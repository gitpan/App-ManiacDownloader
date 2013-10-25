
use strict;
use warnings;

use Module::Build 0.3601;
use lib qw{inc}; use Test::Run::Builder;

my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.3601"
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "a maniac download accelerator.",
  "dist_author" => [
    "Shlomi Fish <shlomif\@cpan.org>"
  ],
  "dist_name" => "App-ManiacDownloader",
  "dist_version" => "0.0.3",
  "license" => "mit",
  "module_name" => "App::ManiacDownloader",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "AnyEvent::HTTP" => 0,
    "Fcntl" => 0,
    "File::Basename" => 0,
    "Getopt::Long" => 0,
    "JSON" => 0,
    "List::Util" => 0,
    "List::UtilsBy" => 0,
    "MooX" => 0,
    "URI" => 0,
    "autodie" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "script_files" => [
    "bin/mdown",
    "bin/mdown"
  ],
  "test_requires" => {
    "File::Spec" => 0,
    "File::Temp" => 0,
    "IO::Handle" => 0,
    "IPC::Open3" => 0,
    "Test::More" => 0
  }
);


unless ( eval { Module::Build->VERSION(0.4004) } ) {
  my $tr = delete $module_build_args{test_requires};
  my $br = $module_build_args{build_requires};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

my $build = Test::Run::Builder->new(%module_build_args);

$build->create_build_script;
