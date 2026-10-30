use v5.36;
use feature 'try';
no warnings 'experimental::try';
use utf8;
use Test::More;
use lib 'lib', 't/lib';
use HTML::Parser;
use ClaphamTest qw(fixture seed_page save_json read_json file_sha);
use ClaphamShopfronts::PageMetadata;
use ClaphamShopfronts::Site;

sub parse_metadata ($html) {
  my $result = {
    titles    => [],
    canonical => [],
    meta      => {},
    elements  => [],
  };
  my $in_title = 0;
  my $parser = HTML::Parser->new(
    api_version => 3,
    start_h => [sub ($tag, $attributes) {
      push @{$result->{elements}}, $tag;

      if ($tag eq 'title') {
        $in_title = 1;
        push @{$result->{titles}}, '';
      } elsif ($tag eq 'meta') {
        my $key = $attributes->{name} // $attributes->{property};
        push @{$result->{meta}{$key}}, $attributes->{content} if defined $key;
      } elsif ($tag eq 'link' && ($attributes->{rel} // '') eq 'canonical') {
        push @{$result->{canonical}}, $attributes->{href};
      }
    }, 'tagname, attr'],
    text_h => [sub ($text) {
      $result->{titles}[-1] .= $text if $in_title;
    }, 'dtext'],
    end_h => [sub ($tag) {
      $in_title = 0 if $tag eq 'title';
    }, 'tagname'],
  );

  $parser->parse($html);
  $parser->eof;

  return $result;
}

sub assert_unique ($metadata) {
  is scalar @{$metadata->{titles}}, 1, 'one title';
  is scalar @{$metadata->{canonical}}, 1, 'one canonical link';

  for my $name (sort keys %{$metadata->{meta}}) {
    is scalar @{$metadata->{meta}{$name}}, 1, "one $name tag";
  }
}

subtest 'Moose role composition escapes text and attributes exactly once' => sub {
  my $title = q{The Rattlin’ Bog & "Shop" </title><script>alert('x')</script>};
  my $description = "A \"frontage\" & 'shutter' <closed>\nOn the high street.";
  my $social = 'A shorter & distinct social summary.';
  my $url = 'https://example.test/shop/?a=1&b=two';
  my $image = 'https://images.example.test/front.webp?width=1600&fit=inside';
  my $metadata = ClaphamShopfronts::PageMetadata->new(
    og_title       => $title,
    description    => $description,
    og_description => $social,
    og_url         => $url,
    og_image       => $image,
    og_image_alt   => $description,
    image_width    => 1200,
    image_height   => 630,
  );

  isa_ok $metadata, 'Moose::Object';
  ok $metadata->does('MooX::Role::SEOTags'), 'SEO role composes with Moose';
  ok $metadata->meta->is_immutable, 'metadata object is immutable';

  my $tags = $metadata->tags;
  my $parsed = parse_metadata($tags);
  assert_unique($parsed);

  is $parsed->{titles}[0], $title, 'title round-trips without becoming markup';
  ok !grep({$_ eq 'script'} @{$parsed->{elements}}), 'title cannot introduce a script element';
  is $parsed->{canonical}[0], $url, 'canonical query string round-trips';

  my %expected = (
    description           => $description,
    'og:title'            => $title,
    'og:type'             => 'website',
    'og:description'      => $social,
    'og:url'              => $url,
    'og:site_name'        => 'Clapham Shopfronts',
    'og:image'            => $image,
    'og:image:alt'        => $description,
    'og:image:width'      => 1200,
    'og:image:height'     => 630,
    'twitter:title'       => $title,
    'twitter:description' => $social,
    'twitter:card'        => 'summary_large_image',
    'twitter:image'       => $image,
    'twitter:image:alt'   => $description,
  );

  for my $name (sort keys %expected) {
    is $parsed->{meta}{$name}[0], $expected{$name}, "$name round-trips";
  }

  is $metadata->tags, $tags, 'repeated tag generation is deterministic';
};

subtest 'absent optional image fields produce a usable text-only preview' => sub {
  for my $options ({}, {og_image => undef}, {og_image => ''}) {
    my $metadata = ClaphamShopfronts::PageMetadata->new(
      og_title    => 'An archive page',
      description => 'An archive description',
      og_url      => 'https://example.test/archive/',
      %$options,
      og_image_alt => 'An alt without an image',
      image_width  => 1200,
      image_height => 630,
    );
    my $parsed = parse_metadata($metadata->tags);

    is $parsed->{meta}{'twitter:card'}[0], 'summary', 'no image selects a text-only card';
    is $parsed->{meta}{'og:description'}[0], 'An archive description', 'social description defaults to search description';
    ok !grep({/^(?:og|twitter):image/} keys %{$parsed->{meta}}), 'no orphan image, alt or dimension tags';
    ok !exists $parsed->{meta}{author}, 'no author tag is invented';
  }

  my $metadata = ClaphamShopfronts::PageMetadata->new(
    og_title    => 'An image without optional details',
    description => 'A photograph',
    og_url      => 'https://example.test/',
    og_image    => 'https://images.example.test/photo.webp',
  );
  my $parsed = parse_metadata($metadata->tags);

  is $parsed->{meta}{'twitter:card'}[0], 'summary_large_image', 'image selects a large-image card';
  is $parsed->{meta}{'og:image'}[0], $metadata->og_image, 'image is retained without optional details';
  ok !grep({/^(?:og|twitter):image:(?:alt|width|height)$/} keys %{$parsed->{meta}}),
    'missing alt and dimensions are omitted';
};

subtest 'metadata rejects relative URLs and invalid dimensions' => sub {
  for my $options (
    {og_url => '/relative/'},
    {og_image => '/relative.webp'},
    {image_width => 0},
    {image_height => -1},
  ) {
    try {
      ClaphamShopfronts::PageMetadata->new(
        og_title    => 'Page',
        description => 'Description',
        og_url      => 'https://example.test/',
        %$options,
      );
      fail 'invalid metadata rejected';
    } catch ($error) {
      like $error, qr/Expected an HTTP\(S\) URL|Image dimensions must be positive/, 'invalid metadata rejected';
    }
  }
};

subtest 'all page types use configured URLs and preserve the photographed identity' => sub {
  my ($root, $schema) = fixture();
  my $photo = seed_page($root, $schema);
  my $caption = q{Pure Vintage's shutter & "old" frontage <vacant>.};
  $photo->update({caption => $caption});

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
  $config->{site_url} = 'https://archive.example.test/';
  $config->{image_base} = 'https://images.claphamshopfronts.com/';
  save_json($root->child('data/site.json'), $config);

  my $database = $root->child('db/claphamshopfront.db');
  my $before = file_sha($database);
  my $builder = ClaphamShopfronts::Site->new(root => $root);
  $builder->build;

  for my $page (
    {file => 'index.html', path => '/', home => 1},
    {file => 'photos/index.html', path => '/photos/', home => 0},
    {file => 'shopfronts/sw4-7ts-7/index.html', path => '/shopfronts/sw4-7ts-7/', home => 0},
  ) {
    my $html = $root->child('docs', $page->{file})->slurp_utf8;
    my ($head) = $html =~ m{(<head>.*?</head>)}s;
    my $parsed = parse_metadata($head);
    my $url = 'https://archive.example.test' . $page->{path};
    my $image = $page->{home}
      ? 'https://archive.example.test/images/hero-collage.webp'
      : 'https://images.claphamshopfronts.com/photos/2026/04/sample.webp';

    subtest $page->{file} => sub {
      assert_unique($parsed);
      is $parsed->{canonical}[0], $url, 'canonical honours site URL';
      is $parsed->{meta}{'og:url'}[0], $url, 'OpenGraph URL agrees with canonical';
      is $parsed->{meta}{'og:image'}[0], $image, 'social image honours its configured host';
      is $parsed->{meta}{'twitter:image'}[0], $image, 'Twitter uses the same image';
      is $parsed->{meta}{'og:image:width'}[0], $page->{home} ? 1200 : 48, 'image width retained';
      is $parsed->{meta}{'og:image:height'}[0], $page->{home} ? 630 : 64, 'image height retained';
      is $parsed->{meta}{'twitter:image:alt'}[0], $parsed->{meta}{'og:image:alt'}[0], 'social previews share alt text';
      is $parsed->{meta}{'twitter:title'}[0], $parsed->{titles}[0], 'Twitter and document titles agree';
      unlike $head, qr/Present occupant|Internal: not for publication/, 'current occupancy and internal notes do not relabel a historical photo';

      if ($page->{home}) {
        isnt $parsed->{meta}{description}[0], $parsed->{meta}{'og:description'}[0],
          'homepage keeps its distinct search and social descriptions';
      } elsif ($page->{file} eq 'photos/index.html') {
        is $parsed->{meta}{'og:image:alt'}[0], $parsed->{meta}{description}[0],
          'gallery keeps its existing archive image description';
      } else {
        is $parsed->{meta}{'og:image:alt'}[0], $caption, 'photo-specific alt text preserved';
      }

      if ($page->{file} =~ /^shopfronts/) {
        like $parsed->{titles}[0], qr/^Pure Vintage /, 'unit preview identifies the photographed business';
        is $parsed->{meta}{description}[0], $caption, 'unit description comes from its historical photograph';
      }
    };
  }

  is file_sha($database), $before, 'SEO generation leaves database bytes unchanged';
  is_deeply $builder->build(check => 1)->{changed_files}, [], 'generated SEO remains current';
};

done_testing;
