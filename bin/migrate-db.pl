#!/usr/bin/env perl
use v5.36;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JSON::MaybeXS;
use ClaphamShopfronts::Migrate;

die "Usage: perl bin/migrate-db.pl\n" if @ARGV;

my $result = eval {
  ClaphamShopfronts::Migrate->migrate("$FindBin::Bin/..")
};

die "Migration failed: $@" if $@;

print JSON::MaybeXS->new(
  utf8 => 1,
  canonical => 1,
  pretty => 1,
)->encode($result);
