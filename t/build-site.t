use v5.36;
use utf8;
use Test::More;
use lib 'lib', 't/lib';
use ClaphamTest qw(fixture seed_page);
use ClaphamShopfronts::Site;
use ClaphamShopfronts::Util qw(file_sha);

subtest 'DBIC data, TT escaping, history and repeatable output' => sub {
  my ($root, $schema) = fixture();
  seed_page($root, $schema);
  my $database = $root->child('db/claphamshopfront.db');
  my $before = file_sha($database);
  my $builder = ClaphamShopfronts::Site->new(root => $root);
  my $result = $builder->build;
  is $result->{shopfront_pages}, 1, 'one published shopfront';
  my $page = $root->child('docs/shopfronts/sw4-7ts-7/index.html')->slurp_utf8;
  for my $text ('7 Clapham High Street, London', 'Second-hand clothing shop', 'Vacant when photographed',
      'Reported · unconfirmed', '31 January 2025', 'The exact closing date is unknown.', 'The old shop &amp; its shutter.',
      'href="../../#the-project"', 'href="../../styles.css"', 'data-photo-modal="photo-modal"',
      '<dialog class="photo-modal"', 'aria-label="Close photograph"', 'src="../../photo-modal.js"',
      'aria-label="Previous photograph"', 'aria-label="Next photograph"', 'aria-describedby="photo-modal-details"',
      'aria-live="polite" aria-atomic="true"') {
    ok index($page, $text) >= 0, "page contains $text";
  }
  unlike $page, qr/Internal: not for publication/, 'internal database notes stay private';
  like $root->child('docs/index.html')->slurp_utf8, qr{href="shopfronts/sw4-7ts-7/#photo-1"}, 'homepage links to its photograph in the record';
  is file_sha($database), $before, 'builder did not modify database';
  is_deeply $builder->build->{changed_files}, [], 'second build is unchanged';
  is_deeply $builder->build(check => 1)->{changed_files}, [], 'check mode succeeds without writes';

  $schema->resultset('Business')->first->update({name => 'Pure & <Vintage> "Shop"'});
  $schema->resultset('Photo')->first->update({caption => '<script>alert("x")</script>'});
  eval {$builder->build(check => 1)};
  like $@, qr/need rebuilding/, 'database edit makes generated page stale';
  $builder->build;
  $page = $root->child('docs/shopfronts/sw4-7ts-7/index.html')->slurp_utf8;
  like $page, qr/Pure &amp; &lt;Vintage&gt; &quot;Shop&quot;/, 'business escaped by TT';
  like $page, qr/&lt;script&gt;alert\(&quot;x&quot;\)&lt;\/script&gt;/, 'caption escaped by TT';
  unlike $page, qr{<script>alert\("x"\)</script>}, 'caption cannot become executable markup';
};

subtest 'image base changes without database migration' => sub {
  my ($root, $schema) = fixture();
  seed_page($root, $schema);
  my $before = file_sha($root->child('db/claphamshopfront.db'));
  ClaphamShopfronts::Site->new(root => $root)->build(image_base => 'https://images.claphamshopfronts.com/');
  like $root->child('docs/shopfronts/sw4-7ts-7/index.html')->slurp_utf8,
    qr{src="https://images.claphamshopfronts.com/photos/2026/04/sample.webp"}, 'record uses configured host';
  like $root->child('docs/index.html')->slurp_utf8,
    qr{src="https://images.claphamshopfronts.com/photos/2026/04/sample-small.webp"}, 'homepage uses configured host';
  is file_sha($root->child('db/claphamshopfront.db')), $before, 'database unchanged';
};

subtest 'missing image stops the build before output changes' => sub {
  my ($root, $schema) = fixture();
  seed_page($root, $schema);
  my $home = $root->child('docs/index.html')->slurp_raw;
  $root->child('docs/images/photos/2026/04/sample-small.webp')->remove;
  eval {ClaphamShopfronts::Site->new(root => $root)->build};
  like $@, qr/Published image not found/, 'missing image rejected';
  ok !$root->child('docs/shopfronts/sw4-7ts-7/index.html')->exists, 'no partial shopfront page';
  is $root->child('docs/index.html')->slurp_raw, $home, 'homepage unchanged';
};

subtest 'recent photos sort by capture date, not insertion order' => sub {
  my ($root, $schema) = fixture();
  my $photo = seed_page($root, $schema);
  $schema->resultset('Photo')->create({unit_id => 1, taken_on => '2026-03-01', source_type => 'own_photo', filename => $photo->filename, caption => 'Older capture'});
  ClaphamShopfronts::Site->new(root => $root)->build;
  my $home = $root->child('docs/index.html')->slurp_utf8;
  my ($section) = $home =~ /BEGIN GENERATED RECENT PHOTOGRAPHS -->(.*?)<!-- END GENERATED/s;
  ok index($section, 'datetime="2026-04-03"') < index($section, 'datetime="2026-03-01"'), 'newer capture appears first';
};

subtest 'read-only schema and SQLite constraints' => sub {
  my ($root, $schema) = fixture();
  is scalar($schema->sources), 11, 'DBIC maps all eleven tables';
  is $schema->storage->dbh->selectrow_array('PRAGMA foreign_keys'), 1, 'foreign keys enabled';
  eval {$schema->resultset('Unit')->create({site_id => 999, unit_code => 'ORPHAN', slug => 'orphan-unit', valid_from => '2026-01-01'})};
  like $@, qr/FOREIGN KEY constraint failed/, 'orphan prevented by SQLite';
  my $readonly = ClaphamShopfronts::Schema->connect_database($root->child('db/claphamshopfront.db'), read_only => 1);
  eval {$readonly->resultset('Tag')->create({name => 'write attempt'})};
  like $@, qr/readonly database/, 'read-only connection cannot write';
};

subtest 'new occupant changes the latest record without relabelling earlier evidence' => sub {
  my ($root, $schema) = fixture();
  my $old_photo = seed_page($root, $schema);
  my $unit = $old_photo->unit;
  $unit->create_related('occupancies', {occupancy_status => 'vacant', valid_from => '2026-04-03', valid_to => '2026-04-03'});
  my $type = $schema->resultset('BusinessType')->create({name => 'Hair salon'});
  my $salon = $type->create_related('businesses', {name => 'Tony Voyage', normalised_name => 'tony voyage', website => 'https://www.tonyvoyage.com/'});
  $unit->create_related('occupancies', {business_id => $salon->id, occupancy_status => 'occupied', valid_from => '2026-10-29'});
  my $observation = $unit->create_related('observations', {business_id => $salon->id, observed_status => 'occupied', observed_business_name => 'Tony Voyage', observed_on => '2026-10-29'});
  $unit->create_related('photos', {observation_id => $observation->id, taken_on => '2026-10-29', source_type => 'own_photo', filename => 'photos/2026/04/sample-now.webp', caption => 'The salon as photographed in October.'});
  for my $suffix ('.webp', '-small.webp') {
    $root->child('docs/images/photos/2026/04', "sample$suffix")->copy($root->child('docs/images/photos/2026/04', "sample-now$suffix"));
  }
  ClaphamShopfronts::Site->new(root => $root)->build;
  my $page = $root->child('docs/shopfronts/sw4-7ts-7/index.html')->slurp_utf8;
  like $page, qr{<h1>Tony Voyage</h1>}, 'latest identity comes from its observation business';
  like $page, qr/Hair salon/, 'latest category comes from the new business';
  like $page, qr/Pure Vintage: closed by this date/, 'old closure is kept in its own business context';
  like $page, qr/Tony Voyage photographed here/, 'later photo is a new history event';
  like $page, qr/exact changeover date between the observations on 3 April 2026 and 29 October 2026/, 'uncertain gap explained';
  like $page, qr/Earlier photographs/, 'earlier evidence remains visible';
  like $page, qr{id="photo-1"}, 'old photograph keeps a direct link';
  like $page, qr{data-photo-name="Pure Vintage"}, 'old modal trigger retains the old business identity';
  like $page, qr{data-photo-name="Tony Voyage"}, 'new modal trigger identifies the salon';
  my $home = $root->child('docs/index.html')->slurp_utf8;
  my ($recent) = $home =~ /BEGIN GENERATED RECENT PHOTOGRAPHS -->(.*?)<!-- END GENERATED/s;
  ok index($recent, '<h3>Tony Voyage</h3>') < index($recent, '<h3>Pure Vintage</h3>'), 'homepage places the new photograph first';
  like $recent, qr{href="shopfronts/sw4-7ts-7/#photo-1"}, 'old card links to old photo rather than only the latest view';
};

done_testing;
