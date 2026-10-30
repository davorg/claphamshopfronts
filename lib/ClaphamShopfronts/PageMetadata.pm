package ClaphamShopfronts::PageMetadata;

use v5.36;
use utf8;
use Moose;
use JSON::MaybeXS;
use List::Util qw(uniqstr);

has og_title => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has description => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has og_url => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has og_type => (
  is      => 'ro',
  isa     => 'Str',
  default => 'website',
);

has og_description => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  default => sub ($self) { $self->description },
);

has og_site_name => (
  is      => 'ro',
  isa     => 'Str',
  default => 'Clapham Shopfronts',
);

has [qw(og_image og_image_alt)] => (
  is      => 'ro',
  isa     => 'Maybe[Str]',
  default => undef,
);

has [qw(image_width image_height)] => (
  is      => 'ro',
  isa     => 'Maybe[Int]',
  default => undef,
);

has site_url => (
  is      => 'ro',
  isa     => 'Maybe[Str]',
  default => undef,
);

has page_kind => (
  is      => 'ro',
  isa     => 'Str',
  default => 'page',
);

has photo_groups => (
  is      => 'ro',
  isa     => 'ArrayRef[HashRef]',
  default => sub { [] },
);

has premises => (
  is      => 'ro',
  isa     => 'Maybe[HashRef]',
  default => undef,
);

has annotations => (
  is      => 'ro',
  isa     => 'ArrayRef[HashRef]',
  default => sub { [] },
);

with qw(
  MooX::Role::SEOTags
  MooX::Role::JSON_LD
  ClaphamShopfronts::Role::WebURLs
);

sub BUILD ($self, $arguments) {
  $self->validate_web_url($self->og_url);
  $self->validate_web_url($self->og_image) if defined $self->og_image && length $self->og_image;
  $self->validate_web_url($self->site_url) if defined $self->site_url;

  for my $dimension (qw(image_width image_height)) {
    my $value = $self->$dimension;

    die "Image dimensions must be positive\n" if defined $value && $value <= 0;
  }
}

# HTML::Tiny escapes attributes, but element content must be escaped by us.
sub title_tag ($self) {
  return $self->_tag('title', {}, $self->_html->entity_encode($self->og_title));
}

# Search descriptions may differ from the social summary, as on the homepage.
sub description_tag ($self) {
  return $self->_tag('meta', {
    name    => 'description',
    content => $self->description,
  });
}

sub _image_tags ($self) {
  return '' unless defined $self->og_image && length $self->og_image;

  my @tags;

  for my $dimension (qw(width height)) {
    my $attribute = "image_$dimension";
    my $value = $self->$attribute;

    push @tags, $self->_tag('meta', {
      property => "og:image:$dimension",
      content  => $value,
    }) if defined $value;
  }

  if (defined $self->og_image_alt && length $self->og_image_alt) {
    push @tags, $self->_tag('meta', {
      name    => 'twitter:image:alt',
      content => $self->og_image_alt,
    });
  }

  return join "\n", @tags;
}

around tags => sub ($original, $self) {
  return join "\n", grep { length } ($self->$original(), $self->_image_tags);
};

sub json_ld_type ($self) {
  return $self->page_kind eq 'gallery' ? 'CollectionPage' : 'WebPage';
}

sub json_ld_fields ($self) {
  return [
    {'@id' => sub ($page) { $page->og_url . '#webpage' }},
    {url => 'og_url'},
    {name => 'og_title'},
    'description',
    {inLanguage => sub ($page) { 'en-GB' }},
    {isPartOf => '_website_data'},
    {mainEntity => '_main_entity'},
    {hasPart => '_parts'},
    {primaryImageOfPage => '_primary_image'},
  ];
}

# Template Toolkit writes UTF-8; keep JSON as Perl characters until then.
sub _build_json_ld_encoder ($self) {
  return JSON::MaybeXS->new->canonical->pretty->utf8(0)->convert_blessed;
}

around json_ld => sub ($original, $self) {
  my $json = $self->$original();

  # JSON escapes preserve the data while preventing HTML script termination.
  $json =~ s/([<>&\x{2028}\x{2029}])/sprintf '\\u%04x', ord($1)/ge;

  return $json;
};

sub _website_data ($self) {
  return undef unless defined $self->site_url;

  return {
    '@type'    => 'WebSite',
    '@id'      => $self->site_url . '/#website',
    url        => $self->site_url . '/',
    name       => $self->og_site_name,
    inLanguage => 'en-GB',
  };
}

sub _image_id ($self, $photo) {
  return $self->site_url . '/photos/#' . $photo->{image_anchor};
}

sub _image_data ($self, $group) {
  my @subjects = @{$group->{subjects}};
  my @dates = uniqstr map { $_->{taken_on} } @subjects;

  die "Shared photograph has inconsistent capture dates\n" unless @dates == 1;

  my @captions = uniqstr map { $_->{caption} } @subjects;
  my @names = uniqstr map { $_->{business_name} } @subjects;
  my @credits = uniqstr grep { defined $_ && length $_ } map { $_->{attribution} } @subjects;
  my %seen;
  my @places = grep { !$seen{$_->{'@id'}}++ } map { $_->{premises} } @subjects;
  my $id = $self->_image_id($group);
  my $image = {
    '@type'        => 'ImageObject',
    '@id'          => $id,
    url            => $id,
    contentUrl     => $self->absolute_web_url($group->{image_url}, $self->site_url . '/'),
    thumbnailUrl   => $self->absolute_web_url($group->{small_url}, $self->site_url . '/'),
    encodingFormat => 'image/webp',
    name           => join(' / ', @names) . ' — ' . $dates[0],
    caption        => @captions == 1 ? $captions[0] : \@captions,
    dateCreated    => $dates[0],
    about          => \@places,
  };

  $image->{creditText} = @credits == 1 ? $credits[0] : \@credits if @credits;

  for my $dimension (qw(width height)) {
    next unless defined $group->{"image_$dimension"};

    $image->{$dimension} = {
      '@type'  => 'QuantitativeValue',
      value    => 0 + $group->{"image_$dimension"},
      unitText => 'px',
    };
  }

  return $image;
}

sub _main_entity ($self) {
  return $self->premises if defined $self->premises;

  if ($self->page_kind eq 'gallery') {
    my @items;

    for my $group (@{$self->photo_groups}) {
      push @items, {
        '@type'  => 'ListItem',
        position => 1 + @items,
        item     => $self->_image_data($group),
      };
    }

    return {
      '@type'         => 'ItemList',
      '@id'           => $self->og_url . '#photographs',
      itemListOrder   => 'https://schema.org/ItemListOrderDescending',
      numberOfItems   => scalar @items,
      itemListElement => \@items,
    };
  }

  return {'@id' => $self->site_url . '/#website'}
    if $self->page_kind eq 'home' && defined $self->site_url;

  return undef;
}

sub _parts ($self) {
  return undef unless $self->page_kind eq 'unit';

  my @parts = map { $self->_image_data($_) } @{$self->photo_groups};

  for my $event (@{$self->annotations}) {
    next unless $event->{reported} || $event->{source_url};

    my $annotation = {
      '@type'          => 'CreativeWork',
      name             => $event->{title},
      text             => $event->{description},
      description      => $event->{reported} ? 'Reported, unconfirmed' : 'Published source',
      temporalCoverage => $event->{date},
      about            => {'@id' => $self->premises->{'@id'}},
    };

    $annotation->{citation} = $event->{source_url} if $event->{source_url};
    push @parts, $annotation;
  }

  return @parts ? \@parts : undef;
}

sub _primary_image ($self) {
  return {'@id' => $self->_image_id($self->photo_groups->[0])} if @{$self->photo_groups};
  return undef unless defined $self->og_image && length $self->og_image;

  return {
    '@type'    => 'ImageObject',
    '@id'      => $self->og_image,
    contentUrl => $self->og_image,
  };
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
