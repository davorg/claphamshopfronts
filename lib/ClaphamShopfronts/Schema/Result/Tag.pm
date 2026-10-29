use utf8;
package ClaphamShopfronts::Schema::Result::Tag;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

ClaphamShopfronts::Schema::Result::Tag

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<tags>

=cut

__PACKAGE__->table("tags");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 name

  data_type: 'text'
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "name",
  { data_type => "text", is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 UNIQUE CONSTRAINTS

=head2 C<name_unique>

=over 4

=item * L</name>

=back

=cut

__PACKAGE__->add_unique_constraint("name_unique", ["name"]);

=head1 RELATIONS

=head2 business_tags

Type: has_many

Related object: L<ClaphamShopfronts::Schema::Result::BusinessTag>

=cut

__PACKAGE__->has_many(
  "business_tags",
  "ClaphamShopfronts::Schema::Result::BusinessTag",
  { "foreign.tag_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 unit_tags

Type: has_many

Related object: L<ClaphamShopfronts::Schema::Result::UnitTag>

=cut

__PACKAGE__->has_many(
  "unit_tags",
  "ClaphamShopfronts::Schema::Result::UnitTag",
  { "foreign.tag_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 businesses

Type: many_to_many

Composing rels: L</business_tags> -> business

=cut

__PACKAGE__->many_to_many("businesses", "business_tags", "business");

=head2 units

Type: many_to_many

Composing rels: L</unit_tags> -> unit

=cut

__PACKAGE__->many_to_many("units", "unit_tags", "unit");


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2026-10-29 12:35:57
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:VPJ3Z4RDbiKeDsjZ5l+HPg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
