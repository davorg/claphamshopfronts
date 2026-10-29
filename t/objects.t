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

    my $string_arguments = {root => '.'};
    my $from_string = $class->new($string_arguments);

    is "" . $from_string->root, "" . $object->root, 'hashref string roots also normalise';
    is_deeply $string_arguments, {root => '.'}, 'caller-owned string arguments stay unchanged';

    my $from_path = $class->new(root => path('.'));

    is "" . $from_path->root, "" . $object->root, 'named Path::Tiny roots also normalise';

    try {
      $object->root(path('/tmp'));
      fail 'project root is read-only';
    } catch ($error) {
      like $error, qr/read-only accessor/, 'project root is read-only';
    }

    try {
      $class->new;
      fail 'project root is required';
    } catch ($error) {
      like $error, qr/Attribute \(root\) is required/, 'project root is required';
    }
  };
}

done_testing;
