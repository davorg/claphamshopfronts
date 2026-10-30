use v5.36;
use feature 'try';
no warnings 'experimental::try';
use utf8;
use Test::More;
use lib 'lib', 't/lib';
use HTML::Parser;
use JSON::MaybeXS;
use ClaphamTest qw(fixture seed_page read_json save_json snapshot file_sha);
use ClaphamShopfronts::PageMetadata;
use ClaphamShopfronts::Site;

sub extract_json_ld ($html) {
  my @scripts;
  my $inside = 0;
  my $parser = HTML::Parser->new(
    api_version => 3,
    start_h => [sub ($tag, $attributes) {
      if ($tag eq 'script' && ($attributes->{type} // '') eq 'application/ld+json') {
        push @scripts, '';
        $inside = 1;
      }
    }, 'tagname, attr'],
    text_h => [sub ($text) {
      $scripts[-1] .= $text if $inside;
    }, 'text'],
    end_h => [sub ($tag) {
      $inside = 0 if $tag eq 'script';
    }, 'tagname'],
  );

  $parser->parse($html);
  $parser->eof;
  is scalar @scripts, 1, 'one complete JSON-LD script';

  return JSON::MaybeXS->new->decode($scripts[0]);
}

sub page_data ($root, $relative) {
  return extract_json_ld($root->child('docs', $relative)->slurp_utf8);
}

sub unit_images ($data) {
  return [grep {$_->{'@type'} eq 'ImageObject'} @{$data->{hasPart}}];
}

sub assert_absolute_urls ($data) {
  if (ref $data eq 'HASH') {
    for my $key (sort keys %$data) {
      if ($key =~ /^(?:\@id|url|contentUrl|thumbnailUrl|citation)$/) {
        like $data->{$key}, qr{^https?://}, "$key is an absolute public URL";
      }
      assert_absolute_urls($data->{$key});
    }
  } elsif (ref $data eq 'ARRAY') {
    assert_absolute_urls($_) for @$data;
  }
}

subtest 'role output safely embeds Unicode, quotes and closing script text' => sub {
  my $text = "The café & 雪 </ScRiPt><script>window.bad = 1</script> \"quoted\" \x{2028}\x{2029}";
  my $metadata = ClaphamShopfronts::PageMetadata->new(
    og_title    => $text,
    description => $text,
    og_url      => 'https://example.test/unit/',
  );

  ok $metadata->does('MooX::Role::JSON_LD'), 'JSON-LD role composes with Moose';
  ok $metadata->meta->is_immutable, 'metadata remains immutable';
  my $wrapped = $metadata->json_ld_wrapped;
  my $data = extract_json_ld($wrapped);

  is $data->{name}, $text, 'title round-trips through JSON';
  is $data->{description}, $text, 'description round-trips through JSON';
  unlike $wrapped, qr{<script>window.bad}, 'data cannot introduce a script element';
  like $wrapped, qr/\\u003c/, 'HTML delimiters are encoded as JSON escapes';
  like $wrapped, qr/\\u2028/, 'Unicode line separator is encoded safely';
  ok !exists $data->{primaryImageOfPage}, 'no image is invented';
  ok !exists $data->{isPartOf}, 'unknown site data is omitted';
  is $metadata->json_ld_wrapped, $wrapped, 'serialization is deterministic';
};

subtest 'pages describe the website, collection and enduring premises' => sub {
  my ($root, $schema) = fixture();
  my $photo = seed_page($root, $schema);
  my $caption = "Pure Vintage’s old frontage & 雪 </script><script>window.bad = 1</script>";
  $photo->update({caption => $caption, attribution => 'Project photographer', notes => 'PRIVATE PHOTO NOTES'});
  $photo->unit->update({frontage_notes => 'PRIVATE UNIT NOTES'});
  my $successor = $schema->resultset('Business')->create({
    name            => 'Present occupant',
    normalised_name => 'present occupant',
  });
  $photo->unit->create_related(
    'occupancies', {
      business_id      => $successor->id,
      occupancy_status => 'occupied',
      valid_from       => '2026-10-29',
    }
  );
  $schema->storage->disconnect;

  my $config = read_json($root->child('data/site.json'));
  $config->{site_url} = 'https://archive.example.test/project/';
  $config->{image_base} = 'https://images.claphamshopfronts.com/';
  save_json($root->child('data/site.json'), $config);
  my $before = file_sha($root->child('db/claphamshopfront.db'));
  my $builder = ClaphamShopfronts::Site->new(root => $root);
  $builder->build;

  my $home = page_data($root, 'index.html');
  my $gallery = page_data($root, 'photos/index.html');
  my $unit = page_data($root, 'shopfronts/sw4-7ts-7/index.html');
  my $canonical = 'https://archive.example.test/project/shopfronts/sw4-7ts-7/';
  is $home->{'@type'}, 'WebPage', 'homepage is a web page';
  is $home->{mainEntity}{'@id'}, $home->{isPartOf}{'@id'}, 'homepage describes the project website';
  is $home->{isPartOf}{'@type'}, 'WebSite', 'project is a website';
  is $gallery->{'@type'}, 'CollectionPage', 'gallery is a collection page';
  is $gallery->{mainEntity}{'@type'}, 'ItemList', 'gallery has an ordered photograph list';
  is $gallery->{mainEntity}{numberOfItems}, 1, 'one published image';
  is $gallery->{mainEntity}{itemListElement}[0]{position}, 1, 'gallery order is explicit';
  is $unit->{url}, $canonical, 'JSON-LD URL matches the canonical page URL';
  is $unit->{'@id'}, "$canonical#webpage", 'web page has a stable identifier';
  is $unit->{mainEntity}{'@type'}, 'Place', 'unit is an enduring physical place';
  is $unit->{mainEntity}{'@id'}, "$canonical#premises", 'premises has a distinct stable identifier';
  is $unit->{mainEntity}{name}, '7 Clapham High Street, London', 'premises name is independent of its businesses';
  is $unit->{mainEntity}{address}{postalCode}, 'SW4 7TS', 'recorded postcode included';
  ok !exists $unit->{mainEntity}{address}{addressCountry}, 'country is not inferred from missing fields';

  my $image = unit_images($unit)->[0];
  is $image->{'@type'}, 'ImageObject', 'photograph is an image object';
  like $image->{name}, qr/^Pure Vintage /, 'photograph retains its historical business identity';
  is $image->{caption}, $caption, 'caption survives UTF-8 rendering and safe JSON embedding';
  is $image->{dateCreated}, '2026-04-03', 'capture date retained without a fabricated time';
  is $image->{creditText}, 'Project photographer', 'recorded attribution stays plain text';
  is $image->{contentUrl}, 'https://images.claphamshopfronts.com/photos/2026/04/sample.webp', 'configured image host is used';
  is $image->{thumbnailUrl}, 'https://images.claphamshopfronts.com/photos/2026/04/sample-small.webp', 'thumbnail has an absolute URL';
  is_deeply $image->{width}, {'@type' => 'QuantitativeValue', value => 48, unitText => 'px'}, 'width records pixel units';
  is_deeply $image->{height}, {'@type' => 'QuantitativeValue', value => 64, unitText => 'px'}, 'height records pixel units';
  is_deeply $unit->{primaryImageOfPage}, {'@id' => $image->{'@id'}}, 'unit primary image references its latest photograph';
  is_deeply $gallery->{mainEntity}{itemListElement}[0]{item}, $image, 'gallery and unit describe the same image consistently';
  my $anchor = $photo->image_anchor;
  like $root->child('docs/photos/index.html')->slurp_utf8,
    qr{id="\Q$anchor\E"}, 'image identifier has a public gallery anchor';

  for my $data ($home, $gallery, $unit) {
    is $data->{isPartOf}{url}, 'https://archive.example.test/project/', 'configured website URL is retained';
    assert_absolute_urls($data);
    my $json = JSON::MaybeXS->new->encode($data);
    unlike $json, qr/PRIVATE (?:PHOTO|UNIT) NOTES|Internal: not for publication|Present occupant/, 'internal notes and later occupancy stay out of historical metadata';
    unlike $json, qr/"(?:openingHours|foundingDate|dissolutionDate|geo|latitude|longitude|datePublished|dateModified)"/, 'unrecorded facts are omitted';
  }

  is file_sha($root->child('db/claphamshopfront.db')), $before, 'structured metadata leaves SQLite bytes untouched';
  is_deeply $builder->build(check => 1)->{changed_files}, [], 'repeat build is current';

  $photo->unit->site->update({postcode => undef});
  ClaphamShopfronts::Site->new(root => $root)->build;
  $unit = page_data($root, 'shopfronts/sw4-7ts-7/index.html');
  ok !exists $unit->{mainEntity}{address}{postalCode}, 'unavailable postcode is omitted';
  is $unit->{mainEntity}{'@id'}, "$canonical#premises", 'address correction does not change premises identity';

  for my $suffix ('.webp', '-small.webp') {
    $root->child('docs/images/photos/2026/04', "sample$suffix")
      ->copy($root->child('docs/images/photos/2026/04', "older$suffix"));
  }
  $photo->unit->create_related(
    'photos', {
      filename    => 'photos/2026/04/older.webp',
      taken_on    => '2026-03-01',
      source_type => 'own_photo',
      caption     => 'An earlier photograph, entered later.',
    }
  );
  $config->{image_base} = '/images/';
  save_json($root->child('data/site.json'), $config);
  ClaphamShopfronts::Site->new(root => $root)->build;
  $unit = page_data($root, 'shopfronts/sw4-7ts-7/index.html');
  $gallery = page_data($root, 'photos/index.html');
  is_deeply [map {$_->{dateCreated}} @{unit_images($unit)}], ['2026-04-03', '2026-03-01'],
    'unit photographs sort by capture date rather than insertion order';
  is_deeply [map {$_->{item}{dateCreated}} @{$gallery->{mainEntity}{itemListElement}}], ['2026-04-03', '2026-03-01'],
    'gallery preserves the same capture-date order';
  is $unit->{primaryImageOfPage}{'@id'}, $image->{'@id'}, 'latest capture stays the primary image';
  is unit_images($unit)->[0]{contentUrl}, 'https://archive.example.test/images/photos/2026/04/sample.webp',
    'root-relative image base resolves at the configured host root';
};

subtest 'shared image identity and metadata agree across both units and the gallery' => sub {
  my ($root, $schema) = fixture();
  my $first = seed_page($root, $schema);
  my $site = $schema->resultset('Site')->create({
    site_code      => 'CHS0002',
    street_address => '9 Clapham High Street, London',
    postcode       => 'SW4 7TS',
  });
  my $unit = $site->create_related(
    'units', {
      unit_code  => 'CHS0002-U01',
      slug       => 'sw4-7ts-9',
      valid_from => '2026-04-03',
    }
  );
  my $second = $unit->create_related(
    'photos', {
      filename    => $first->filename,
      taken_on    => $first->taken_on,
      source_type => 'own_photo',
      caption     => 'The neighbouring frontage on the right.',
    }
  );
  my $config = read_json($root->child('data/site.json'));
  push @{$config->{shopfronts}}, {unit_code => 'CHS0002-U01'};
  save_json($root->child('data/site.json'), $config);
  ClaphamShopfronts::Site->new(root => $root)->build;

  my $left = unit_images(page_data($root, 'shopfronts/sw4-7ts-7/index.html'))->[0];
  my $right = unit_images(page_data($root, 'shopfronts/sw4-7ts-9/index.html'))->[0];
  my $gallery = page_data($root, 'photos/index.html');
  is_deeply $left, $right, 'both unit pages use the complete shared-image description';
  is_deeply $gallery->{mainEntity}{itemListElement}[0]{item}, $left, 'gallery uses the same image object';
  is $gallery->{mainEntity}{numberOfItems}, 1, 'shared image is listed once';
  is scalar @{$left->{about}}, 2, 'both premises are represented';
  is scalar @{$left->{caption}}, 2, 'both public captions are preserved';
  ok !exists $left->{creditText}, 'missing attribution is omitted';
  my $original_id = $left->{'@id'};

  $config->{image_base} = 'https://images.claphamshopfronts.com/';
  $config->{shopfronts} = [reverse @{$config->{shopfronts}}];
  save_json($root->child('data/site.json'), $config);
  ClaphamShopfronts::Site->new(root => $root)->build;
  $left = unit_images(page_data($root, 'shopfronts/sw4-7ts-7/index.html'))->[0];
  $right = unit_images(page_data($root, 'shopfronts/sw4-7ts-9/index.html'))->[0];
  is $left->{'@id'}, $original_id, 'image identity survives a hosting change';
  is_deeply $left, $right, 'publication order does not change shared-image meaning';
  like $left->{contentUrl}, qr{^https://images.claphamshopfronts.com/}, 'content URL follows the new host';

  $second->update({taken_on => '2026-04-04'});
  $schema->storage->disconnect;
  my $before = snapshot($root);

  try {
    ClaphamShopfronts::Site->new(root => $root)->build;
    fail 'conflicting capture dates rejected';
  } catch ($error) {
    like "$error", qr/inconsistent capture dates/, 'conflicting capture dates rejected';
  }

  is_deeply snapshot($root), $before, 'invalid shared evidence leaves every existing page untouched';
};

subtest 'historical annotations preserve precision and evidence labels' => sub {
  my ($root, $schema) = fixture();
  seed_page($root, $schema);
  my $config = read_json($root->child('data/site.json'));
  $config->{shopfronts}[0]{sourced_events} = [{
    date         => '2020',
    title        => 'A published historical account',
    description  => 'Only the year is established.',
    source_url   => 'https://example.test/history',
    source_label => 'Historical account',
  }];
  $config->{shopfronts}[0]{reported_events} = [{
    date        => '2025-12',
    title       => 'Departure reported by the owner',
    description => 'The exact day remains unconfirmed.',
  }];
  save_json($root->child('data/site.json'), $config);
  ClaphamShopfronts::Site->new(root => $root)->build;
  my $data = page_data($root, 'shopfronts/sw4-7ts-7/index.html');
  my @annotations = grep {$_->{'@type'} eq 'CreativeWork'} @{$data->{hasPart}};
  is_deeply [map {$_->{temporalCoverage}} @annotations], ['2020', '2025-12'], 'year and month precision retained';
  is $annotations[0]{description}, 'Published source', 'published evidence is labelled';
  is $annotations[0]{citation}, 'https://example.test/history', 'published evidence links to its source';
  is $annotations[1]{description}, 'Reported, unconfirmed', 'owner report remains unconfirmed';
  ok !exists $annotations[1]{citation}, 'no source is invented for an owner report';
  is $annotations[1]{about}{'@id'}, $data->{mainEntity}{'@id'}, 'annotation concerns the enduring premises';
};

subtest 'empty gallery has an explicit empty collection and no fabricated capture date' => sub {
  my ($root) = fixture();
  my $config = read_json($root->child('data/site.json'));
  $config->{shopfronts} = [];
  save_json($root->child('data/site.json'), $config);
  ClaphamShopfronts::Site->new(root => $root)->build;
  my $data = page_data($root, 'photos/index.html');
  is $data->{mainEntity}{numberOfItems}, 0, 'empty collection count';
  is_deeply $data->{mainEntity}{itemListElement}, [], 'no phantom photographs';
  like $data->{primaryImageOfPage}{contentUrl}, qr{/images/hero-collage.webp$}, 'decorative image remains the fallback';
  ok !exists $data->{primaryImageOfPage}{dateCreated}, 'fallback has no invented capture date';
};

done_testing;
