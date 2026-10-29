use v5.36;
use feature 'try';
no warnings 'experimental::try';
use Test::More;
use lib 'lib', 't/lib';
use ClaphamTest qw(fixture seed_page snapshot);
use ClaphamShopfronts::Site;
use Path::Tiny qw(path);
use IPC::Open3 qw(open3);
use IO::Select;
use Symbol qw(gensym);

try {
  require DBIx::Class::Schema::Loader;
} catch ($error) {
  plan skip_all => 'DBIx::Class::Schema::Loader is needed for check-command tests (development dependency)';
}

sub run_check ($root) {
  my ($input, $output);
  my $error = gensym;
  my $pid = open3($input, $output, $error, $^X, "" . $root->child('bin/check'));
  close $input;

  # Drain both streams together; failing subprocesses may write to either one.
  my $streams = IO::Select->new($output, $error);
  my $report = '';

  while (my @ready = $streams->can_read) {
    for my $stream (@ready) {
      my $length = sysread($stream, my $buffer, 8192);
      die "Cannot read check output: $!" unless defined $length;

      if ($length) {
        $report .= $buffer;
      } else {
        $streams->remove($stream);
        close $stream;
      }
    }
  }

  waitpid $pid, 0;
  return ($? >> 8, $report);
}

subtest 'checks report failures without modifying project files' => sub {
  my ($root, $schema) = fixture();
  my $photo = seed_page($root, $schema);
  ClaphamShopfronts::Site->new(root => $root)->build;

  my @sources = map {path($_)} qw(bin/check bin/regenerate-schema bin/build-site.pl db/claphamshopfronts.ddl);
  my $iterator = path('lib')->iterator({recurse => 1});

  while (my $file = $iterator->()) {
    push @sources, $file if $file->is_file && $file =~ /\.pm\z/;
  }

  for my $source (@sources) {
    my $destination = $root->child("$source");
    $destination->parent->mkpath;
    $source->copy($destination);
  }

  # The child runs an isolated suite, avoiding a recursive invocation of this test.
  $root->child('t')->mkpath;
  my $test = $root->child('t/smoke.t');
  my $passing_test = "use Test::More tests => 1; ok 1, 'fixture test';\n";
  $test->spew_utf8($passing_test);
  $root->child('pics/incoming/original.jpg')->spew_raw('original photograph');
  $schema->storage->disconnect;

  my $before = snapshot($root);
  my ($exit, $report) = run_check($root);
  is $exit, 0, 'passes when everything is current, even from outside its root' or diag $report;
  like $report, qr/PASS: Perl tests/, 'test success identified';
  like $report, qr/PASS: generated pages/, 'page success identified';
  like $report, qr/PASS: DBIC classes/, 'schema success identified';
  is_deeply snapshot($root), $before, 'success leaves database, originals, pages and sources unchanged';

  $test->spew_utf8("use Test::More tests => 1; ok 0, 'deliberate failure';\n");
  $before = snapshot($root);
  ($exit, $report) = run_check($root);
  isnt $exit, 0, 'a failing test fails the command';
  like $report, qr/FAIL: Perl tests/, 'failing stage identified';
  like $report, qr/PASS: DBIC classes/, 'later checks still run';
  is_deeply snapshot($root), $before, 'test failure leaves project files unchanged';
  $test->spew_utf8($passing_test);

  $photo->update({caption => 'A changed caption needs a rebuild.'});
  $schema->storage->disconnect;
  $before = snapshot($root);
  ($exit, $report) = run_check($root);
  isnt $exit, 0, 'stale pages fail the command';
  like $report, qr/FAIL: generated pages/, 'stale page stage identified';
  is_deeply snapshot($root), $before, 'stale pages are checked without rebuilding';
  ClaphamShopfronts::Site->new(root => $root)->build;

  my $ddl = $root->child('db/claphamshopfronts.ddl');
  my $definition = $ddl->slurp_utf8;
  $ddl->append_utf8("\nALTER TABLE units ADD COLUMN check_probe TEXT;\n");
  $before = snapshot($root);
  ($exit, $report) = run_check($root);
  isnt $exit, 0, 'a DDL change without regenerated classes fails';
  like $report, qr/FAIL: DBIC classes:.*Stale class: lib\/ClaphamShopfronts\/Schema\/Result\/Unit.pm/s,
    'stale class identified';
  is_deeply snapshot($root), $before, 'DDL check neither regenerates sources nor migrates the live database';
  $ddl->spew_utf8($definition);

  my $obsolete = $root->child('lib/ClaphamShopfronts/Schema/Result/Obsolete.pm');
  $obsolete->spew_utf8("package ClaphamShopfronts::Schema::Result::Obsolete;\n1;\n");
  $before = snapshot($root);
  ($exit, $report) = run_check($root);
  isnt $exit, 0, 'an obsolete generated class fails';
  like $report, qr/Obsolete class: lib\/ClaphamShopfronts\/Schema\/Result\/Obsolete.pm/,
    'fresh generation detects leftover classes';
  is_deeply snapshot($root), $before, 'obsolete files are reported without removal';
};

done_testing;
