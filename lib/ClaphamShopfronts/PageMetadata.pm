package ClaphamShopfronts::PageMetadata;

use v5.36;
use Moose;

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

with 'MooX::Role::SEOTags', 'ClaphamShopfronts::Role::WebURLs';

sub BUILD ($self, $arguments) {
  $self->validate_web_url($self->og_url);
  $self->validate_web_url($self->og_image) if defined $self->og_image && length $self->og_image;

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

no Moose;
__PACKAGE__->meta->make_immutable;

1;
