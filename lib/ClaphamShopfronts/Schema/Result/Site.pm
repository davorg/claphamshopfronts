use utf8;
package ClaphamShopfronts::Schema::Result::Site;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

ClaphamShopfronts::Schema::Result::Site

=cut

use strict;
use warnings;

use Moose;
use MooseX::NonMoose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Core';

=head1 TABLE: C<sites>

=cut

__PACKAGE__->table("sites");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 site_code

  data_type: 'text'
  is_nullable: 0

=head2 street_address

  data_type: 'text'
  is_nullable: 0

=head2 postcode

  data_type: 'text'
  is_nullable: 1

=head2 latitude

  data_type: 'real'
  is_nullable: 1

=head2 longitude

  data_type: 'real'
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
  "site_code",
  { data_type => "text", is_nullable => 0 },
  "street_address",
  { data_type => "text", is_nullable => 0 },
  "postcode",
  { data_type => "text", is_nullable => 1 },
  "latitude",
  { data_type => "real", is_nullable => 1 },
  "longitude",
  { data_type => "real", is_nullable => 1 },
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

=head2 C<site_code_unique>

=over 4

=item * L</site_code>

=back

=cut

__PACKAGE__->add_unique_constraint("site_code_unique", ["site_code"]);

=head1 RELATIONS

=head2 units

Type: has_many

Related object: L<ClaphamShopfronts::Schema::Result::Unit>

=cut

__PACKAGE__->has_many(
  "units",
  "ClaphamShopfronts::Schema::Result::Unit",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2026-10-29 16:55:12
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:xAPjtaHQ/+uzOO+nyXmkvg


# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable;
1;
