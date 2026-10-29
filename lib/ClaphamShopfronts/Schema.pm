use utf8;
package ClaphamShopfronts::Schema;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use Moose;
use MooseX::MarkAsMethods autoclean => 1;
extends 'DBIx::Class::Schema';

__PACKAGE__->load_namespaces;


# Created by DBIx::Class::Schema::Loader v0.07053 @ 2026-10-29 16:55:12
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:AE8HqEqFXs2/uktXmtV2uw

use v5.36;
use DBD::SQLite::Constants qw(SQLITE_OPEN_READONLY SQLITE_OPEN_READWRITE);
use Path::Tiny qw(path);

sub connect_database ($class, $filename, %options) {
  my $database = path($filename)->absolute;

  die "Database not found: $database\n" unless $database->is_file;

  my $schema = $class->connect(
    "dbi:SQLite:dbname=$database",
    '', '', {
      sqlite_open_flags                => $options{read_only} ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE,
      sqlite_unicode                   => 1,
      sqlite_use_immediate_transaction => 1,
      AutoCommit                       => 1,
      RaiseError                       => 1,
      on_connect_do                    => ['PRAGMA foreign_keys = ON', 'PRAGMA recursive_triggers = OFF'],
    }
  );

  my $version = $schema->storage->dbh->selectrow_array('PRAGMA user_version');

  die "Database schema needs migration; run perl bin/migrate-db.pl\n"
    unless $options{allow_old_schema} || $version == 2;

  return $schema;
}

# You can replace this text with custom code or comments, and it will be preserved on regeneration
__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;
