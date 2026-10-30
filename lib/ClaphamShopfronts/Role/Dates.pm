package ClaphamShopfronts::Role::Dates;

use v5.36;
use Moose::Role;
use Time::Piece;

sub parse_date ($self, $value) {
  die "Invalid ISO date: " . ($value // '(missing)') . "\n"
    unless defined $value && $value =~ /^\d{4}-\d{2}-\d{2}$/;

  my $date = Time::Piece->strptime($value, '%Y-%m-%d');

  die "Invalid date: $value\n" unless $date->strftime('%Y-%m-%d') eq $value;

  return $date;
}

sub display_date ($self, $value) {
  my $date = $self->parse_date($value);

  return $date->mday . ' ' . $date->strftime('%B %Y');
}

no Moose::Role;

1;
