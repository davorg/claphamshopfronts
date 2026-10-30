package ClaphamShopfronts::Role::WebURLs;

use v5.36;
use Moose::Role;
use URI;

sub validate_web_url ($self, $value) {
  my $url = URI->new($value);

  die "Expected an HTTP(S) URL: $value\n"
    unless ($url->scheme // '') =~ /^https?$/ && $url->can('host') && $url->host;

  return $value;
}

no Moose::Role;

1;
