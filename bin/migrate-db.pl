#!/usr/bin/env perl
use v5.36;
use feature 'try';
no warnings 'experimental::try';
use FindBin;
use lib "$FindBin::Bin/../lib";
use JSON::MaybeXS;
use ClaphamShopfronts::Migrate;

die "Usage: perl bin/migrate-db.pl\n" if @ARGV;

my $result;

try {
  $result = ClaphamShopfronts::Migrate->migrate("$FindBin::Bin/..");
} catch ($error) {
  die "Migration failed: $error";
}

print JSON::MaybeXS->new(
  utf8 => 1,
  canonical => 1,
  pretty => 1,
)->encode($result);
