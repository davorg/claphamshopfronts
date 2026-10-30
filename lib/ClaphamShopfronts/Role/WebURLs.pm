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

sub absolute_web_url ($self, $value, $base) {
  return $self->validate_web_url(URI->new_abs($value, $base)->as_string);
}

no Moose::Role;

1;
