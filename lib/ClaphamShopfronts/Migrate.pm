package ClaphamShopfronts::Migrate;

use v5.36;
use feature 'try';
use Moose;
no warnings 'experimental::try';
use Path::Tiny qw(path);
use JSON::MaybeXS qw(decode_json);
use ClaphamShopfronts::Schema;
use ClaphamShopfronts::Schema::Result::Unit;

with 'ClaphamShopfronts::Role::Dates';

sub identify_observations ($class, $schema, $root) {
  my $count = 0;

  # Reviewed, matching import metadata identifies an existing photo's business.
  for my $file (sort $root->child('data/photos')->children(qr/\.json$/)) {
    my $data = decode_json($file->slurp_raw);

    next unless $data->{business};
    $class->parse_date($data->{taken_on});

    die "Invalid original checksum in reviewed metadata: $file\n"
      unless ($data->{original_sha256} // '') =~ /^[a-f0-9]{64}$/;
    (my $stem = $data->{original}) =~ s/\.[^.]+$//;
    my ($year, $month) = $data->{taken_on} =~ /^(\d{4})-(\d{2})-/;
    my @photos = $schema->resultset('Photo')->search({
      filename => "photos/$year/$month/$stem.webp"
    })->all;

    next unless @photos;

    die "Ambiguous photo while migrating $file\n" unless @photos == 1;

    my $photo = $photos[0];
    my $observation = $photo->observation;

    die "Import evidence does not match existing photo: $file\n"
      unless $observation
        && $observation->unit->unit_code eq $data->{unit}{unit_code}
        && $photo->taken_on eq $data->{taken_on}
        && $observation->observed_on eq $data->{taken_on}
        && (!defined $photo->unit_id || $photo->unit_id == $observation->unit_id)
        && index($photo->notes // '', 'Original SHA-256: ' . $data->{original_sha256}) >= 0;

    my $business = $schema->resultset('Business')->find({
      normalised_name => $data->{business}{normalised_name}
    })
      or die "Reviewed photo business is missing: $file\n";

    $observation->update({
      business_id => $business->id
    });
    $count++;
  }

  return $count;
}

sub add_unit_slugs ($class, $dbh, $root) {
  my %explicit;

  for my $file ($root->child('data/photos')->children(qr/\.json$/)) {
    my $unit = decode_json($file->slurp_raw)->{unit};

    next unless defined $unit->{slug};

    my $slug = ClaphamShopfronts::Schema::Result::Unit->validate_slug($unit->{slug});

    die "Conflicting explicit slugs for $unit->{unit_code}\n"
      if exists $explicit{$unit->{unit_code}} && $explicit{$unit->{unit_code}} ne $slug;

    $explicit{$unit->{unit_code}} = $slug;
  }

  my $rows = $dbh->selectall_arrayref(
    'SELECT u.*, s.street_address AS slug_address, s.postcode AS slug_postcode FROM units u LEFT JOIN sites s ON s.id = u.site_id ORDER BY u.id',
    {
      Slice => {}
    }
  );

  my %used;

  for my $row (@$rows) {
    $row->{slug} = ClaphamShopfronts::Schema::Result::Unit->slug_from_address(
      $row->{slug_postcode}, $row->{slug_address}, $explicit{$row->{unit_code}}
    );

    die "Slug collision for $row->{slug}; supply distinct unit.slug values in reviewed metadata\n"
      if $used{$row->{slug}}++;
  }

  # Rebuild the table to enforce NOT NULL and UNIQUE on migrated databases too.
  # Preserve IDs, timestamps, dependent rows, indexes, triggers and all views.
  my @columns = map { $_->{name} } @{
    $dbh->selectall_arrayref(
      'PRAGMA table_info(units)', {
        Slice => {}
      }
    )
  };

  my $views = $dbh->selectall_arrayref(
    q{SELECT name, sql FROM sqlite_master WHERE type = 'view' ORDER BY rowid}, {
      Slice => {}
    }
  );

  my $objects = $dbh->selectall_arrayref(
    q{SELECT sql FROM sqlite_master WHERE tbl_name = 'units' AND type IN ('index', 'trigger') AND sql IS NOT NULL ORDER BY rowid}
  );

  $dbh->do($root->child('db/migrations/002-unit-slugs.sql')->slurp_utf8);

  my $insert =
    'INSERT INTO units_slug_v2 ('
    . join(', ', map { $dbh->quote_identifier($_) } (@columns, 'slug'))
    . ') VALUES ('
    . join(', ', ('?') x (@columns + 1)) . ')';

  my $statement = $dbh->prepare($insert);

  $statement->execute(@{$_}{@columns, 'slug'}) for @$rows;
  $statement->finish;
  $dbh->do('DROP VIEW ' . $dbh->quote_identifier($_->{name})) for reverse @$views;
  $dbh->do('DROP TABLE units');
  $dbh->do('ALTER TABLE units_slug_v2 RENAME TO units');
  $dbh->do($_->[0]) for @$objects;
  $dbh->do($_->{sql}) for @$views;

  return scalar @$rows;
}

sub migrate ($class, $root) {
  $root = path($root)->absolute;

  my $schema =
    ClaphamShopfronts::Schema->connect_database($root->child('db/claphamshopfront.db'), allow_old_schema => 1);

  my $dbh = $schema->storage->dbh;
  my $version = $dbh->selectrow_array('PRAGMA user_version');

  if ($version == 2) {
    $schema->storage->disconnect;

    return {
      schema_version          => 2,
      result                  => 'already_current',
      identified_observations => 0,
      assigned_slugs          => 0
    };
  }

  die "Unsupported schema version: $version\n" unless $version == 0 || $version == 1;

  # SQLite requires FK enforcement off outside the transaction for a parent-table
  # rebuild. Check all foreign keys before commit and restore enforcement after.
  $dbh->do('PRAGMA foreign_keys = OFF');

  my $result;

  try {
    $result = $schema->txn_do(sub {
      if ($version == 0) {
        $dbh->do(
          'ALTER TABLE observations ADD COLUMN business_id INTEGER REFERENCES businesses(id) ON DELETE SET NULL');
        $dbh->do('CREATE INDEX idx_observations_business_id ON observations(business_id)');
      }

      my $assigned = $class->add_unit_slugs($dbh, $root);
      my $identified = $version == 0 ? $class->identify_observations($schema, $root) : 0;

      die "Migration would leave foreign-key violations\n" if @{$dbh->selectall_arrayref('PRAGMA foreign_key_check')};

      $dbh->do('PRAGMA user_version = 2');

      return {
        schema_version          => 2,
        result                  => 'migrated',
        identified_observations => $identified,
        assigned_slugs          => $assigned
      };
    });
  } catch ($error) {
    $dbh->do('PRAGMA foreign_keys = ON');
    $schema->storage->disconnect;
    die $error;
  }

  $dbh->do('PRAGMA foreign_keys = ON');
  $schema->storage->disconnect;

  return $result;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
