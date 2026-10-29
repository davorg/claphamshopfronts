package ClaphamShopfronts::Role::ProjectRoot;

use v5.36;
use Moose::Role;
use Path::Tiny qw(path);

has root => (
  is       => 'ro',
  isa      => 'Path::Tiny',
  required => 1,
);

around BUILDARGS => sub ($original, $class, @arguments) {
  my $arguments = $class->$original(@arguments);

  $arguments->{root} = path($arguments->{root})->absolute if exists $arguments->{root};

  return $arguments;
};

no Moose::Role;

1;
