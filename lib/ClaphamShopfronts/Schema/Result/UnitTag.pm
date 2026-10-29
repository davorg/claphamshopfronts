use utf8;
package ClaphamShopfronts::Schema::Result::UnitTag;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

ClaphamShopfronts::Schema::Result::UnitTag

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<unit_tags>

=cut

__PACKAGE__->table("unit_tags");

=head1 ACCESSORS

=head2 unit_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 tag_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "unit_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "tag_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</unit_id>

=item * L</tag_id>

=back

=cut

__PACKAGE__->set_primary_key("unit_id", "tag_id");

=head1 RELATIONS

=head2 tag

Type: belongs_to

Related object: L<ClaphamShopfronts::Schema::Result::Tag>

=cut

__PACKAGE__->belongs_to(
  "tag",
  "ClaphamShopfronts::Schema::Result::Tag",
  { id => "tag_id" },
  { is_deferrable => 0, on_delete => "CASCADE", on_update => "NO ACTION" },
);

=head2 unit

Type: belongs_to

Related object: L<ClaphamShopfronts::Schema::Result::Unit>

=cut

__PACKAGE__->belongs_to(
  "unit",
  "ClaphamShopfronts::Schema::Result::Unit",
  { id => "unit_id" },
  { is_deferrable => 0, on_delete => "CASCADE", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2026-10-29 12:35:57
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:pGX2Ye6c+PkTll78dEKogg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
