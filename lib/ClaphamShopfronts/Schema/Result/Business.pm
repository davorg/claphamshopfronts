use utf8;
package ClaphamShopfronts::Schema::Result::Business;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

ClaphamShopfronts::Schema::Result::Business

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 TABLE: C<businesses>

=cut

__PACKAGE__->table("businesses");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'text'
  is_nullable: 0

=head2 normalised_name

  data_type: 'text'
  is_nullable: 0

=head2 business_type_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 is_chain

  data_type: 'integer'
  default_value: 0
  is_nullable: 0

=head2 website

  data_type: 'text'
  is_nullable: 1

=head2 notes

  data_type: 'text'
  is_nullable: 1

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
  "name",
  { data_type => "text", is_nullable => 0 },
  "normalised_name",
  { data_type => "text", is_nullable => 0 },
  "business_type_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "is_chain",
  { data_type => "integer", default_value => 0, is_nullable => 0 },
  "website",
  { data_type => "text", is_nullable => 1 },
  "notes",
  { data_type => "text", is_nullable => 1 },
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

=head2 C<normalised_name_unique>

=over 4

=item * L</normalised_name>

=back

=cut

__PACKAGE__->add_unique_constraint("normalised_name_unique", ["normalised_name"]);

=head1 RELATIONS

=head2 business_tags

Type: has_many

Related object: L<ClaphamShopfronts::Schema::Result::BusinessTag>

=cut

__PACKAGE__->has_many(
  "business_tags",
  "ClaphamShopfronts::Schema::Result::BusinessTag",
  { "foreign.business_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 business_type

Type: belongs_to

Related object: L<ClaphamShopfronts::Schema::Result::BusinessType>

=cut

__PACKAGE__->belongs_to(
  "business_type",
  "ClaphamShopfronts::Schema::Result::BusinessType",
  { id => "business_type_id" },
  {
    is_deferrable => 0,
    join_type     => "LEFT",
    on_delete     => "SET NULL",
    on_update     => "NO ACTION",
  },
);

=head2 observations

Type: has_many

Related object: L<ClaphamShopfronts::Schema::Result::Observation>

=cut

__PACKAGE__->has_many(
  "observations",
  "ClaphamShopfronts::Schema::Result::Observation",
  { "foreign.business_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 occupancies

Type: has_many

Related object: L<ClaphamShopfronts::Schema::Result::Occupancy>

=cut

__PACKAGE__->has_many(
  "occupancies",
  "ClaphamShopfronts::Schema::Result::Occupancy",
  { "foreign.business_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 tags

Type: many_to_many

Composing rels: L</business_tags> -> tag

=cut

__PACKAGE__->many_to_many("tags", "business_tags", "tag");


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2026-10-29 16:55:12
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:eAfot60F8/rNETTmM3oDcg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
