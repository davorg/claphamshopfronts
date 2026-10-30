use utf8;
package ClaphamShopfronts::Schema::Result::Unit;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

ClaphamShopfronts::Schema::Result::Unit

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 TABLE: C<units>

=cut

__PACKAGE__->table("units");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 site_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 unit_code

  data_type: 'text'
  is_nullable: 0

=head2 slug

  data_type: 'text'
  is_nullable: 0

=head2 label

  data_type: 'text'
  is_nullable: 1

=head2 valid_from

  data_type: 'text'
  is_nullable: 0

=head2 valid_to

  data_type: 'text'
  is_nullable: 1

=head2 lifecycle_status

  data_type: 'text'
  default_value: 'active'
  is_nullable: 0

=head2 frontage_notes

  data_type: 'text'
  is_nullable: 1

=head2 source_confidence

  data_type: 'text'
  default_value: 'observed'
  is_nullable: 0

=head2 created_at

  data_type: 'text'
  default_value: current_timestamp
  is_nullable: 0

=head2 updated_at

  data_type: 'text'
  default_value: current_timestamp
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "site_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "unit_code",
  { data_type => "text", is_nullable => 0 },
  "slug",
  { data_type => "text", is_nullable => 0 },
  "label",
  { data_type => "text", is_nullable => 1 },
  "valid_from",
  { data_type => "text", is_nullable => 0 },
  "valid_to",
  { data_type => "text", is_nullable => 1 },
  "lifecycle_status",
  { data_type => "text", default_value => "active", is_nullable => 0 },
  "frontage_notes",
  { data_type => "text", is_nullable => 1 },
  "source_confidence",
  { data_type => "text", default_value => "observed", is_nullable => 0 },
  "created_at",
  {
    data_type     => "text",
    default_value => \"current_timestamp",
    is_nullable   => 0,
  },
  "updated_at",
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

=head1 UNIQUE CONSTRAINTS

=head2 C<slug_unique>

=over 4

=item * L</slug>

=back

=cut

__PACKAGE__->add_unique_constraint("slug_unique", ["slug"]);

=head2 C<unit_code_unique>

=over 4

=item * L</unit_code>

=back

=cut

__PACKAGE__->add_unique_constraint("unit_code_unique", ["unit_code"]);

=head1 RELATIONS

=head2 observations

Type: has_many

Related object: L<ClaphamShopfronts::Schema::Result::Observation>

=cut

__PACKAGE__->has_many(
  "observations",
  "ClaphamShopfronts::Schema::Result::Observation",
  { "foreign.unit_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 occupancies

Type: has_many

Related object: L<ClaphamShopfronts::Schema::Result::Occupancy>

=cut

__PACKAGE__->has_many(
  "occupancies",
  "ClaphamShopfronts::Schema::Result::Occupancy",
  { "foreign.unit_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 photos

Type: has_many

Related object: L<ClaphamShopfronts::Schema::Result::Photo>

=cut

__PACKAGE__->has_many(
  "photos",
  "ClaphamShopfronts::Schema::Result::Photo",
  { "foreign.unit_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 site

Type: belongs_to

Related object: L<ClaphamShopfronts::Schema::Result::Site>

=cut

__PACKAGE__->belongs_to(
  "site",
  "ClaphamShopfronts::Schema::Result::Site",
  { id => "site_id" },
  { is_deferrable => 0, on_delete => "RESTRICT", on_update => "NO ACTION" },
);

=head2 unit_relationships_from_unit

Type: has_many

Related object: L<ClaphamShopfronts::Schema::Result::UnitRelationship>

=cut

__PACKAGE__->has_many(
  "unit_relationships_from_unit",
  "ClaphamShopfronts::Schema::Result::UnitRelationship",
  { "foreign.from_unit_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 unit_relationships_to_units

Type: has_many

Related object: L<ClaphamShopfronts::Schema::Result::UnitRelationship>

=cut

__PACKAGE__->has_many(
  "unit_relationships_to_units",
  "ClaphamShopfronts::Schema::Result::UnitRelationship",
  { "foreign.to_unit_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 unit_tags

Type: has_many

Related object: L<ClaphamShopfronts::Schema::Result::UnitTag>

=cut

__PACKAGE__->has_many(
  "unit_tags",
  "ClaphamShopfronts::Schema::Result::UnitTag",
  { "foreign.unit_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 tags

Type: many_to_many

Composing rels: L</unit_tags> -> tag

=cut

__PACKAGE__->many_to_many("tags", "unit_tags", "tag");


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2026-10-29 16:55:12
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Ls1+I6tjbp2jxAu75R7EMw


use v5.36;

sub validate_slug ($class, $slug) {
  die "Unit slug must contain lowercase letters, digits and single hyphens\n"
    unless defined $slug && !ref $slug && $slug =~ /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/;

  return $slug;
}

sub slug_from_address ($class, $postcode, $address, $explicit = undef) {
  return $class->validate_slug($explicit) if defined $explicit;

  my $compact = uc($postcode // '');
  $compact =~ s/\s+//g;

  die "Cannot derive a slug without a postcode; supply unit.slug\n"
    unless $compact =~ /\A([A-Z0-9]{2,4})([0-9][A-Z]{2})\z/;

  my ($outward, $inward) = ($1, $2);

  die "Cannot derive a street number from the address; supply unit.slug\n"
    unless ($address // '') =~ /^\s*(\d+[A-Za-z]?(?:\s*[-–—]\s*\d+[A-Za-z]?)?)(?=\s|,|$)/;

  my $number = $1;
  $number =~ s/\s+//g;
  $number =~ tr/–—/--/;

  return $class->validate_slug(lc "$outward-$inward-$number");
}

sub page_url ($self) {
  return 'shopfronts/' . $self->validate_slug($self->slug) . '/';
}

__PACKAGE__->meta->make_immutable;
1;
