use v5.36;
use feature 'try';
no warnings 'experimental::try';
use Test::More;
use lib 'lib', 't/lib';
use ClaphamTest qw(fixture seed_page snapshot file_sha);
use ClaphamShopfronts::Site;

my @pages = (
  {
    file      => 'index.html',
    prefix    => '',
    home_url  => './',
    canonical => 'https://claphamshopfronts.com/',
    modal     => 0,
  }, {
    file      => 'photos/index.html',
    prefix    => '../',
    home_url  => '../',
    canonical => 'https://claphamshopfronts.com/photos/',
    modal     => 0,
  }, {
    file      => 'shopfronts/sw4-7ts-7/index.html',
    prefix    => '../../',
    home_url  => '../../',
    canonical => 'https://claphamshopfronts.com/shopfronts/sw4-7ts-7/',
    modal     => 1,
  }
);

subtest 'all page types share one wrapper with links at the correct depth' => sub {
  my ($root, $schema) = fixture();
  seed_page($root, $schema);
  $schema->storage->disconnect;

  ok !$root->child('docs/index.html')->exists, 'no generated homepage is needed to build';

  my $database = $root->child('db/claphamshopfront.db');
  my $before = file_sha($database);
  my $result = ClaphamShopfronts::Site->new(root => $root)->build;

  is scalar @{$result->{changed_files}}, 3, 'homepage, gallery and unit page created from templates';

  for my $page (@pages) {
    my $html = $root->child('docs', $page->{file})->slurp_utf8;
    my $prefix = $page->{prefix};

    subtest $page->{file} => sub {
      for my $tag (qw(html head body main title)) {
        is scalar(() = $html =~ /<\Q$tag\E\b/g), 1, "one $tag element";
      }

      is scalar(() = $html =~ /<header class="site-header wrap">/g), 1, 'one shared navigation header';
      is scalar(() = $html =~ /<footer class="site-footer wrap">/g), 1, 'one shared footer';
      is scalar(() = $html =~ /rel="canonical"/g), 1, 'one canonical link';
      like $html, qr{<link\b(?=[^>]*\brel="canonical")(?=[^>]*\bhref="\Q$page->{canonical}\E")[^>]*>},
        'page-specific canonical URL';
      like $html, qr{href="\Q$page->{home_url}\E" aria-label="Clapham Shopfronts home"}, 'wordmark links home';
      like $html, qr{href="\Q$prefix\Ephotos/"}, 'gallery link resolves';
      like $html, qr{href="\Q$prefix\E#the-project"}, 'homepage project anchor resolves';
      like $html, qr{href="\Q$prefix\E#contribute"}, 'homepage contribution anchor resolves';
      like $html, qr{href="\Q$prefix\Estyles.css"}, 'stylesheet resolves';
      like $html, qr{fonts.googleapis.com/css2}, 'fonts preserved';
      like $html, qr{gtag\('config', 'G-KRMR11D4WG'\)}, 'analytics preserved';
      like $html, qr{href="https://davecross.co.uk/">Dave Cross}, 'project credit preserved';
      like $html, qr{href="#main">Back to the top}, 'footer anchor stays on its own page';

      if ($page->{modal}) {
        like $html, qr{src="\Q$prefix\Ephoto-modal.js" defer}, 'unit page loads carousel script';
      } else {
        unlike $html, qr{photo-modal.js}, 'other page types have no carousel script';
      }
    };
  }

  like $root->child('docs/photos/index.html')->slurp_utf8,
    qr{href="../photos/" aria-current="page">All photos}, 'gallery navigation remains active';
  like $root->child('docs/index.html')->slurp_utf8,
    qr{Our neighbourhood, in watercolour}, 'homepage artwork and copy preserved';
  is file_sha($database), $before, 'full site build leaves database bytes unchanged';
};

subtest 'generated HTML can be edited or removed without becoming template input' => sub {
  my ($root, $schema) = fixture();
  seed_page($root, $schema);

  ClaphamShopfronts::Site->new(root => $root)->build;
  my %expected = map {$_->{file} => $root->child('docs', $_->{file})->slurp_utf8} @pages;
  my $home = $root->child('docs/index.html');

  $home->spew_utf8('An edited output file is not a source template.');
  my $before = snapshot($root);

  try {
    ClaphamShopfronts::Site->new(root => $root)->build(check => 1);
    fail 'edited homepage detected';
  } catch ($error) {
    like $error, qr{need rebuilding: docs/index.html}, 'edited homepage detected';
  }

  is_deeply snapshot($root), $before, 'check mode leaves edited output and all other files untouched';

  my $result = ClaphamShopfronts::Site->new(root => $root)->build;
  is_deeply $result->{changed_files}, ['docs/index.html'], 'only edited homepage needs restoring';
  is $home->slurp_utf8, $expected{'index.html'}, 'homepage restored entirely from source';

  $root->child('docs', $_->{file})->remove for @pages;
  $before = snapshot($root);

  try {
    ClaphamShopfronts::Site->new(root => $root)->build(check => 1);
    fail 'missing pages detected';
  } catch ($error) {
    like $error, qr/need rebuilding/, 'missing pages detected';
  }

  is_deeply snapshot($root), $before, 'checking absent pages creates no output';
  ClaphamShopfronts::Site->new(root => $root)->build;

  for my $page (@pages) {
    is $root->child('docs', $page->{file})->slurp_utf8, $expected{$page->{file}},
      "$page->{file} regenerates identically with no previous HTML";
  }
};

subtest 'shared partial edits propagate to every page after a successful preflight' => sub {
  my ($root, $schema) = fixture();
  seed_page($root, $schema);
  ClaphamShopfronts::Site->new(root => $root)->build;

  my $head = $root->child('templates/head.tt');
  my $markup = $head->slurp_utf8;
  $markup =~ s{</head>}{  <meta name="shared-template-check" content="updated">\n</head>};
  $head->spew_utf8($markup);

  my $nav = $root->child('templates/nav.tt');
  $markup = $nav->slurp_utf8;
  $markup =~ s{</nav>}{  <a href="[% page.prefix | html %]new/">New shared link</a>\n    </nav>};
  $nav->spew_utf8($markup);
  $root->child('templates/footer.tt')->append_utf8("  <p>Updated shared footer</p>\n");
  my $before = snapshot($root);

  try {
    ClaphamShopfronts::Site->new(root => $root)->build(check => 1);
    fail 'partial changes detected';
  } catch ($error) {
    like $error, qr/need rebuilding/, 'partial changes detected';
  }

  is_deeply snapshot($root), $before, 'preflight reports changes without writing';
  my $builder = ClaphamShopfronts::Site->new(root => $root);
  is scalar @{$builder->build->{changed_files}}, 3, 'every page rebuilt for shared edits';

  for my $page (@pages) {
    my $html = $root->child('docs', $page->{file})->slurp_utf8;
    like $html, qr{name="shared-template-check" content="updated"}, "$page->{file} uses shared head";
    like $html, qr{href="\Q$page->{prefix}\Enew/">New shared link}, "$page->{file} uses shared navigation";
    like $html, qr{Updated shared footer}, "$page->{file} uses shared footer";
  }

  is_deeply $builder->build(check => 1)->{changed_files}, [], 'repeat build is current';
};

done_testing;
