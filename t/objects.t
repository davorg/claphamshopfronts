use v5.36;
use feature 'try';
no warnings 'experimental::try';
use Test::More;
use lib 'lib';
use Path::Tiny qw(path);
use ClaphamShopfronts::Ingest;
use ClaphamShopfronts::Site;

for my $class (qw(ClaphamShopfronts::Ingest ClaphamShopfronts::Site)) {
  subtest "$class has a Moose constructor" => sub {
    my $object = $class->new(root => '.');

    isa_ok $object, 'Moose::Object';
    isa_ok $object->root, 'Path::Tiny';
    is "" . $object->root, "" . path('.')->absolute, 'relative roots normalise to absolute paths';
    ok $class->meta->is_immutable, 'class is immutable';

    my $arguments = {root => path('.')};
    my $from_hashref = $class->new($arguments);

    is "" . $from_hashref->root, "" . $object->root, 'hashref arguments and Path::Tiny roots also work';
    is "" . $arguments->{root}, '.', 'constructor does not modify caller arguments';

    try {
      $class->new;
      fail 'project root is required';
    } catch ($error) {
      like $error, qr/Attribute \(root\) is required/, 'project root is required';
    }
  };
}

done_testing;
