use utf8;
package ClaphamShopfronts::Schema::Result::Photo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

ClaphamShopfronts::Schema::Result::Photo

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 TABLE: C<photos>

=cut

__PACKAGE__->table("photos");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 unit_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 observation_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 taken_on

  data_type: 'text'
  is_nullable: 0

=head2 source_type

  data_type: 'text'
  is_nullable: 0

=head2 filename

  data_type: 'text'
  is_nullable: 1

=head2 source_url

  data_type: 'text'
  is_nullable: 1

=head2 attribution

  data_type: 'text'
  is_nullable: 1

=head2 caption

  data_type: 'text'
  is_nullable: 1

=head2 notes

  data_type: 'text'
  is_nullable: 1

=head2 created_at

  data_type: 'text'
  default_value: current_timestamp
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "unit_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "observation_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "taken_on",
  { data_type => "text", is_nullable => 0 },
  "source_type",
  { data_type => "text", is_nullable => 0 },
  "filename",
  { data_type => "text", is_nullable => 1 },
  "source_url",
  { data_type => "text", is_nullable => 1 },
  "attribution",
  { data_type => "text", is_nullable => 1 },
  "caption",
  { data_type => "text", is_nullable => 1 },
  "notes",
  { data_type => "text", is_nullable => 1 },
  "created_at",
  {
    data_type     => "text",
    default_value => \"current_timestamp",
    is_nullable   => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 observation

Type: belongs_to

Related object: L<ClaphamShopfronts::Schema::Result::Observation>

=cut

__PACKAGE__->belongs_to(
  "observation",
  "ClaphamShopfronts::Schema::Result::Observation",
  { id => "observation_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "SET NULL",
    on_update     => "NO ACTION",
  },
);

=head2 unit

Type: belongs_to

Related object: L<ClaphamShopfronts::Schema::Result::Unit>

=cut

__PACKAGE__->belongs_to(
  "unit",
  "ClaphamShopfronts::Schema::Result::Unit",
  { id => "unit_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "SET NULL",
    on_update     => "NO ACTION",
  },
);


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2026-10-29 16:55:12
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:sjudiHEgM8bK2WxcaN8VGw


use v5.36;
use Path::Tiny qw(path);
use URI::Escape qw(uri_escape_utf8);
use Image::Magick;
use Digest::SHA qw(sha256_hex);
use Encode qw(encode_utf8);

with 'ClaphamShopfronts::Role::Dates';

sub photograph_date ($self) {
  return $self->display_date($self->taken_on);
}

sub image_anchor ($self) {
  return 'image-' . sha256_hex(encode_utf8($self->filename));
}

sub image_assets ($self, $root, $base) {
  my $filename = $self->filename;

  die "Expected an image-root-relative WebP filename: $filename\n"
    if $filename =~ m{^/|(?:^|/)\.\.(?:/|$)|\\} || $filename !~ /\.webp$/;

  (my $thumbnail = $filename) =~ s/\.webp$/-small.webp/;
  my $images = path($root)->child('docs/images')->realpath;
  my @sizes;

  for my $relative ($filename, $thumbnail) {
    my $file = $images->child($relative);

    die "Published image not found: $relative\n" unless $file->is_file;
    die "Image path leaves published directory\n" unless index("" . $file->realpath, "$images/") == 0;

    my $image = Image::Magick->new;
    my $error = $image->Read("$file");

    die "Cannot read image $file: $error\n" if "$error";

    push @sizes, [$image->Get('width', 'height')];
  }

  return {
    image_anchor => $self->image_anchor,
    image_url    => $base . uri_escape_utf8($filename, '^A-Za-z0-9\-._~/'),
    small_url    => $base . uri_escape_utf8($thumbnail, '^A-Za-z0-9\-._~/'),
    image_width  => $sizes[0][0],
    image_height => $sizes[0][1],
    small_width  => $sizes[1][0],
    small_height => $sizes[1][1],
  };
}

__PACKAGE__->meta->make_immutable;
1;
