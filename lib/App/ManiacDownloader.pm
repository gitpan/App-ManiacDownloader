package App::ManiacDownloader;

use strict;
use warnings;

use MooX qw/late/;
use URI;
use AnyEvent::HTTP qw/http_head http_get/;
use Getopt::Long qw/GetOptionsFromArray/;
use File::Basename qw(basename);
use Fcntl qw( SEEK_SET );
use List::UtilsBy qw(max_by);

use App::ManiacDownloader::_SegmentTask;

our $VERSION = '0.0.2';

my $DEFAULT_NUM_CONNECTIONS = 4;
my $NUM_CONN_BYTES_THRESHOLD = 4_096 * 2;

has '_finished_condvar' => (is => 'rw');
has '_ranges' => (isa => 'ArrayRef', is => 'rw');
has '_url' => (is => 'rw');
has '_url_basename' => (isa => 'Str', is => 'rw');
has '_remaining_connections' => (isa => 'Int', is => 'rw');
has ['_bytes_dled', '_bytes_dled_last_timer'] =>
    (isa => 'Int', is => 'rw', default => sub { return 0;});
has '_stats_timer' => (is => 'rw');
has '_last_timer_time' => (is => 'rw', isa => 'Num');
has '_len' => (is => 'rw', isa => 'Int');

sub _downloading_path
{
    my ($self) = @_;

    return $self->_url_basename . '.mdown-intermediate';
}

sub _start_connection
{
    my ($self, $idx) = @_;

    my $r = $self->_ranges->[$idx];

    sysseek( $r->_fh, $r->_start, SEEK_SET );

    http_get $self->_url,
    headers => { 'Range'
        => sprintf("bytes=%d-%d", $r->_start, $r->_end-1)
    },
    on_body => sub {
        my ($data, $hdr) = @_;

        my $ret = $r->_write_data(\$data);

        $self->_bytes_dled(
            $self->_bytes_dled + $ret->{num_written},
        );
        my $cont = $ret->{should_continue};
        if (! $cont)
        {
            my $largest_r = max_by { $r->_num_remaining } @{$self->_ranges};
            if ($largest_r->_num_remaining < $NUM_CONN_BYTES_THRESHOLD)
            {
                $r->_close;
                if (
                    not
                    $self->_remaining_connections(
                        $self->_remaining_connections() - 1
                    )
                )
                {
                    $self->_finished_condvar->send;
                }
            }
            else
            {
                $largest_r->_split_into($r);
                $self->_start_connection($idx);
            }
        }
        return $cont;
    },
    sub {
        # Do nothing.
        return;
    }
    ;
}

sub _handle_stats_timer
{
    my ($self) = @_;

    my $num_dloaded = $self->_bytes_dled - $self->_bytes_dled_last_timer;

    my $time = AnyEvent->now;
    my $last_time = $self->_last_timer_time;

    printf "Downloaded %i%% (Currently: %.2fKB/s)\r",
        int($self->_bytes_dled * 100 / $self->_len),
        ($num_dloaded / (1024 * ($time-$last_time))),
    ;
    STDOUT->flush;

    $self->_last_timer_time($time);
    $self->_bytes_dled_last_timer($self->_bytes_dled);

    return;
}

sub run
{
    my ($self, $args) = @_;

    my $num_connections = $DEFAULT_NUM_CONNECTIONS;

    my @argv = @{ $args->{argv} };

    if (! GetOptionsFromArray(
        \@argv,
        'k|num-connections=i' => \$num_connections,
    ))
    {
        die "Cannot parse argv - $!";
    }

    my $url_s = shift(@argv)
        or die "No url given.";

    my $url = URI->new($url_s);

    $self->_url($url);
    my $url_path = $url->path();
    my $url_basename = basename($url_path);

    $self->_url_basename($url_basename);

    $self->_finished_condvar(
        scalar(AnyEvent->condvar)
    );

    http_head $url, sub {
        my (undef, $headers) = @_;
        my $len = $headers->{'content-length'};

        if (!defined($len)) {
            die "Cannot find a content-length header.";
        }

        $self->_len($len);

        my @stops = (map { int( ($len * $_) / $num_connections ) }
            0 .. ($num_connections-1));

        push @stops, $len;

        my @ranges = (
            map {
                App::ManiacDownloader::_SegmentTask->new(
                    _start => $stops[$_],
                    _end => $stops[$_+1],
                )
            }
            0 .. ($num_connections-1)
        );

        $self->_ranges(\@ranges);

        $self->_remaining_connections($num_connections);
        foreach my $idx (0 .. $num_connections-1)
        {
            my $r = $ranges[$idx];

            {
                open my $fh, "+>:raw", $self->_downloading_path()
                    or die "${url_basename}: $!";

                $r->_fh($fh);
            }

            $self->_start_connection($idx);
        }

        my $timer = AnyEvent->timer(
            after => 3,
            interval => 3,
            cb => sub {
                $self->_handle_stats_timer;
                return;
            },
        );
        $self->_last_timer_time(AnyEvent->time());
        $self->_stats_timer($timer);

        return;
    };

    $self->_finished_condvar->recv;
    $self->_stats_timer(undef());

    if (! $self->_remaining_connections())
    {
        rename($self->_downloading_path(), $self->_url_basename());
    }

    return;
}

1;

__END__

=pod

=head1 NAME

App::ManiacDownloader - a maniac download accelerator.

=head1 VERSION

version 0.0.2

=head1 SYNOPSIS

    # To download with 10 segments
    $ mdown -k=10 http://path.to.my.url.tld/path-to-file.txt

=head1 DESCRIPTION

This is B<Maniac Downloader>, a maniac download accelerator. It is currently
very incomplete (see the C<TODO.txt> file), but is still somewhat usable.
Maniac Downloader is being written out of necessity out of proving to
improve the download speed of files here (which I suspect is caused by a
misconfiguration of my ISP's networking), and as a result, may prove of
use elsewhere.

=head2 The Secret Sauce

The main improvement of Maniac Downloader over other downloader managers is
that if a segment of the downloaded file finishes, then it splits the
largest remaining segment, and starts another new download, so the slowest
downloads won't delay the completion time by much.

=encoding utf8

=head1 METHODS

=head2 $self->run({argv => [@ARGV]})

Run the application with @ARGV .

=head1 SEE ALSO

=head2 Asynchronous Programming FTW! 2 (with AnyEvent)

L<http://www.slideshare.net/xSawyer/async-programmingftwanyevent>

a talk by Sawyer X that introduced me to L<AnyEvent> of which I made use
for Maniac Downloader.

=head2 “Man Down”

“Man Down” is a song by Rihanna, which happens to have the same initialism
as Maniac Downloader, and which I happen to like, so feel free to check it
out:

L<http://www.youtube.com/watch?v=sEhy-RXkNo0>

=head1 AUTHOR

Shlomi Fish <shlomif@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2013 by Shlomi Fish.

This is free software, licensed under:

  The MIT (X11) License

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website
http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-ManiacDownloader or by email
to bug-app-maniacdownloader@rt.cpan.org.

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 SUPPORT

=head2 Perldoc

You can find documentation for this module with the perldoc command.

  perldoc App::ManiacDownloader

=head2 Websites

The following websites have more information about this module, and may be of help to you. As always,
in addition to those websites please use your favorite search engine to discover more resources.

=over 4

=item *

MetaCPAN

A modern, open-source CPAN search engine, useful to view POD in HTML format.

L<http://metacpan.org/release/App-ManiacDownloader>

=item *

Search CPAN

The default CPAN search engine, useful to view POD in HTML format.

L<http://search.cpan.org/dist/App-ManiacDownloader>

=item *

RT: CPAN's Bug Tracker

The RT ( Request Tracker ) website is the default bug/issue tracking system for CPAN.

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-ManiacDownloader>

=item *

AnnoCPAN

The AnnoCPAN is a website that allows community annotations of Perl module documentation.

L<http://annocpan.org/dist/App-ManiacDownloader>

=item *

CPAN Ratings

The CPAN Ratings is a website that allows community ratings and reviews of Perl modules.

L<http://cpanratings.perl.org/d/App-ManiacDownloader>

=item *

CPAN Forum

The CPAN Forum is a web forum for discussing Perl modules.

L<http://cpanforum.com/dist/App-ManiacDownloader>

=item *

CPANTS

The CPANTS is a website that analyzes the Kwalitee ( code metrics ) of a distribution.

L<http://cpants.perl.org/dist/overview/App-ManiacDownloader>

=item *

CPAN Testers

The CPAN Testers is a network of smokers who run automated tests on uploaded CPAN distributions.

L<http://www.cpantesters.org/distro/A/App-ManiacDownloader>

=item *

CPAN Testers Matrix

The CPAN Testers Matrix is a website that provides a visual overview of the test results for a distribution on various Perls/platforms.

L<http://matrix.cpantesters.org/?dist=App-ManiacDownloader>

=item *

CPAN Testers Dependencies

The CPAN Testers Dependencies is a website that shows a chart of the test results of all dependencies for a distribution.

L<http://deps.cpantesters.org/?module=App::ManiacDownloader>

=back

=head2 Bugs / Feature Requests

Please report any bugs or feature requests by email to C<bug-app-maniacdownloader at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=App-ManiacDownloader>. You will be automatically notified of any
progress on the request by the system.

=head2 Source Code

The code is open to the world, and available for you to hack on. Please feel free to browse it and play
with it, or whatever. If you want to contribute patches, please send me a diff or prod me to pull
from your repository :)

L<http://bitbucket.org/shlomif/perl-App-ManiacDownloader>

  hg clone ssh://hg@bitbucket.org/shlomif/perl-App-ManiacDownloader

=cut
