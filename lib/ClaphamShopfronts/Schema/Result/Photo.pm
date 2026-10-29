use utf8;
package ClaphamShopfronts::Schema::Result::Photo;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

ClaphamShopfronts::Schema::Result::Photo

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

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


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2026-10-29 12:35:57
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:PMOgRT4DIUvrmkXAi9V7dw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
