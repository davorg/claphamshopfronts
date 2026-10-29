use v5.36;
use feature 'try';
no warnings 'experimental::try';
use utf8;
use Test::More;
use lib 'lib', 't/lib';
use ClaphamTest qw(fixture seed_page snapshot);
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

  for my $text (
    '7 Clapham High Street, London',
    'Second-hand clothing shop',
    'Vacant when photographed',
    'Reported · unconfirmed',
    '31 January 2025',
    'The exact closing date is unknown.',
    'The old shop &amp; its shutter.',
    'href="../../#the-project"',
    'href="../../styles.css"',
    'data-photo-modal="photo-modal"',
    '<dialog class="photo-modal"',
    'aria-label="Close photograph"',
    'src="../../photo-modal.js"',
    'aria-label="Previous photograph"',
    'aria-label="Next photograph"',
    'aria-describedby="photo-modal-details"',
    'aria-live="polite" aria-atomic="true"'
  ) {
    ok index($page, $text) >= 0, "page contains $text";
  }

  unlike $page, qr/Internal: not for publication/, 'internal database notes stay private';
  like $root->child('docs/index.html')->slurp_utf8, qr{href="shopfronts/sw4-7ts-7/#photo-1"},
    'homepage links to its photograph in the record';
  is file_sha($database), $before, 'builder did not modify database';
  is_deeply $builder->build->{changed_files}, [], 'second build is unchanged';
  is_deeply $builder->build(check => 1)->{changed_files}, [], 'check mode succeeds without writes';

  $schema->resultset('Business')->first->update({
    name => 'Pure & <Vintage> "Shop"'
  });
  $schema->resultset('Photo')->first->update({
    caption => '<script>alert("x")</script>'
  });
  try {
    $builder->build(check => 1);
    fail 'database edit makes generated page stale';
  } catch ($error) {
    like $error, qr/need rebuilding/, 'database edit makes generated page stale';
  }

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
  like $root->child('docs/photos/index.html')->slurp_utf8,
    qr{src="https://images.claphamshopfronts.com/photos/2026/04/sample-small.webp"}, 'archive uses configured host';
  is file_sha($root->child('db/claphamshopfront.db')), $before, 'database unchanged';
};

subtest 'missing image stops the build before output changes' => sub {
  my ($root, $schema) = fixture();

  seed_page($root, $schema);

  my $home = $root->child('docs/index.html')->slurp_raw;

  $root->child('docs/images/photos/2026/04/sample-small.webp')->remove;
  try {
    ClaphamShopfronts::Site->new(root => $root)->build;
    fail 'missing image rejected';
  } catch ($error) {
    like $error, qr/Published image not found/, 'missing image rejected';
  }

  ok !$root->child('docs/shopfronts/sw4-7ts-7/index.html')->exists, 'no partial shopfront page';
  is $root->child('docs/index.html')->slurp_raw, $home, 'homepage unchanged';
};

subtest 'a late template failure preserves the complete existing output' => sub {
  my ($root, $schema) = fixture();
  my $photo = seed_page($root, $schema);

  ClaphamShopfronts::Site->new(root => $root)->build;
  $photo->update({
    caption => 'A revised caption that needs publishing.'
  });
  $schema->storage->disconnect;

  # The gallery renders after unit pages have already been prepared in memory.
  $root->child('templates/all-photos.tt')->append_utf8('[% missing_archive_value %]');

  my $before = snapshot($root);

  try {
    ClaphamShopfronts::Site->new(root => $root)->build;
    fail 'invalid gallery template rejected';
  } catch ($error) {
    like "$error", qr/missing_archive_value/, 'invalid gallery template rejected';
  }

  is_deeply snapshot($root), $before, 'late rendering failure leaves all pages and database bytes unchanged';
};

subtest 'recent photos sort by capture date, not insertion order' => sub {
  my ($root, $schema) = fixture();
  my $photo = seed_page($root, $schema);

  for my $suffix ('.webp', '-small.webp') {
    $root->child('docs/images/photos/2026/04', "sample$suffix")
      ->copy($root->child('docs/images/photos/2026/04', "older$suffix"));
  }

  $schema->resultset('Photo')->create({
    unit_id     => 1,
    taken_on    => '2026-03-01',
    source_type => 'own_photo',
    filename    => 'photos/2026/04/older.webp',
    caption     => 'Older capture'
  });
  ClaphamShopfronts::Site->new(root => $root)->build;

  my $home = $root->child('docs/index.html')->slurp_utf8;
  my ($section) = $home =~ /BEGIN GENERATED RECENT PHOTOGRAPHS -->(.*?)<!-- END GENERATED/s;

  ok index($section, 'datetime="2026-04-03"') < index($section, 'datetime="2026-03-01"'), 'newer capture appears first';
};

subtest 'read-only schema and SQLite constraints' => sub {
  my ($root, $schema) = fixture();

  is scalar($schema->sources), 11, 'DBIC maps all eleven tables';
  is $schema->storage->dbh->selectrow_array('PRAGMA foreign_keys'), 1, 'foreign keys enabled';
  try {
    $schema->resultset('Unit')->create({
      site_id    => 999,
      unit_code  => 'ORPHAN',
      slug       => 'orphan-unit',
      valid_from => '2026-01-01'
    });
    fail 'orphan prevented by SQLite';
  } catch ($error) {
    like $error, qr/FOREIGN KEY constraint failed/, 'orphan prevented by SQLite';
  }

  my $readonly = ClaphamShopfronts::Schema->connect_database($root->child('db/claphamshopfront.db'), read_only => 1);

  try {
    $readonly->resultset('Tag')->create({name => 'write attempt'});
    fail 'read-only connection cannot write';
  } catch ($error) {
    like $error, qr/readonly database/, 'read-only connection cannot write';
  }
};

subtest 'new occupant changes the latest record without relabelling earlier evidence' => sub {
  my ($root, $schema) = fixture();
  my $old_photo = seed_page($root, $schema);
  my $unit = $old_photo->unit;

  $unit->create_related(
    'occupancies', {
      occupancy_status => 'vacant',
      valid_from       => '2026-04-03',
      valid_to         => '2026-04-03'
    }
  );

  my $type = $schema->resultset('BusinessType')->create({
    name => 'Hair salon'
  });

  my $salon = $type->create_related(
    'businesses', {
      name            => 'Tony Voyage',
      normalised_name => 'tony voyage',
      website         => 'https://www.tonyvoyage.com/'
    }
  );

  $unit->create_related(
    'occupancies', {
      business_id      => $salon->id,
      occupancy_status => 'occupied',
      valid_from       => '2026-10-29'
    }
  );

  my $observation = $unit->create_related(
    'observations', {
      business_id            => $salon->id,
      observed_status        => 'occupied',
      observed_business_name => 'Tony Voyage',
      observed_on            => '2026-10-29'
    }
  );

  $unit->create_related(
    'photos', {
      observation_id => $observation->id,
      taken_on       => '2026-10-29',
      source_type    => 'own_photo',
      filename       => 'photos/2026/04/sample-now.webp',
      caption        => 'The salon as photographed in October.'
    }
  );

  for my $suffix ('.webp', '-small.webp') {
    $root->child('docs/images/photos/2026/04', "sample$suffix")
      ->copy($root->child('docs/images/photos/2026/04', "sample-now$suffix"));
  }

  ClaphamShopfronts::Site->new(root => $root)->build;

  my $page = $root->child('docs/shopfronts/sw4-7ts-7/index.html')->slurp_utf8;

  like $page, qr{<h1>Tony Voyage</h1>}, 'latest identity comes from its observation business';
  like $page, qr/Hair salon/, 'latest category comes from the new business';
  like $page, qr/Pure Vintage: closed by this date/, 'old closure is kept in its own business context';
  like $page, qr/Tony Voyage photographed here/, 'later photo is a new history event';
  like $page, qr/exact changeover date between the observations on 3 April 2026 and 29 October 2026/,
    'uncertain gap explained';
  like $page, qr/Earlier photographs/, 'earlier evidence remains visible';
  like $page, qr{id="photo-1"}, 'old photograph keeps a direct link';
  like $page, qr{data-photo-name="Pure Vintage"}, 'old modal trigger retains the old business identity';
  like $page, qr{data-photo-name="Tony Voyage"}, 'new modal trigger identifies the salon';

  my $home = $root->child('docs/index.html')->slurp_utf8;
  my ($recent) = $home =~ /BEGIN GENERATED RECENT PHOTOGRAPHS -->(.*?)<!-- END GENERATED/s;

  ok index($recent, '<h3>Tony Voyage</h3>') < index($recent, '<h3>Pure Vintage</h3>'),
    'homepage places the new photograph first';
  like $recent, qr{href="shopfronts/sw4-7ts-7/#photo-1"},
    'old card links to old photo rather than only the latest view';
};

subtest 'published history is distinguished from unconfirmed reports and photo observations' => sub {
  my ($root, $schema) = fixture();

  seed_page($root, $schema);

  my $config = ClaphamShopfronts::Util::read_json($root->child('data/site.json'));

  $config->{shopfronts}[0]{sourced_events} = [{
    date         => '2020',
    title        => 'Published closure announcement',
    description  => 'The business confirms its final trading day at this address.',
    source_url   => 'https://example.com/closure',
    source_label => 'Company announcement',
  }];
  push @{$config->{shopfronts}[0]{reported_events}}, {
    date        => '2025-12',
    title       => 'Departure reported by owner',
    description => 'Reported departure month; exact day unknown.',
  };
  ClaphamTest::save_json($root->child('data/site.json'), $config);
  ClaphamShopfronts::Site->new(root => $root)->build;

  my $page = $root->child('docs/shopfronts/sw4-7ts-7/index.html')->slurp_utf8;

  like $page, qr{Published source</span>\s*<h3>Published closure announcement</h3>},
    'sourced event has its own evidence label';
  like $page, qr{href="https://example.com/closure">Company announcement}, 'source is publicly linked';
  like $page, qr{Reported · unconfirmed}, 'separate unconfirmed event keeps its label';
  like $page, qr{<time datetime="2020">2020</time>}, 'year-only evidence keeps its precision';
  like $page, qr{<time datetime="2025-12">December 2025</time>},
    'month-only owner report needs no invented day or source URL';
  unlike $page, qr{2025-12-01|2020-01-01}, 'no exact dates invented';
  is $schema->resultset('Observation')->count, 1, 'published event does not fabricate a photo observation';
  $config->{shopfronts}[0]{reported_events}[-1]{date} = '2025-13';
  ClaphamTest::save_json($root->child('data/site.json'), $config);
  try {
    ClaphamShopfronts::Site->new(root => $root)->build;
    fail 'invalid partial date rejected';
  } catch ($error) {
    like $error, qr/Invalid ISO date|Invalid date|Month/, 'invalid partial date rejected';
  }
};

subtest 'shared image appears on both unit pages but once among recent photographs' => sub {
  my ($root, $schema) = fixture();
  my $photo = seed_page($root, $schema);
  my $site = $schema->resultset('Site')->create({
    site_code      => 'CHS0002',
    street_address => '9 Clapham High Street, London',
    postcode       => 'SW4 7TS'
  });

  my $unit = $site->create_related(
    'units', {
      unit_code  => 'CHS0002-U01',
      slug       => 'sw4-7ts-9',
      valid_from => '2026-04-03'
    }
  );

  my $observation = $unit->create_related(
    'observations', {
      observed_on            => '2026-04-03',
      observed_status        => 'vacant',
      observed_business_name => 'Neighbour'
    }
  );

  $unit->create_related(
    'photos', {
      observation_id => $observation->id,
      filename       => $photo->filename,
      taken_on       => $photo->taken_on,
      source_type    => 'own_photo',
      caption        => 'The neighbouring shop on the right.'
    }
  );

  my $config = ClaphamShopfronts::Util::read_json($root->child('data/site.json'));

  push @{$config->{shopfronts}}, {unit_code => 'CHS0002-U01'};
  ClaphamTest::save_json($root->child('data/site.json'), $config);

  my $result = ClaphamShopfronts::Site->new(root => $root)->build;

  is $result->{shopfront_pages}, 2, 'both unit pages built';
  is $result->{recent_photographs}, 1, 'shared image not repeated on homepage';
  is $result->{archive_photographs}, 1, 'shared image not repeated in archive';

  my $archive = $root->child('docs/photos/index.html')->slurp_utf8;

  like $archive, qr{href="../shopfronts/sw4-7ts-9/#photo-2"}, 'archive links to second unit and its photo';
  like $archive, qr{href="../shopfronts/sw4-7ts-7/#photo-1"}, 'archive also links to first unit and its photo';
  is scalar(() = $archive =~ /class="photo-archive-card"/g), 1, 'one gallery card for shared image';
  like $root->child('docs/shopfronts/sw4-7ts-9/index.html')->slurp_utf8, qr{<h1>Neighbour</h1>},
    'second page keeps its own identity';
  like $root->child('docs/shopfronts/sw4-7ts-7/index.html')->slurp_utf8, qr{<h1>Pure Vintage</h1>},
    'first page keeps its own identity';
};

subtest 'complete archive is chronological, escaped and linked from every page' => sub {
  my ($root, $schema) = fixture();
  my $seed = seed_page($root, $schema);
  my @dates = qw(2026-01-10 2026-05-15 2026-03-02 2026-02-20);

  for my $i (0 .. $#dates) {
    for my $suffix ('.webp', '-small.webp') {
      $root->child('docs/images/photos/2026/04', "sample$suffix")
        ->copy($root->child('docs/images/photos/2026/04', "extra-$i$suffix"));
    }

    $schema->resultset('Photo')->create({
      unit_id        => 1,
      observation_id => $seed->observation_id,
      taken_on       => $dates[$i],
      source_type    => 'own_photo',
      filename       => "photos/2026/04/extra-$i.webp",
      caption        => q{<script>Private markup & quoted "caption" and 'apostrophe'</script>}
    });
  }

  my $hidden = $schema->resultset('Unit')->create({
    site_id    => 1,
    unit_code  => 'UNPUBLISHED',
    slug       => 'unpublished',
    valid_from => '2026-04-03'
  });

  $hidden->create_related(
    'photos', {
      taken_on    => '2026-10-29',
      source_type => 'own_photo',
      filename    => 'not-published.webp',
      caption     => 'Unpublished photograph'
    }
  );

  my $before = file_sha($root->child('db/claphamshopfront.db'));
  my $builder = ClaphamShopfronts::Site->new(root => $root);
  my $result = $builder->build;

  is $result->{archive_photographs}, 5, 'all five published photographs included';
  is $result->{recent_photographs}, 3, 'homepage still limited to three';

  my $archive_file = $root->child('docs/photos/index.html');
  my $archive = $archive_file->slurp_utf8;

  is_deeply [($archive =~ /<time datetime="([^"]+)"/g)], [qw(2026-05-15 2026-04-03 2026-03-02 2026-02-20 2026-01-10)],
    'sorted by capture date rather than insertion order';
  like $archive, qr{href="../shopfronts/sw4-7ts-7/#photo-1"}, 'old photograph retains its own unit anchor';
  like $archive, qr{&lt;script&gt;Private markup &amp; quoted &quot;caption&quot; and &#39;apostrophe&#39;&lt;/script&gt;},
    'photo captions escape both kinds of quotes consistently across TT releases';
  unlike $archive, qr{<script>Private markup|Unpublished photograph|not-published.webp},
    'markup and unpublished photographs excluded';
  like $archive, qr{href="../styles.css"}, 'archive stylesheet resolves from its depth';
  like $archive, qr{href="../#the-project"}, 'archive navigation links back to homepage sections';
  like $archive, qr{href="../photos/" aria-current="page">All photos}, 'active archive link indicated';
  like $archive, qr{rel="canonical" href="https://claphamshopfronts.com/photos/"}, 'archive canonical URL';

  my $home = $root->child('docs/index.html')->slurp_utf8;

  like $home, qr{<a href="photos/">All photos</a>}, 'homepage top navigation links to gallery';
  like $home, qr{class="all-photos-link" href="photos/"}, 'recent section links to complete archive';

  my $unit = $root->child('docs/shopfronts/sw4-7ts-7/index.html')->slurp_utf8;

  like $unit, qr{<a href="../../photos/">All photos</a>}, 'unit navigation links to gallery at correct depth';
  like $unit, qr{class="archive-back" href="../../photos/"}, 'unit back link returns to gallery';
  is file_sha($root->child('db/claphamshopfront.db')), $before, 'archive build leaves database untouched';
  $archive_file->append_utf8('stale gallery');
  try {
    $builder->build(check => 1);
    fail 'check mode detects stale archive output';
  } catch ($error) {
    like $error, qr{photos/index.html}, 'check mode detects stale archive output';
  }

  $builder->build;
  is_deeply $builder->build(check => 1)->{changed_files}, [], 'rebuild restores current archive output';
};

subtest 'empty archive renders without needing a published unit' => sub {
  my ($root) = fixture();
  my $config = ClaphamShopfronts::Util::read_json($root->child('data/site.json'));

  $config->{shopfronts} = [];
  ClaphamTest::save_json($root->child('data/site.json'), $config);

  my $result = ClaphamShopfronts::Site->new(root => $root)->build;

  is $result->{archive_photographs}, 0, 'empty archive count';
  is $result->{shopfront_pages}, 0, 'no phantom unit pages';
  like $root->child('docs/photos/index.html')->slurp_utf8, qr{Check back soon for our first shopfronts},
    'empty message shown';
};

done_testing;
