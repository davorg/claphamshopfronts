#!/usr/bin/env perl

use v5.36;
use feature 'try';
no warnings 'experimental::try';
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long qw(GetOptions);
use JSON::MaybeXS;
use ClaphamShopfronts::Site;

my ($check, $image_base, $help);

GetOptions(
  'check'        => \$check,
  'image-base=s' => \$image_base,
  'help'         => \$help
) or die "Use --help for usage\n";

if ($help) {
  say 'Usage: perl bin/build-site [--check] [--image-base URL]';
  exit 0;
}

die "Unexpected arguments\n" if @ARGV;

my $result;

try {
  $result = ClaphamShopfronts::Site->new(
    root => "$FindBin::Bin/.."
  )->build(check => $check, image_base => $image_base);
} catch ($error) {
  die "Build failed: $error";
}

print JSON::MaybeXS->new(
  utf8      => 1,
  canonical => 1,
  pretty    => 1,
)->encode($result);
