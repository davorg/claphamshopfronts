use utf8;
package ClaphamShopfronts::Schema::Result::UnitRelationship;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

ClaphamShopfronts::Schema::Result::UnitRelationship

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<unit_relationships>

=cut

__PACKAGE__->table("unit_relationships");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 from_unit_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 to_unit_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 relationship_type

  data_type: 'text'
  is_nullable: 0

=head2 effective_date

  data_type: 'text'
  is_nullable: 0

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
  "from_unit_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "to_unit_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "relationship_type",
  { data_type => "text", is_nullable => 0 },
  "effective_date",
  { data_type => "text", is_nullable => 0 },
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

=head2 from_unit

Type: belongs_to

Related object: L<ClaphamShopfronts::Schema::Result::Unit>

=cut

__PACKAGE__->belongs_to(
  "from_unit",
  "ClaphamShopfronts::Schema::Result::Unit",
  { id => "from_unit_id" },
  { is_deferrable => 0, on_delete => "RESTRICT", on_update => "NO ACTION" },
);

=head2 to_unit

Type: belongs_to

Related object: L<ClaphamShopfronts::Schema::Result::Unit>

=cut

__PACKAGE__->belongs_to(
  "to_unit",
  "ClaphamShopfronts::Schema::Result::Unit",
  { id => "to_unit_id" },
  { is_deferrable => 0, on_delete => "RESTRICT", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2026-10-29 12:35:57
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:TIGKVtrkB+uA1+Ski6fyRA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
