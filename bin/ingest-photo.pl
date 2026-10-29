#!/usr/bin/env perl

use v5.36;
use feature 'try';
no warnings 'experimental::try';
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long qw(GetOptions);
use JSON::MaybeXS;
use ClaphamShopfronts::Ingest;

my ($dry_run, $help);

GetOptions(
  'dry-run' => \$dry_run,
  'help'    => \$help
) or die "Use --help for usage\n";

if ($help) {
  say 'Usage: perl bin/ingest-photo.pl [--dry-run] data/photos/PHOTO.json';
  exit 0;
}

@ARGV or die "A reviewed photograph manifest is required\n";
my $manifest = shift @ARGV;
die "Unexpected arguments\n" if @ARGV;

my $result;

try {
  $result = ClaphamShopfronts::Ingest->new(
    root => "$FindBin::Bin/.."
  )->ingest($manifest, dry_run => $dry_run);
} catch ($error) {
  die "Import failed: $error";
}

print JSON::MaybeXS->new(
  utf8      => 1,
  canonical => 1,
  pretty    => 1,
)->encode($result);
