use v5.36;
use feature 'try';
no warnings 'experimental::try';
use Test::More;
use lib 'lib', 't/lib';
use ClaphamTest qw(fixture seed_page);
use ClaphamShopfronts::Util qw(file_sha);
use Path::Tiny qw(path);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

try {
  require DBIx::Class::Schema::Loader;
} catch ($error) {
  plan skip_all => 'DBIx::Class::Schema::Loader is needed for regeneration checks (development dependency)';
}

sub run_command (@command) {
  my ($input, $output);
  my $error = gensym;
  my $pid = open3($input, $output, $error, @command);
  close $input;

  my $stdout = do { local $/; <$output> } // '';
  my $stderr = do { local $/; <$error> } // '';
  waitpid $pid, 0;

  return ($? >> 8, $stdout, $stderr);
}

sub generated_files ($root) {
  return {
    map {"" . $_->relative($root) => file_sha($_)}
      ($root->child('lib/ClaphamShopfronts/Schema.pm'),
       $root->child('lib/ClaphamShopfronts/Schema/Result')->children(qr/\.pm$/))
  };
}

subtest 'regeneration follows the DDL and preserves custom code and populated data' => sub {
  my ($root, $schema) = fixture();
  seed_page($root, $schema);
  $schema->storage->disconnect;

  for my $relative ('bin/regenerate-schema', 'db/claphamshopfronts.ddl',
                    'lib/ClaphamShopfronts/Schema.pm',
                    map {"" . $_} path('lib/ClaphamShopfronts/Schema/Result')->children(qr/\.pm$/)) {
    my $destination = $root->child($relative);
    $destination->parent->mkpath;
    path($relative)->copy($destination);
  }

  my $schema_file = $root->child('lib/ClaphamShopfronts/Schema.pm');
  $schema_file->append_utf8("\nsub regeneration_probe { return 'custom code preserved' }\n");
  $root->child('db/claphamshopfronts.ddl')->append_utf8("\nALTER TABLE units ADD COLUMN regeneration_probe TEXT;\n");
  my $database = $root->child('db/claphamshopfront.db');
  my $before = file_sha($database);
  my $script = "" . $root->child('bin/regenerate-schema');

  my ($exit, $stdout, $stderr) = run_command($^X, $script);
  is $exit, 0, 'regeneration succeeds from outside its repository root' or diag $stderr;
  like $stdout, qr/Regenerated ClaphamShopfronts::Schema/, 'completion reported';
  like $root->child('lib/ClaphamShopfronts/Schema/Result/Unit.pm')->slurp_utf8,
    qr/=head2 regeneration_probe/, 'new DDL column appears in result class';
  like $schema_file->slurp_utf8, qr/sub connect_database/, 'custom database connection helper preserved';
  like $schema_file->slurp_utf8, qr/sub regeneration_probe \{ return 'custom code preserved' \}/,
    'additional custom code preserved';
  is file_sha($database), $before, 'populated database bytes unchanged';

  ($exit, $stdout, $stderr) = run_command(
    $^X, '-I' . $root->child('lib'), '-MClaphamShopfronts::Schema', '-e',
    q{die "wrong source count" unless scalar(ClaphamShopfronts::Schema->sources) == 11;
      die "missing column" unless ClaphamShopfronts::Schema->source('Unit')->has_column('regeneration_probe');
      die "lost custom code" unless ClaphamShopfronts::Schema->regeneration_probe eq 'custom code preserved';
      die "schema is not Moose" unless ClaphamShopfronts::Schema->meta->isa('Moose::Meta::Class');
      die "schema is mutable" unless ClaphamShopfronts::Schema->meta->is_immutable;
      for my $source (ClaphamShopfronts::Schema->sources) {
        my $class = ClaphamShopfronts::Schema->source($source)->result_class;
        die "$class is not Moose" unless $class->meta->isa('Moose::Meta::Class');
        die "$class is mutable" unless $class->meta->is_immutable;
      }}
  );
  is $exit, 0, 'regenerated Moose classes load immutably with eleven tables and no current_* views' or diag $stderr;

  my $generated = generated_files($root);
  ($exit, $stdout, $stderr) = run_command($^X, $script);
  is $exit, 0, 'safe regeneration repeat' or diag $stderr;
  is_deeply generated_files($root), $generated, 'unchanged DDL produces unchanged files';

  $root->child('db/claphamshopfronts.ddl')->append_utf8("\nINVALID SQL;\n");
  ($exit, $stdout, $stderr) = run_command($^X, $script);
  isnt $exit, 0, 'invalid DDL fails';
  like $stderr, qr/Schema regeneration failed:/, 'failure reported clearly';
  is_deeply generated_files($root), $generated, 'failed DDL leaves existing classes intact';
  is file_sha($database), $before, 'failure leaves populated database intact too';
};

done_testing;
