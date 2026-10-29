use v5.36;
use feature 'try';
no warnings 'experimental::try';
use utf8;
use Test::More;
use lib 'lib', 't/lib';
use ClaphamTest qw(fixture seed_page setup_original save_json snapshot);
use ClaphamShopfronts::Util qw(unit_slug validate_slug);
use ClaphamShopfronts::Ingest;
use ClaphamShopfronts::Site;

subtest 'address-based slug conventions' => sub {
  is unit_slug('SW4 7TS', '7 Clapham High Street, London'), 'sw4-7ts-7', 'postcode and number';
  is unit_slug(' sw47ts ', '7A Clapham High Street'), 'sw4-7ts-7a', 'letter suffix and postcode normalisation';
  is unit_slug('SW4 7TS', '7–9 Clapham High Street'), 'sw4-7ts-7-9', 'address range';
  is unit_slug('SW4 7TS', '7 - 9A Clapham High Street'), 'sw4-7ts-7-9a', 'range with spaces and letter suffix';
  is unit_slug(undef, 'Named premises', 'sw4-7ts-7-u2'), 'sw4-7ts-7-u2',
    'explicit slug supports shared or unusual addresses';

  for my $slug ('SW4-7TS-7', '../elsewhere', 'sw4--7ts-7', 'sw4 7ts-7', '') {
    try {
      validate_slug($slug);
      fail 'invalid path rejected';
    } catch ($error) {
      like $error, qr/Unit slug/, 'invalid path rejected';
    }
  }

  try {
    unit_slug(undef, '7 Clapham High Street');
    fail 'missing postcode needs an explicit choice';
  } catch ($error) {
    like $error, qr/supply unit.slug/, 'missing postcode needs an explicit choice';
  }

  try {
    unit_slug('SW4 7TS', 'Named premises');
    fail 'missing number needs an explicit choice';
  } catch ($error) {
    like $error, qr/supply unit.slug/, 'missing number needs an explicit choice';
  }
};

subtest 'new imports generate and store a slug once' => sub {
  my ($root, $schema) = fixture();
  my ($manifest, $data) = setup_original($root);
  my $importer = ClaphamShopfronts::Ingest->new(root => $root);

  is $importer->ingest($manifest, dry_run => 1)->{slug}, 'sw4-7ts-7', 'dry run previews slug';
  $importer->ingest($manifest);

  my $unit = $schema->resultset('Unit')->first;

  is $unit->slug, 'sw4-7ts-7', 'slug persisted on unit';
  $unit->site->update({
    postcode => 'SW4 9ZZ'
  });
  ClaphamShopfronts::Site->new(root => $root)->build;
  ok $root->child('docs/shopfronts/sw4-7ts-7/index.html')->is_file, 'address correction does not change existing URL';
  ok !$root->child('docs/shopfronts/sw4-9zz-7/index.html')->exists, 'builder never silently recomputes slug';
  ok !$root->child('docs/shopfronts/chs0001-u01/index.html')->exists, 'unpublished code-based URL not generated';
};

subtest 'collisions require an explicit unit extension' => sub {
  my ($root, $schema) = fixture();
  my ($first) = setup_original($root);
  my $importer = ClaphamShopfronts::Ingest->new(root => $root);

  $importer->ingest($first);

  my ($manifest, $data) = setup_original(
    $root,
    name => 'next-unit.jpg',
    date => '2026-10-29'
  );

  $data->{unit}{unit_code} = 'CHS0001-U02';
  save_json($manifest, $data);

  my $before = snapshot($root);

  try {
    $importer->ingest($manifest);
    fail 'duplicate address slug rejected';
  } catch ($error) {
    like $error, qr/already used/, 'duplicate address slug rejected';
  }

  is_deeply snapshot($root), $before, 'collision leaves incoming photo and database unchanged';
  $data->{unit}{slug} = 'sw4-7ts-7-u2';
  save_json($manifest, $data);
  $importer->ingest($manifest);
  is $schema->resultset('Unit')->find({
    unit_code => 'CHS0001-U02'
  })->slug, 'sw4-7ts-7-u2', 'explicit extension stored';
  try {
    $schema->resultset('Unit')->create({
      site_id    => 1,
      unit_code  => 'DUPLICATE',
      slug       => 'sw4-7ts-7',
      valid_from => '2026-10-29'
    });
    fail 'database enforces uniqueness independently';
  } catch ($error) {
    like $error, qr/UNIQUE constraint failed/, 'database enforces uniqueness independently';
  }

  try {
    $schema->resultset('Unit')->create({site_id => 1, unit_code => 'MISSING-SLUG', valid_from => '2026-10-29'});
    fail 'database requires a stored slug';
  } catch ($error) {
    like $error, qr/NOT NULL constraint failed/, 'database requires a stored slug';
  }
};

done_testing;
