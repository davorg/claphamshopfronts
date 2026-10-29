use utf8;
package ClaphamShopfronts::Schema::Result::Observation;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

ClaphamShopfronts::Schema::Result::Observation

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<observations>

=cut

__PACKAGE__->table("observations");

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

=head2 observed_on

  data_type: 'text'
  is_nullable: 0

=head2 observer

  data_type: 'text'
  is_nullable: 1

=head2 observed_status

  data_type: 'text'
  is_nullable: 0

=head2 observed_business_name

  data_type: 'text'
  is_nullable: 1

=head2 confidence

  data_type: 'text'
  default_value: 'high'
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
  "unit_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
  "business_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "observed_on",
  { data_type => "text", is_nullable => 0 },
  "observer",
  { data_type => "text", is_nullable => 1 },
  "observed_status",
  { data_type => "text", is_nullable => 0 },
  "observed_business_name",
  { data_type => "text", is_nullable => 1 },
  "confidence",
  { data_type => "text", default_value => "high", is_nullable => 0 },
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

=head2 photos

Type: has_many

Related object: L<ClaphamShopfronts::Schema::Result::Photo>

=cut

__PACKAGE__->has_many(
  "photos",
  "ClaphamShopfronts::Schema::Result::Photo",
  { "foreign.observation_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
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


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2026-10-29 13:30:38
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:McOdmRCcx+Op0zVExOe4Wg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
