package ClaphamShopfronts::Site;

use v5.36;
use utf8;
use Moose;
use Path::Tiny qw(path);
use Template;
use URI;
use URI::Escape qw(uri_escape_utf8);
use ClaphamShopfronts::Schema;
use ClaphamShopfronts::Util qw(read_json display_date web_url image_base html image_size validate_slug);

with 'ClaphamShopfronts::Role::ProjectRoot';

my $START = '<!-- BEGIN GENERATED RECENT PHOTOGRAPHS -->';
my $END = '<!-- END GENERATED RECENT PHOTOGRAPHS -->';
my %STATUS = (
  occupied            => 'Occupied',
  vacant              => 'Vacant',
  opening_soon        => 'Opening soon',
  under_refurbishment => 'Under refurbishment',
  unknown             => 'State unknown'
);

has tt => (
  is       => 'ro',
  isa      => 'Template',
  init_arg => undef,
  lazy     => 1,
  builder  => '_build_tt',
);

sub _build_tt ($self) {
  return Template->new({
    INCLUDE_PATH => "" . $self->root->child('templates'),
    ENCODING     => 'utf8',
    STRICT       => 1,
    # Keep escaping identical across Template Toolkit releases and metadata.
    FILTERS      => {
      html => \&html,
    },
  });
}

sub render ($self, $template, $variables) {
  my $output = '';

  $self->tt->process($template, $variables, \$output) or die $self->tt->error . "\n";

  return $output;
}

sub fragment ($document, $pattern) {
  my @matches = $document =~ /($pattern)/sg;

  die "Expected one shared homepage head, header, or footer\n" unless @matches == 1;

  return $matches[0];
}

sub page_header ($home, $prefix, $current = '') {
  my $header = fragment($home, qr{<header class="site-header wrap">.*?</header>}s);

  $header =~ s{href="\./"}{'href="' . $prefix . '"'}ge;
  $header =~ s{href="#([^"]+)"}{'href="' . $prefix . '#' . $1 . '"'}ge;
  $header =~
    s{href="photos/"}{'href="' . $prefix . 'photos/"' . ($current eq 'photos' ? ' aria-current="page"' : '')}ge;

  return $header;
}

sub page_head ($home, $fields, $prefix = '../../') {
  my $head = fragment($home, qr{<head>.*?</head>}s);
  my $count = $head =~ s{<title>.*?</title>}{'<title>' . html($fields->{title}) . '</title>'}se;

  die "Expected one homepage title\n" unless $count == 1;

  my %metadata = (
    description       => $fields->{caption},
    'og:title'        => $fields->{title},
    'og:description'  => $fields->{caption},
    'og:image'        => $fields->{social_image},
    'og:image:width'  => $fields->{image_width},
    'og:image:height' => $fields->{image_height},
    'og:image:alt'    => $fields->{caption}
  );

  for my $key (keys %metadata) {
    $count = $head =~ s{(<meta (?:name|property)="\Q$key\E" content=")[^"]*(">)}{$1 . html($metadata{$key}) . $2}ge;

    die "Expected one homepage meta tag for $key\n" unless $count == 1;
  }

  $head =~ s{href="styles.css"}{'href="' . $prefix . 'styles.css"'}ge;
  $head =~ s{</head>}{'  <link rel="canonical" href="' . html($fields->{canonical}) . qq{">\n</head>}}e;

  return $head;
}

sub photo_assets ($self, $photo, $base) {
  my $filename = $photo->{filename};

  die "Expected an image-root-relative WebP filename: $filename\n"
    if $filename =~ m{^/|(?:^|/)\.\.(?:/|$)|\\} || $filename !~ /\.webp$/;

  (my $thumbnail = $filename) =~ s/\.webp$/-small.webp/;
  my $images = $self->root->child('docs/images')->realpath;
  my @sizes;

  for my $relative ($filename, $thumbnail) {
    my $file = $images->child($relative);

    die "Published image not found: $relative\n" unless $file->is_file;
    die "Image path leaves published directory\n" unless index("" . $file->realpath, "$images/") == 0;

    push @sizes, image_size($file);
  }

  return {
    image_url    => $base . uri_escape_utf8($filename, '^A-Za-z0-9\-._~/'),
    small_url    => $base . uri_escape_utf8($thumbnail, '^A-Za-z0-9\-._~/'),
    image_width  => $sizes[0][0],
    image_height => $sizes[0][1],
    small_width  => $sizes[1][0],
    small_height => $sizes[1][1],
  };
}

sub history_date ($value) {
  return $value if defined $value && $value =~ /^[1-9][0-9]{3}$/;

  if (defined $value && $value =~ /^[1-9][0-9]{3}-(?:0[1-9]|1[0-2])$/) {
    my $display = display_date("$value-01");

    $display =~ s/^1 //;

    return $display;
  }

  return display_date($value);
}

sub history ($publication, $photos) {
  my @events;

  for my $event (@{$publication->{reported_events} // []}) {
    push @events, {
      %$event,
      display_date => history_date($event->{date}),
      source_url   => $event->{source_url} ? web_url($event->{source_url}) : '',
      source_label => $event->{source_label} // '',
      reported     => 1
    };
  }

  for my $event (@{$publication->{sourced_events} // []}) {
    push @events, {
      %$event,
      display_date => history_date($event->{date}),
      source_url   => web_url($event->{source_url}),
      reported     => 0
    };
  }

  my %closed;

  for my $closure (@{$publication->{confirmed_closures} // []}) {
    display_date($closure->{observed_on});

    my @matching = grep {
      $_->{taken_on} eq $closure->{observed_on}
        && ($_->{business_normalised_name} // '') eq $closure->{business_normalised_name}
        && ($_->{observed_status} // '') eq 'vacant'
    } @$photos;

    die "Confirmed closure has no matching vacant business observation\n" unless @matching;

    $closed{$_->{id}} = 1 for @matching;
  }

  for my $photo (@$photos) {
    my $title = 'Photograph recorded';
    my $description = $photo->{caption};

    if ($closed{$photo->{id}}) {
      $title = $photo->{business_name} . ': closed by this date';
      $description =
        'The project photographer confirms '
        . $photo->{business_name}
        . ' had ceased trading at this address by the time this photograph was taken. The exact closing date is unknown.';
    } elsif (($photo->{observed_status} // '') eq 'occupied') {
      $title = $photo->{business_name} . ' photographed here';
      $description .= ' This documents the business on the photograph date, not its opening date.';
    }

    push @events, {
      date         => $photo->{taken_on},
      display_date => $photo->{photograph_date},
      reported     => 0,
      source_url   => '',
      source_label => '',
      title        => $title,
      description  => $description
    };
  }

  return [sort { $a->{date} cmp $b->{date} } @events];
}

sub _load_unit ($self, $schema, $code) {
  die "Unit code is not suitable for a page URL\n" unless $code =~ /^[A-Za-z0-9-]+$/;

  my $unit = $schema->resultset('Unit')->find(
    {
      unit_code => $code
    }, {
      prefetch => 'site'
    }
  );

  die "Published unit is missing: $code\n" unless $unit;

  return $unit;
}

sub _load_photographs ($self, $schema, $unit) {
  my @rows = $schema->resultset('Photo')->search(
    {
      -or => [
        {
          'me.unit_id' => $unit->id
        }, {
          'me.unit_id'          => undef,
          'observation.unit_id' => $unit->id
        }
      ],
      'me.filename' => {
        '!=' => undef
      },
    }, {
      prefetch => {
        observation => {
          business => 'business_type'
        }
      },
      order_by => [
        {
          -desc => 'me.taken_on'
        }, {
          -desc => 'me.id'
        }
      ]
    }
  )->all;

  die 'Published unit has no photograph: ' . $unit->unit_code . "\n" unless @rows;

  return \@rows;
}

sub _prepare_photographs ($self, $rows, $site, $page_url, $base) {
  my @photos;

  for my $row (@$rows) {
    my $observation = $row->observation;
    my $business = $observation ? $observation->business : undef;
    my $type = $business ? $business->business_type : undef;
    my $photo = {
      $row->get_columns,
      observed_status        => $observation ? $observation->observed_status : undef,
      observed_business_name => $observation ? $observation->observed_business_name : undef
    };

    $photo->{photograph_date} = display_date($photo->{taken_on});

    die "Unrecognised observation state\n"
      if defined $photo->{observed_status} && !exists $STATUS{$photo->{observed_status}};

    my $business_name = $business ? $business->name : ($photo->{observed_business_name} || $site->street_address);

    $photo->{caption} ||=
      $business_name . ', ' . $site->street_address . ', photographed ' . $photo->{photograph_date} . '.';
    push @photos, {
      %$photo,
      %{$self->photo_assets($photo, $base)},
      page_url                 => $page_url . '#photo-' . $row->id,
      attribution              => $photo->{attribution} // '',
      business_name            => $business_name,
      street_address           => $site->street_address,
      business_type            => $type ? $type->name : 'Business type not yet recorded',
      business_normalised_name => $business ? $business->normalised_name : '',
      business_website         => $business ? ($business->website // '') : '',
      status_label             => $STATUS{$photo->{observed_status} // ''} // 'State not recorded',
      display_name             => $photo->{observed_business_name} || $business_name
    };
  }

  return \@photos;
}

sub _change_note ($self, $photos) {
  for my $index (1 .. $#$photos) {
    my ($newer, $older) = @$photos[$index - 1, $index];

    next
      if ($newer->{observed_status} // '') eq ($older->{observed_status} // '')
        && $newer->{business_normalised_name} eq $older->{business_normalised_name};

    return
      'The exact changeover date between the observations on '
      . $older->{photograph_date} . ' and '
      . $newer->{photograph_date}
      . ' is not yet known.';
  }

  return '';
}

sub _source_links ($self, $photos) {
  my (@sources, %seen);

  for my $record (@$photos) {
    if (my $url = $record->{business_website}) {
      web_url($url);

      my $host = URI->new($url)->host;

      push @sources, {
        url   => $url,
        label => $record->{business_name} . ($host =~ /^(www\.)?instagram\.com$/ ? ' on Instagram' : ' website')
      }
        unless $seen{$url}++;
    }

    if ($record->{source_url} && !$seen{$record->{source_url}}++) {
      push @sources, {
        url   => web_url($record->{source_url}),
        label => 'Original photograph source'
      };
    }
  }

  return \@sources;
}

sub _unit_page_data ($self, $unit, $publication, $photos, $site_url, $page_url) {
  my $site = $unit->site;
  my $photo = $photos->[0];

  return {
    %$photo,
    address        => $site->street_address,
    postcode       => $site->postcode // '',
    status_at_date => ($STATUS{$photo->{observed_status} // ''} // 'Not recorded') . ' when photographed',
    title          => $photo->{business_name} . ' — ' . $site->street_address . ' — Clapham Shopfronts',
    canonical      => "$site_url/$page_url",
    social_image   => $photo->{image_url} =~ m{^/} ? $site_url . $photo->{image_url} : $photo->{image_url},
    history        => history($publication, $photos),
    source_links   => $self->_source_links($photos),
    main_photo     => $photo,
    earlier_photos => [@$photos[1 .. $#$photos]],
    photo_sources  => $photos,
    change_note    => $self->_change_note($photos),
  };
}

sub _render_unit_page ($self, $data, $layout) {
  return $self->render(
    'shopfront.tt', {
      %$data,
      head   => page_head($layout->{home}, $data),
      header => $layout->{header},
      footer => $layout->{footer},
    }
  );
}

sub _group_archive_photographs ($self, $photos) {
  my @ordered = sort { $b->{taken_on} cmp $a->{taken_on} || $b->{id} <=> $a->{id} } @$photos;
  my (%by_image, @archive);

  for my $photo (@ordered) {
    unless ($by_image{$photo->{filename}}) {
      my $group = {%$photo, subjects => []};

      $by_image{$photo->{filename}} = $group;
      push @archive, $group;
    }

    push @{$by_image{$photo->{filename}}{subjects}}, $photo;
  }

  return \@archive;
}

sub _render_archive_page ($self, $archive, $layout) {
  my $site_url = $layout->{site_url};
  my $latest = $archive->[0];
  my $fields = {
    title   => 'All photos — Clapham Shopfronts',
    caption =>
      'Explore the photographic archive of Clapham shopfronts, newest first. Follow each photograph to its address and story.',
    canonical    => "$site_url/photos/",
    social_image => $latest
      ? ($latest->{image_url} =~ m{^/} ? $site_url . $latest->{image_url} : $latest->{image_url})
      : "$site_url/images/hero-collage.webp",
    image_width  => $latest ? $latest->{image_width} : 1200,
    image_height => $latest ? $latest->{image_height} : 630,
  };

  return $self->render(
    'all-photos.tt', {
      head        => page_head($layout->{home}, $fields, '../'),
      header      => page_header($layout->{home}, '../', 'photos'),
      footer      => $layout->{footer},
      photos      => $archive,
      photo_count => scalar @$archive,
    }
  );
}

sub _render_homepage ($self, $photos, $layout) {
  my $home = $layout->{home};
  my $recent = @$photos
    ? $self->render(
      'recent-photographs.tt', {
        photos => $photos
      }
    )
    : '';

  my $count = $home =~ s{\Q$START\E.*?\Q$END\E}{$START . "\n" . $recent . "\n    " . $END}se;

  die "Expected one generated recent-photographs section in the homepage\n" unless $count == 1;

  return $home;
}

sub _apply_outputs ($self, $outputs, $check) {
  my $root = $self->root;
  my @changed = grep { !path($_)->exists || path($_)->slurp_utf8 ne $outputs->{$_} } sort keys %$outputs;

  die 'Generated pages need rebuilding: ' . join(', ', map { path($_)->relative($root) } @changed) . "\n"
    if $check && @changed;

  unless ($check) {
    for my $file (@changed) {
      path($file)->parent->mkpath;
      path($file)->spew_utf8($outputs->{$file});
    }
  }

  return [map { "" . path($_)->relative($root) } @changed];
}

sub build ($self, %options) {
  my $root = $self->root;
  my $config = read_json($root->child('data/site.json'));
  my $site_url = web_url($config->{site_url});

  $site_url =~ s{/+$}{};

  my $base = image_base($options{image_base} // $config->{image_base});
  my $home_path = $root->child('docs/index.html');
  my $home = $home_path->slurp_utf8;
  my $layout = {
    home     => $home,
    site_url => $site_url,
    header   => page_header($home, '../../'),
    footer   => fragment($home, qr{<footer class="site-footer wrap">.*?</footer>}s),
  };

  my $schema = ClaphamShopfronts::Schema->connect_database($root->child('db/claphamshopfront.db'), read_only => 1);
  my (%outputs, @all_photos);

  for my $publication (@{$config->{shopfronts}}) {
    my $code = $publication->{unit_code};
    my $unit = $self->_load_unit($schema, $code);
    my $rows = $self->_load_photographs($schema, $unit);
    my $page_url = 'shopfronts/' . validate_slug($unit->slug) . '/';
    my $output = $root->child('docs', $page_url, 'index.html');

    die "Duplicate published unit: $code\n" if exists $outputs{"$output"};

    my $photos = $self->_prepare_photographs($rows, $unit->site, $page_url, $base);
    my $data = $self->_unit_page_data($unit, $publication, $photos, $site_url, $page_url);

    $outputs{"$output"} = $self->_render_unit_page($data, $layout);
    push @all_photos, @$photos;
  }

  $schema->storage->disconnect;

  my $unit_pages = scalar keys %outputs;
  my $archive = $self->_group_archive_photographs(\@all_photos);
  my @recent = map { $_->{subjects}[0] } @$archive;

  splice @recent, 3 if @recent > 3;

  $outputs{"" . $root->child('docs/photos/index.html')} = $self->_render_archive_page($archive, $layout);
  $outputs{"$home_path"} = $self->_render_homepage(\@recent, $layout);

  # Every page and asset has been validated before any output is written.
  my $changed = $self->_apply_outputs(\%outputs, $options{check});

  return {
    shopfront_pages     => $unit_pages,
    archive_photographs => scalar @$archive,
    recent_photographs  => scalar @recent,
    changed_files       => $changed,
  };
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
