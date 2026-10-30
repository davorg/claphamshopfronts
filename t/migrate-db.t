use v5.36;
use feature 'try';
no warnings 'experimental::try';
use Test::More;
use lib 'lib', 't/lib';
use ClaphamTest qw(fixture seed_page snapshot save_json read_json);
use ClaphamShopfronts::Migrate;

subtest 'legacy data is preserved and identified only from matching reviewed metadata' => sub {
  my ($root, $schema) = fixture(legacy => 1);
  my $photo = seed_page($root, $schema);
  my $data = read_json($root->child('data/photos/PXL_20260403_065904338.json'));

  $photo->update({
    filename => 'photos/2026/04/PXL_20260403_065904338.webp',
    notes    => 'Original SHA-256: ' . $data->{original_sha256}
  });
  $schema->storage->disconnect;

  my $result = ClaphamShopfronts::Migrate->migrate($root);

  is $result->{result}, 'migrated', 'schema upgraded';
  is $result->{identified_observations}, 1, 'reviewed legacy observation identified';
  $schema = ClaphamShopfronts::Schema->connect_database($root->child('db/claphamshopfront.db'));
  is $schema->storage->dbh->selectrow_array('PRAGMA user_version'), 2, 'version updated';
  is $schema->resultset('Unit')->first->slug, 'sw4-7ts-7', 'address slug assigned while preserving unit';
  is $schema->resultset('Photo')->count, 1, 'photo preserved';
  is $schema->resultset('Photo')->first->observation->business->name, 'Pure Vintage',
    'vacant observation identifies former business';
  is $schema->resultset('Photo')->first->observation->observed_status, 'vacant',
    'identification does not change occupancy state';

  my $before = snapshot($root);

  is ClaphamShopfronts::Migrate->migrate($root)->{result}, 'already_current', 'safe migration repeat';
  is_deeply snapshot($root), $before, 'repeat changes no files or database bytes';
};

subtest 'unmatched legacy evidence rolls the schema migration back' => sub {
  my ($root, $schema) = fixture(legacy => 1);
  my $photo = seed_page($root, $schema);

  $photo->update({
    filename => 'photos/2026/04/PXL_20260403_065904338.webp',
    notes    => 'different evidence'
  });
  $schema->storage->disconnect;
  try {
    ClaphamShopfronts::Migrate->migrate($root);
    fail 'mismatched metadata refused';
  } catch ($error) {
    like $error, qr/evidence does not match/, 'mismatched metadata refused';
  }

  $schema = ClaphamShopfronts::Schema->connect_database($root->child('db/claphamshopfront.db'), allow_old_schema => 1);
  is $schema->storage->dbh->selectrow_array('PRAGMA user_version'), 0, 'version change rolled back';

  my $columns = $schema->storage->dbh->selectall_arrayref(
    'PRAGMA table_info(observations)', {
      Slice => {}
    }
  );

  ok !grep($_->{name} eq 'business_id', @$columns), 'column addition rolled back too';
  is $schema->resultset('Photo')->count, 1, 'original photo still present';
};

subtest 'version-one upgrade preserves records, views, indexes and timestamp triggers' => sub {
  my ($root, $schema) = fixture(version => 1);

  seed_page($root, $schema);
  $schema->resultset('Occupancy')->create({
    unit_id          => 1,
    occupancy_status => 'vacant',
    valid_from       => '2026-04-03'
  });

  my $dbh = $schema->storage->dbh;

  $dbh->do(q{UPDATE units SET created_at = '2020-01-01 00:00:00', updated_at = '2020-01-01 00:00:00'});

  my $before = $dbh->selectrow_hashref('SELECT * FROM units');
  my $objects = $dbh->selectall_arrayref(
    q{SELECT type, name, sql FROM sqlite_master WHERE type IN ('view', 'trigger') OR (type = 'index' AND sql IS NOT NULL) ORDER BY name}
  );

  $schema->storage->disconnect;

  my $result = ClaphamShopfronts::Migrate->migrate($root);

  is $result->{assigned_slugs}, 1, 'one slug assigned';
  is $result->{identified_observations}, 0, 'existing business identities retained';
  $schema = ClaphamShopfronts::Schema->connect_database($root->child('db/claphamshopfront.db'));
  $dbh = $schema->storage->dbh;

  my $after = $dbh->selectrow_hashref('SELECT * FROM units');

  is delete $after->{slug}, 'sw4-7ts-7', 'new slug stored';
  is_deeply $after, $before, 'all earlier unit fields including ID and timestamps preserved';
  is_deeply $dbh->selectall_arrayref(
    q{SELECT type, name, sql FROM sqlite_master WHERE type IN ('view', 'trigger') OR (type = 'index' AND sql IS NOT NULL) ORDER BY name}
  ), $objects, 'views, explicit indexes and triggers preserved';
  is $schema->resultset('Photo')->first->observation->business->name, 'Pure Vintage',
    'photo and business references preserved';
  is $dbh->selectrow_array('SELECT count(*) FROM current_non_occupied_units'), 1, 'dependent views still work';
  is_deeply $dbh->selectall_arrayref('PRAGMA foreign_key_check'), [], 'all foreign keys valid';
  is $dbh->selectrow_array('PRAGMA foreign_keys'), 1, 'foreign key enforcement enabled';
  $dbh->do(q{UPDATE units SET updated_at = '2000-01-01 00:00:00'});
  isnt $dbh->selectrow_array('SELECT updated_at FROM units'), '2000-01-01 00:00:00', 'timestamp trigger still works';
  try {
    $dbh->do(q{INSERT INTO units (site_id, unit_code, slug, valid_from) VALUES (1, 'DUP', 'sw4-7ts-7', '2026-10-29')});
    fail 'migrated schema enforces slug uniqueness';
  } catch ($error) {
    like $error, qr/UNIQUE constraint failed/, 'migrated schema enforces slug uniqueness';
  }

  try {
    $dbh->do(q{INSERT INTO units (site_id, unit_code, valid_from) VALUES (1, 'MISSING', '2026-10-29')});
    fail 'migrated schema requires slug';
  } catch ($error) {
    like $error, qr/NOT NULL constraint failed/, 'migrated schema requires slug';
  }
};

subtest 'migration collision rolls back and accepts an explicit unit extension' => sub {
  my ($root, $schema) = fixture(version => 1);

  seed_page($root, $schema);
  $schema->resultset('Unit')->create({
    site_id    => 1,
    unit_code  => 'CHS0001-U02',
    valid_from => '2026-04-03'
  });
  $schema->storage->disconnect;

  my $before = snapshot($root);

  try {
    ClaphamShopfronts::Migrate->migrate($root);
    fail 'ambiguous address refused';
  } catch ($error) {
    like $error, qr/Slug collision/, 'ambiguous address refused';
  }

  is_deeply snapshot($root), $before, 'collision changes no files or database bytes';

  my $data = read_json($root->child('data/photos/PXL_20260403_065904338.json'));

  $data->{unit} = {
    unit_code => 'CHS0001-U02',
    slug      => 'sw4-7ts-7-u2'
  };
  save_json($root->child('data/photos/second-unit.json'), $data);
  is ClaphamShopfronts::Migrate->migrate($root)->{assigned_slugs}, 2, 'explicit extension resolves ambiguity';
  $schema = ClaphamShopfronts::Schema->connect_database($root->child('db/claphamshopfront.db'));
  is $schema->resultset('Unit')->find({
    unit_code => 'CHS0001-U02'
  })->slug, 'sw4-7ts-7-u2', 'reviewed extension persisted';
};

done_testing;
