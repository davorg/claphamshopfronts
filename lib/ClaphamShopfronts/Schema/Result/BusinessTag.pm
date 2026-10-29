use utf8;
package ClaphamShopfronts::Schema::Result::BusinessTag;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

ClaphamShopfronts::Schema::Result::BusinessTag

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 TABLE: C<business_tags>

=cut

__PACKAGE__->table("business_tags");

=head1 ACCESSORS

=head2 business_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=head2 tag_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "business_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "tag_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</business_id>

=item * L</tag_id>

=back

=cut

__PACKAGE__->set_primary_key("business_id", "tag_id");

=head1 RELATIONS

=head2 business

Type: belongs_to

Related object: L<ClaphamShopfronts::Schema::Result::Business>

=cut

__PACKAGE__->belongs_to(
  "business",
  "ClaphamShopfronts::Schema::Result::Business",
  { id => "business_id" },
  { is_deferrable => 0, on_delete => "CASCADE", on_update => "NO ACTION" },
);

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


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2026-10-29 16:55:12
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:6C4VIHhUC+dCLJKB3vM70A


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
