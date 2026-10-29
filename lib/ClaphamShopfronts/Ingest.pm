package ClaphamShopfronts::Ingest;

use v5.36;
use feature 'try';
use Moose;
no warnings 'experimental::try';
use Path::Tiny qw(path);
use File::Temp qw(tempdir);
use Image::ExifTool qw(ImageInfo);
use Image::Magick;
use ClaphamShopfronts::Schema;
use ClaphamShopfronts::Util qw(read_json file_sha display_date image_size unit_slug validate_slug);

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

sub finish_original ($self, $source, $destination) {
  return if "$source" eq "$destination";

  die "Processed original already exists: $destination\n" if $destination->exists;

  my $sidecar = path("$source:Zone.Identifier");
  my $archived = path("$destination:Zone.Identifier");

  die "Processed metadata sidecar already exists: $archived\n" if $sidecar->exists && $archived->exists;

  $source->move($destination);
  $sidecar->move($archived) if $sidecar->exists;
}

sub write_image ($self, $source, $destination, $limit) {
  my $image = Image::Magick->new;
  my $error = $image->Read("$source");

  die "Cannot read photograph: $error\n" if "$error";

  $error = $image->AutoOrient;

  die "Cannot orient photograph: $error\n" if "$error";

  my ($width, $height) = $image->Get('width', 'height');

  my $scale = $limit / ($width > $height ? $width : $height);

  if ($scale < 1) {
    $error = $image->Resize(
      width  => int($width * $scale + .5),
      height => int($height * $scale + .5),
      filter => 'Lanczos',
    );

    die "Cannot resize photograph: $error\n" if "$error";
  }

  $error = $image->Strip;
  die "Cannot strip website image metadata: $error\n" if "$error";

  $error = $image->Write(filename => "webp:$destination", quality => 85);
  die "Cannot write website image: $error\n" if "$error";

  image_size($destination);
}

# Dates bound the evidence we have, rather than inventing a handover date.
# A superseded period ends on its last observation; the gap remains unknown.
sub observation_plan ($self, $schema, $data, $taken_on) {
  my $unit = $schema->resultset('Unit')->find({
    unit_code => $data->{unit}{unit_code}
  }, {
    prefetch => 'site',
  });

  unless ($unit) {
    my $slug = unit_slug(
      $data->{site}{postcode},
      $data->{site}{street_address},
      $data->{unit}{slug},
    );

    die "Slug $slug is already used; supply a distinct unit.slug suffix\n"
      if $schema->resultset('Unit')->find({slug => $slug});

    return { action => 'new_unit', slug => $slug };
  }

  die "A stored unit slug cannot be changed by importing a photo\n"
    if defined $data->{unit}{slug} && validate_slug($data->{unit}{slug}) ne $unit->slug;

  my $site = $unit->site;

  die "Existing unit belongs to a different site or address\n"
    unless $site->site_code eq $data->{site}{site_code}
      && $site->street_address eq $data->{site}{street_address}
      && ($site->postcode // '') eq ($data->{site}{postcode} // '');

  die "Cannot append observations to a retired unit\n"
    if defined $unit->valid_to || $unit->lifecycle_status ne 'active';

  my $last = $unit->observations->search({}, {
    order_by => [{-desc => 'observed_on'}, {-desc => 'id'}]
  })->first;

  my @current = $unit->occupancies->search({valid_to => undef})->all;

  die "Existing unit needs one current occupancy and a prior observation before automatic import\n"
    unless @current == 1 && $last;

  my $occupancy = $current[0];

  die "Out-of-order observations need manual timeline review\n"
    if $taken_on lt $last->observed_on;

  die "Current occupancy and latest observation disagree; manual review required\n"
    if $occupancy->occupancy_status ne $last->observed_status
      || $occupancy->valid_from gt $last->observed_on;

  my $changed = $occupancy->occupancy_status ne $data->{observation}{status};

  if ($data->{observation}{status} eq 'occupied') {
    my $current_business = $occupancy->business;
    $changed ||= !$current_business || $current_business->normalised_name ne $data->{business}{normalised_name};
  }

  die "Same-day state changes need manual timeline review\n" if $changed && $taken_on eq $last->observed_on;

  return {
    action           => $changed ? 'new_occupancy' : 'same_occupancy',
    unit             => $unit,
    slug             => $unit->slug,
    occupancy        => $occupancy,
    last_observed_on => $last->observed_on,
  };
}

sub ingest ($self, $manifest_path, %options) {
  my $root = $self->root;
  my $data = read_json($manifest_path);
  my $name = $data->{original};

  die "original must be a filename, without directories\n"
    unless defined $name && length $name && $name !~ m{[/\\]} && $name ne '.' && $name ne '..';

  my $incoming = $root->child('pics/incoming', $name);
  my $processed = $root->child('pics/processed', $name);

  die "The original exists in both incoming and processed\n" if $incoming->exists && $processed->exists;

  my $source = $incoming->exists ? $incoming : $processed;

  die "Original not found: $name\n" unless $source->is_file;

  my $digest = file_sha($source);

  die "Original SHA-256 does not match the manifest\n" unless $digest eq ($data->{original_sha256} // '');

  my $exif = ImageInfo("$source", 'DateTimeOriginal', 'OffsetTimeOriginal');

  my $captured = $exif->{DateTimeOriginal} // die "Original has no EXIF DateTimeOriginal\n";
  $captured =~ /^(\d{4}):(\d{2}):(\d{2}) \d{2}:\d{2}:\d{2}$/ or die "Invalid EXIF capture date\n";

  my ($year, $month, $day) = ($1, $2, $3);
  my $taken_on = "$year-$month-$day";

  display_date($taken_on);

  die "Manifest date does not match EXIF DateTimeOriginal\n" unless $taken_on eq $data->{taken_on};

  if (defined $data->{occupancy_valid_to}) {
    display_date($data->{occupancy_valid_to});
    die "Occupancy end date precedes the photograph\n" if $data->{occupancy_valid_to} lt $taken_on;
  }

  my $offset = $exif->{OffsetTimeOriginal} // 'offset not recorded';
  my $observation = $data->{observation};
  my $status = $observation->{status};

  die "Unsupported observation status\n"
    unless $status =~ /^(occupied|vacant|opening_soon|under_refurbishment|unknown)$/;
  die "Observation confidence must be high, medium, or low\n"
    unless $observation->{confidence} =~ /^(high|medium|low)$/;
  die "This importer requires a known business for occupied units\n"
    if $status eq 'occupied' && !$data->{business};

  for my $value ($data->{site}{site_code}, $data->{site}{street_address},
                 $data->{unit}{unit_code}) {
    die "Site code, street address, and unit code must be nonempty strings\n"
      unless defined $value && !ref $value && $value =~ /\S/;
  }

  if (my $business = $data->{business}) {
    die "is_chain must be 0 or 1\n"
      unless defined $business->{is_chain} && $business->{is_chain} =~ /^(0|1)$/;
    for my $key (qw(name normalised_name type)) {
      die "Business $key must be a nonempty string\n"
        unless defined $business->{$key}
          && !ref $business->{$key}
          && $business->{$key} =~ /\S/;
    }
  }

  (my $stem = $name) =~ s/\.[^.]+$//;

  my $shared_from = $data->{share_image_from};

  die "share_image_from must name a different unit code\n"
    if defined $shared_from && (ref $shared_from || $shared_from !~ /^[A-Za-z0-9-]+$/ || $shared_from eq $data->{unit}{unit_code});

  my $filename = "photos/$year/$month/$stem.webp";
  my $thumbnail = "photos/$year/$month/$stem-small.webp";
  my $large = $root->child('docs/images', $filename);
  my $small = $root->child('docs/images', $thumbnail);
  my $marker = "Original SHA-256: $digest";
  my $summary = {
    original => $name,
    taken_on => $taken_on,
    site_code => $data->{site}{site_code},
    unit_code => $data->{unit}{unit_code},
    status => $status,
    filename => $filename,
    thumbnail => $thumbnail,
  };

  my $schema = ClaphamShopfronts::Schema->connect_database(
    $root->child('db/claphamshopfront.db'), read_only => $options{dry_run}
  );

  my @created;
  my $work = sub {
    my @existing = $schema->resultset('Photo')->search({
      filename => $filename,
    })->all;

    my $reuse_images = 0;

    if (@existing) {
      die "Published image path belongs to a different photo record\n"
        if grep { $_->taken_on ne $taken_on || index($_->notes // '', $marker) < 0} @existing;

      die "Existing photo record is missing its generated image copies\n" unless $large->is_file && $small->is_file;

      my @matching = grep {$_->unit && $_->unit->unit_code eq $data->{unit}{unit_code}} @existing;

      die "Multiple photo records already exist for this unit and image\n" if @matching > 1;

      return {
        %$summary,
        result   => 'already_ingested',
        photo_id => $matching[0]->id,
      } if @matching;

      die "Image already belongs to another unit; explicit share_image_from is required\n"
        unless defined $shared_from && grep {$_->unit && $_->unit->unit_code eq $shared_from} @existing;
      $reuse_images = 1;
    } else {
      die "Shared image source must be ingested first\n"
        if defined $shared_from;
      die "Original is processed but has no matching database record\n"
        if "$source" eq "$processed";
      die "A generated image path already exists; refusing to overwrite it\n"
        if $large->exists || $small->exists;
    }

    my $plan = $self->observation_plan($schema, $data, $taken_on);

    die "Ending an existing occupancy needs manual review\n"
      if defined $data->{occupancy_valid_to} && $plan->{action} eq 'same_occupancy';

    return {
      %$summary,
      result          => 'dry_run',
      timeline_action => $plan->{action},
      slug            => $plan->{slug},
    } if $options{dry_run};

    my $site_data = $data->{site};
    my $site = $schema->resultset('Site')->find_or_create({
      map { $_ => $site_data->{$_} }
      qw(site_code street_address postcode notes)
    }, {
      key => 'site_code_unique',
    });

    die "Site code already belongs to a different address\n"
      unless $site->street_address eq $site_data->{street_address}
        && ($site->postcode // '') eq ($site_data->{postcode} // '');

    my $unit = $plan->{unit} // $site->create_related('units', {
      unit_code         => $data->{unit}{unit_code},
      slug              => $plan->{slug},
      label             => $data->{unit}{label},
      valid_from        => $taken_on,
      source_confidence => 'observed',
      frontage_notes    => $data->{unit}{frontage_notes},
    });

    my $business;
    if (my $b = $data->{business}) {
      my $type = $schema->resultset('BusinessType')->find_or_create({
        name => $b->{type},
      });

      $business = $schema->resultset('Business')->find_or_create({
        (map {$_ => $b->{$_}} qw(name normalised_name is_chain website notes)),
        business_type_id => $type->id,
      }, {
        key => 'normalised_name_unique',
      });
    }

    my $observed = $unit->create_related('observations', {
      observed_on            => $taken_on,
      observer               => $observation->{observer},
      observed_status        => $status,
      business_id            => $business ? $business->id : undef,
      observed_business_name => $observation->{name_as_displayed},
      confidence             => $observation->{confidence},
      notes                  => $observation->{notes},
    });

    if ($plan->{action} ne 'same_occupancy') {
      if ($plan->{occupancy}) {
        my $notes = $plan->{occupancy}->notes // '';
        $notes .= "\nLast observed in this state: $plan->{last_observed_on}. A different state was first observed on $taken_on. valid_to is the last supported observation date (inclusive), not the actual date the state changed. The intervening period is not established.";
        $plan->{occupancy}->update({
          valid_to => $plan->{last_observed_on},
          notes => $notes,
        });
      }

      $unit->create_related('occupancies', {
        business_id       => $status eq 'occupied' ? $business->id : undef,
        occupancy_status  => $status,
        valid_from        => $taken_on,
        valid_to          => $data->{occupancy_valid_to},
        name_as_displayed => $observation->{name_as_displayed},
        notes             => $data->{occupancy_notes},
      });
    }

    my $photo = $unit->create_related('photos', {
      observation_id => $observed->id,
      taken_on => $taken_on,
      source_type => 'own_photo',
      filename => $filename,
      (map {$_ => $data->{photo}{$_}} qw(source_url attribution caption)),
      notes => "Original: $name\n$marker\nEXIF captured: $captured ($offset)\n$data->{photo}{notes}",
    });

    unless ($reuse_images) {
      $large->parent->mkpath;
      my $temporary = path(tempdir('.ingest-XXXXXX', DIR => "" . $large->parent, CLEANUP => 1));
      for my $copy ([$large, 1600], [$small, 640]) {
        my ($destination, $limit) = @$copy;
        my $staged = $temporary->child($destination->basename);
        $self->write_image($source, $staged, $limit);
        $staged->move($destination);
        push @created, $destination;
      }
    }

    return {
      %$summary,
      result => 'ingested',
      photo_id => $photo->id,
      timeline_action => $plan->{action},
    };
  };

  my $result;

  try {
    $result = $options{dry_run} ? $work->() : $schema->txn_do($work);
  } catch ($error) {
    $schema->storage->disconnect;
    $_->remove for @created;
    die $error;
  }

  $schema->storage->disconnect;

  # A rerun can finish this move after an interrupted, committed import.
  $self->finish_original($source, $processed) unless $options{dry_run};
  return $result;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
