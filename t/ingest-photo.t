use v5.36;
use Test::More;
use lib 'lib', 't/lib';
use ClaphamTest qw(fixture setup_original snapshot counts save_json);
use ClaphamShopfronts::Ingest;
use ClaphamShopfronts::Util qw(file_sha image_size);

sub followup ($root, %options) {
  my ($manifest, $data, $original) = setup_original($root,
    name => $options{name} // 'later.jpg', date => $options{date} // '2026-10-29');
  $data->{business} = {name => 'Tony Voyage', normalised_name => 'tony voyage', type => 'Hair salon',
    is_chain => 1, website => 'https://www.tonyvoyage.com/', notes => 'Opening date unknown'};
  $data->{observation}{status} = 'occupied';
  $data->{observation}{name_as_displayed} = 'Tony Voyage';
  $data->{observation}{notes} = 'A fitted salon was photographed here.';
  $data->{occupancy_notes} = 'First photographed in this use, not an opening date.';
  $data->{photo}{caption} = 'Tony Voyage Hair Salon at the same address.';
  save_json($manifest, $data);
  return ($manifest, $data, $original);
}

subtest 'dry run changes no files or records' => sub {
  my ($root, $schema) = fixture();
  my ($manifest) = setup_original($root);
  my $before = snapshot($root);
  is ClaphamShopfronts::Ingest->new(root => $root)->ingest($manifest, dry_run => 1)->{result}, 'dry_run', 'valid dry run';
  is_deeply snapshot($root), $before, 'files and database byte-for-byte unchanged';
};

subtest 'transactional import preserves history, relationships and original' => sub {
  my ($root, $schema) = fixture();
  my ($manifest, $data, $original) = setup_original($root);
  my $sidecar = "$original:Zone.Identifier";
  Path::Tiny::path($sidecar)->spew_utf8('Windows metadata');
  my $importer = ClaphamShopfronts::Ingest->new(root => $root);
  my $result = $importer->ingest($manifest);
  is $result->{result}, 'ingested', 'import completed';
  is_deeply counts($schema), {map {$_ => 1} qw(Site Unit BusinessType Business Observation Occupancy Photo)}, 'one of each primary record';
  my $archived = $root->child('pics/processed', $data->{original});
  ok !$original->exists, 'original left incoming';
  is file_sha($archived), $data->{original_sha256}, 'original bytes unchanged';
  is Path::Tiny::path("$archived:Zone.Identifier")->slurp_utf8, 'Windows metadata', 'sidecar archived';
  my $photo = $schema->resultset('Photo')->first;
  is $photo->unit->unit_code, 'CHS0001-U01', 'photo linked to unit through DBIC';
  is $photo->observation->unit_id, $photo->unit_id, 'observation and photo agree';
  ok !defined $photo->source_url, 'opening reel not incorrectly used as photograph source';
  my $occupancy = $photo->unit->occupancies->first;
  is $occupancy->occupancy_status, 'vacant', 'vacancy recorded';
  ok !defined $occupancy->business_id, 'former business not treated as trading';
  is $occupancy->valid_from, '2026-04-03', 'first vacancy observation used';
  like $occupancy->notes, qr/unverified report/, 'opening-date uncertainty retained';
  like $occupancy->notes, qr/exact closing date is unknown/, 'closure-date uncertainty retained';
  ok !defined $photo->unit->site->latitude, 'camera GPS not treated as site location';
  for my $field (qw(filename thumbnail)) {
    is_deeply image_size($root->child('docs/images', $result->{$field})), [24, 32], 'small source not enlarged';
  }
  my $before = snapshot($root);
  is $importer->ingest($manifest)->{result}, 'already_ingested', 'safe repeat';
  is_deeply snapshot($root), $before, 'repeat preserves files and database';
  is_deeply $schema->storage->dbh->selectall_arrayref('PRAGMA foreign_key_check'), [], 'no foreign-key violations';
};

subtest 'image generation respects orientation, aspect ratio and size limits' => sub {
  my ($root, $schema) = fixture();
  my ($manifest, $data) = setup_original($root, size => '2400x1200', rotate => 1);
  my $result = ClaphamShopfronts::Ingest->new(root => $root)->ingest($manifest);
  is_deeply image_size($root->child('docs/images', $result->{filename})), [800, 1600], 'large copy rotates and fits the long-edge limit';
  is_deeply image_size($root->child('docs/images', $result->{thumbnail})), [320, 640], 'small copy rotates and preserves proportions';
  is file_sha($root->child('pics/processed', $data->{original})), $data->{original_sha256}, 'original retains its bytes and EXIF';
  my $exif = Image::ExifTool::ImageInfo('' . $root->child('docs/images', $result->{filename}), 'DateTimeOriginal');
  ok !exists $exif->{DateTimeOriginal}, 'published copy has metadata stripped';
};

subtest 'EXIF mismatch leaves original and database untouched' => sub {
  my ($root, $schema) = fixture();
  my ($manifest, $data, $original) = setup_original($root);
  $data->{taken_on} = '2026-04-04';
  save_json($manifest, $data);
  eval {ClaphamShopfronts::Ingest->new(root => $root)->ingest($manifest)};
  like $@, qr/EXIF/, 'date mismatch rejected';
  ok $original->exists, 'original still incoming';
  is $schema->resultset('Photo')->count, 0, 'no photo record created';
};

subtest 'failed image write rolls back database and generated copies' => sub {
  my ($root, $schema) = fixture();
  my ($manifest, undef, $original) = setup_original($root);
  my $writer = \&ClaphamShopfronts::Ingest::write_image;
  my $calls = 0;
  {
    no warnings 'redefine';
    local *ClaphamShopfronts::Ingest::write_image = sub {
      die "simulated disk failure\n" if ++$calls == 2;
      return $writer->(@_);
    };
    eval {ClaphamShopfronts::Ingest->new(root => $root)->ingest($manifest)};
    like $@, qr/simulated disk failure/, 'image error reported';
  }
  is_deeply counts($schema), {map {$_ => 0} qw(Site Unit BusinessType Business Observation Occupancy Photo)}, 'all inserted records rolled back';
  ok $original->exists, 'original remains incoming';
  is scalar(grep {m{^docs/.*\.webp$}} keys %{snapshot($root)}), 0, 'no published image copies left';
};

subtest 'rerun finishes interrupted archive move without duplicates' => sub {
  my ($root, $schema) = fixture();
  my ($manifest, undef, $original) = setup_original($root);
  {
    no warnings 'redefine';
    local *ClaphamShopfronts::Ingest::finish_original = sub {die "interrupted move\n"};
    eval {ClaphamShopfronts::Ingest->new(root => $root)->ingest($manifest)};
    like $@, qr/interrupted move/, 'post-commit interruption simulated';
  }
  is $schema->resultset('Photo')->count, 1, 'database commit retained';
  ok $original->exists, 'original has not moved yet';
  is ClaphamShopfronts::Ingest->new(root => $root)->ingest($manifest)->{result}, 'already_ingested', 'retry recognises committed photo';
  ok !$original->exists, 'retry finishes moving original';
  is $schema->resultset('Photo')->count, 1, 'no duplicate photo';
};

subtest 'later occupant reuses site and unit and leaves the handover gap unknown' => sub {
  my ($root, $schema) = fixture();
  my ($first) = setup_original($root);
  my $importer = ClaphamShopfronts::Ingest->new(root => $root);
  $importer->ingest($first);
  my ($later) = followup($root);
  my $before = snapshot($root);
  is $importer->ingest($later, dry_run => 1)->{timeline_action}, 'new_occupancy', 'dry run explains the state change';
  is_deeply snapshot($root), $before, 'later-photo dry run changes nothing';
  is $importer->ingest($later)->{timeline_action}, 'new_occupancy', 'new state imported';
  is_deeply counts($schema), {Site => 1, Unit => 1, Business => 2, BusinessType => 2, Observation => 2, Occupancy => 2, Photo => 2}, 'same physical unit, distinct businesses and evidence';
  my @periods = $schema->resultset('Occupancy')->search({}, {order_by => 'valid_from'})->all;
  is $periods[0]->valid_from, '2026-04-03', 'original vacancy start preserved';
  is $periods[0]->valid_to, '2026-04-03', 'vacancy ends at last supported observation, not an invented October date';
  is $periods[1]->valid_from, '2026-10-29', 'salon state starts at observation date';
  is $periods[1]->business->name, 'Tony Voyage', 'occupied state identifies the salon';
  is $schema->resultset('Observation')->find(1)->business->name, 'Pure Vintage', 'earlier vacant observation retains its identified business';
  is $schema->resultset('Observation')->find(2)->business->name, 'Tony Voyage', 'new observation identifies the new business';
  my $gap = $schema->resultset('Occupancy')->search({valid_from => {'<=' => '2026-09-01'}, -or => [valid_to => undef, valid_to => {'>=' => '2026-09-01'}]});
  is $gap->count, 0, 'unobserved September state is not fabricated';
  my ($again) = followup($root, name => 'same-business.jpg', date => '2026-11-02');
  is $importer->ingest($again)->{timeline_action}, 'same_occupancy', 'unchanged business adds evidence to existing period';
  is $schema->resultset('Occupancy')->count, 2, 'unchanged state does not create an artificial period';
  is $schema->resultset('Photo')->count, 3, 'all three photos retained';
  is $importer->ingest($later)->{result}, 'already_ingested', 'older already-imported manifest still safely reruns';
  my ($replacement, $replacement_data) = followup($root, name => 'replacement.jpg', date => '2026-12-01');
  $replacement_data->{business}{name} = 'Another Salon';
  $replacement_data->{business}{normalised_name} = 'another salon';
  $replacement_data->{observation}{name_as_displayed} = 'Another Salon';
  save_json($replacement, $replacement_data);
  is $importer->ingest($replacement)->{timeline_action}, 'new_occupancy', 'a different occupied business creates a new period too';
  my $salon_period = $schema->resultset('Occupancy')->find({business_id => 2});
  is $salon_period->valid_to, '2026-11-02', 'prior business ends at its latest supported observation';
  is $schema->resultset('Unit')->count, 1, 'business replacement still does not duplicate the physical unit';
};

subtest 'failed later import restores the prior occupancy as well as its own records' => sub {
  my ($root, $schema) = fixture();
  my ($first) = setup_original($root);
  my $importer = ClaphamShopfronts::Ingest->new(root => $root);
  $importer->ingest($first);
  my ($later, undef, $original) = followup($root);
  my $before = snapshot($root);
  my $writer = \&ClaphamShopfronts::Ingest::write_image;
  my $calls = 0;
  {
    no warnings 'redefine';
    local *ClaphamShopfronts::Ingest::write_image = sub {
      die "later disk failure\n" if ++$calls == 2;
      return $writer->(@_);
    };
    eval {$importer->ingest($later)};
    like $@, qr/later disk failure/, 'later write failure reported';
  }
  ok !defined $schema->resultset('Occupancy')->first->valid_to, 'old period closing update rolled back';
  is_deeply snapshot($root), $before, 'entire prior archive and incoming original preserved';
};

subtest 'ambiguous chronology and wrong site are rejected without changes' => sub {
  my ($root, $schema) = fixture();
  my ($first) = setup_original($root);
  my $importer = ClaphamShopfronts::Ingest->new(root => $root);
  $importer->ingest($first);
  for my $case (['earlier.jpg', '2026-04-02', qr/Out-of-order/], ['same-day.jpg', '2026-04-03', qr/Same-day/]) {
    my ($manifest) = followup($root, name => $case->[0], date => $case->[1]);
    my $before = snapshot($root);
    eval {$importer->ingest($manifest)};
    like $@, $case->[2], 'uncertain sequence requires review';
    is_deeply snapshot($root), $before, 'rejection changes no archive files';
  }
  my ($manifest, $data) = followup($root, name => 'wrong-site.jpg');
  $data->{site}{street_address} = '99 Another Street';
  save_json($manifest, $data);
  eval {$importer->ingest($manifest)};
  like $@, qr/different site or address/, 'existing unit cannot silently move to a different address';
};

done_testing;
