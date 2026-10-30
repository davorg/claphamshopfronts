package ClaphamTest;

use v5.36;
use Exporter 'import';
use Path::Tiny qw(path);
use File::Temp qw(tempdir);
use DBI;
use Image::Magick;
use Image::ExifTool;
use JSON::MaybeXS qw(encode_json);
use ClaphamShopfronts::Schema;
use ClaphamShopfronts::Util qw(read_json file_sha);

our @EXPORT_OK = qw(fixture seed_page setup_original snapshot counts save_json);
my $PROJECT = path(__FILE__)->absolute->parent(3);

sub save_json ($filename, $data) {
  path($filename)->spew_raw(encode_json($data));
}

sub fixture (%options) {
  my $root = path(tempdir(
    CLEANUP => 1
  ));

  $root->child($_)->mkpath for qw(db data templates docs/images/photos/2026/04 pics/incoming pics/processed);

  my $dbh = DBI->connect(
    'dbi:SQLite:dbname=' . $root->child('db/claphamshopfront.db'),
    '', '', {
      RaiseError                       => 1,
      sqlite_allow_multiple_statements => 1,
    }
  );

  my $definition =
    $options{legacy} ? 't/fixtures/schema-v0.sql'
    : defined $options{version} ? "t/fixtures/schema-v$options{version}.sql"
    : 'db/claphamshopfronts.ddl';

  $dbh->do($PROJECT->child($definition)->slurp_utf8);
  $dbh->disconnect;

  for my $relative (
    qw(
      data/site.json
      templates/page.tt
      templates/head.tt
      templates/nav.tt
      templates/footer.tt
      templates/home.tt
      templates/shopfront.tt
      templates/photograph.tt
      templates/recent-photographs.tt
      templates/all-photos.tt
      data/photos/PXL_20260403_065904338.json
      db/migrations/002-unit-slugs.sql
    )
  ) {
    my $destination = $root->child($relative);

    $destination->parent->mkpath;
    $PROJECT->child($relative)->copy($destination);
  }

  # Publish only the unit seeded by this fixture, independently of the live archive.
  my $config = read_json($root->child('data/site.json'));

  $config->{shopfronts} = [grep { $_->{unit_code} eq 'CHS0001-U01' } @{$config->{shopfronts}}];
  save_json($root->child('data/site.json'), $config);

  return (
    $root,
    ClaphamShopfronts::Schema->connect_database(
      $root->child('db/claphamshopfront.db'),
      allow_old_schema => $options{legacy} || defined $options{version}
    )
  );
}

sub seed_page ($root, $schema) {
  my $site = $schema->resultset('Site')->create({
    site_code      => 'CHS0001',
    street_address => '7 Clapham High Street, London',
    postcode       => 'SW4 7TS'
  });

  my $version = $schema->storage->dbh->selectrow_array('PRAGMA user_version');
  my %slug = $version >= 2 ? (slug => 'sw4-7ts-7') : ();
  my $unit = $site->create_related(
    'units', {
      %slug,
      unit_code  => 'CHS0001-U01',
      valid_from => '2026-04-03'
    }
  );

  my $type = $schema->resultset('BusinessType')->create({
    name => 'Second-hand clothing shop'
  });

  my $business = $type->create_related(
    'businesses', {
      name            => 'Pure Vintage',
      normalised_name => 'pure vintage',
      website         => 'https://www.instagram.com/purevintage_clapham/',
      notes           => 'Internal: not for publication'
    }
  );

  my %identity = $schema->storage->dbh->selectrow_array('PRAGMA user_version') ? (business_id => $business->id) : ();
  my $observation = $unit->create_related(
    'observations', {
      %identity,
      observed_on            => '2026-04-03',
      observed_status        => 'vacant',
      observed_business_name => 'Pure Vintage'
    }
  );

  my $photo = $unit->create_related(
    'photos', {
      observation_id => $observation->id,
      taken_on       => '2026-04-03',
      source_type    => 'own_photo',
      filename       => 'photos/2026/04/sample.webp',
      caption        => 'The old shop & its shutter.'
    }
  );

  for my $name (qw(sample.webp sample-small.webp)) {
    my $image = Image::Magick->new(size => '48x64');
    my $error = $image->Read('xc:blue');

    die $error if "$error";

    $error = $image->Write('' . $root->child('docs/images/photos/2026/04', $name));

    die $error if "$error";
  }

  return $photo;
}

sub setup_original ($root, %options) {
  my $manifest = $root->child('data/photos/PXL_20260403_065904338.json');
  my $data = read_json($manifest);

  if ($options{name}) {
    $data->{original} = $options{name};
    $manifest = $root->child('data/photos', "$options{name}.json");
  }

  $data->{taken_on} = $options{date} if $options{date};

  my $original = $root->child('pics/incoming', $data->{original});
  my $image = Image::Magick->new(size => $options{size} // '24x32');
  my $error = $image->Read('xc:blue');

  die $error if "$error";

  $error = $image->Write("$original");

  die $error if "$error";

  my $exif = Image::ExifTool->new;
  (my $date = $data->{taken_on}) =~ s/-/:/g;
  $exif->SetNewValue(DateTimeOriginal   => "$date 07:59:04");
  $exif->SetNewValue(OffsetTimeOriginal => '+01:00');
  $exif->SetNewValue(Orientation        => 'Rotate 90 CW')
    if $options{rotate};
  $exif->WriteInfo("$original") or die 'Cannot write fixture EXIF';
  $data->{original_sha256} = file_sha($original);
  save_json($manifest, $data);

  return ($manifest, $data, $original);
}

sub snapshot ($root) {
  my %files;
  my $iterator = $root->iterator({
    recurse => 1
  });

  while (my $file = $iterator->()) {
    $files{"" . $file->relative($root)} = file_sha($file) if $file->is_file;
  }

  return \%files;
}

sub counts ($schema) {
  return {map { $_ => $schema->resultset($_)->count } qw(Site Unit BusinessType Business Observation Occupancy Photo)};
}

1;
