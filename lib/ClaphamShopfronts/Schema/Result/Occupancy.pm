use utf8;
package ClaphamShopfronts::Schema::Result::Occupancy;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

ClaphamShopfronts::Schema::Result::Occupancy

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<occupancies>

=cut

__PACKAGE__->table("occupancies");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 unit_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 business_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 occupancy_status

  data_type: 'text'
  is_nullable: 0

=head2 valid_from

  data_type: 'text'
  is_nullable: 0

=head2 valid_to

  data_type: 'text'
  is_nullable: 1

=head2 name_as_displayed

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
  "unit_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "business_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "occupancy_status",
  { data_type => "text", is_nullable => 0 },
  "valid_from",
  { data_type => "text", is_nullable => 0 },
  "valid_to",
  { data_type => "text", is_nullable => 1 },
  "name_as_displayed",
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

=head1 RELATIONS

=head2 business

Type: belongs_to

Related object: L<ClaphamShopfronts::Schema::Result::Business>

=cut

__PACKAGE__->belongs_to(
  "business",
  "ClaphamShopfronts::Schema::Result::Business",
  { id => "business_id" },
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
  { is_deferrable => 0, on_delete => "RESTRICT", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2026-10-29 12:35:57
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ymLpyxoNkhYg2EU35bcDDA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
