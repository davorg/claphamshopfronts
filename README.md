# Clapham Shopfronts

A local history website documenting Clapham’s changing shopfronts. The static site lives in `docs/`, ready for GitHub Pages. Perl generates the homepage, shopfront pages and photo gallery using Template Toolkit and DBIx::Class before publication. The archive HTML is static; a small JavaScript enhancement opens larger photographs in a modal.

## Preview locally

```sh
http_this --host 127.0.0.1 --port 8000 --autoindex docs
```

Run this from the repository root using App::HTTPThis, then visit `http://localhost:8000`. The `--autoindex` option serves `index.html` for directory URLs, including shopfront pages.

## Design and artwork

The page uses Cormorant Garamond, DM Sans, and Caveat from Google Fonts, with local fallback fonts. Styles are in `docs/styles.css`.

The hero is a responsive collage of eight watercolour interpretations of the project's original photographs. It uses four columns on larger screens and two on phones. The paper, tape, and small rotations are CSS. Motion respects the visitor’s reduced-motion setting.

Finished paintings are in `docs/images/watercolours/`. Each has a full-size WebP and a smaller version for the page. A reusable, flattened collage is in `docs/images/hero-collage.webp`.

See [the artwork notes](artwork/README.md) for individual image links, source photographs, and the exact imagegen prompts.

The original Clapham High Street sign photograph used as the project's social avatar is [`docs/images/clapham-high-street-sign.jpg`](docs/images/clapham-high-street-sign.jpg). It is a branding asset, separate from the shopfront photo archive.

## Photograph storage

Photographs are stored in this GitHub repository for now. Original source photographs waiting for ingestion live in `pics/incoming/`; successfully ingested originals are retained in `pics/processed/`. Optimised copies for the website live under `docs/images/photos/`. See [Photograph intake](pics/README.md) for the workflow and the definition of a successful ingestion.

The intended future home for published images is an AWS-hosted `https://images.claphamshopfronts.com/`. Keep image paths independent of the hosting domain so the same directory structure can be copied there later.

For new photograph records, store a path relative to the published image root in `photos.filename`, for example `photos/2026/04/PXL_20260403_065904338.webp`. Keep the original Instagram post link, where available, in `photos.source_url`.

Page generation resolves these paths through the `image_base` setting in [`data/site.json`](data/site.json):

| Hosting | Image base | Example published URL |
| --- | --- | --- |
| GitHub Pages, initially | `/images/` | `/images/photos/2026/04/PXL_20260403_065904338.webp` |
| AWS, in future | `https://images.claphamshopfronts.com/` | `https://images.claphamshopfronts.com/photos/2026/04/PXL_20260403_065904338.webp` |

The photographs are imported using this path convention. The future move should preserve the relative paths and change the image base, leaving the database records intact. This setting controls archive photographs on shopfront pages and the homepage. The decorative watercolour artwork remains local to the website.

See [the database documentation](database.md) for the photo metadata and its relationships to units and observations.

## Import a photograph

The commands use Perl 5.36 or later, Moose, DBIx::Class, Template Toolkit, Image::ExifTool, and the Perl ImageMagick bindings. ImageMagick needs WebP support. Dependencies are listed in `cpanfile`; install them with your usual Perl environment:

```sh
cpanm --installdeps .
```

App::HTTPThis provides the optional local preview, and DBIx::Class::Schema::Loader is a development dependency for maintaining the schema classes. Install those tools with `cpanm --with-develop --installdeps .`.

Reviewed metadata lives in `data/photos/`. The first examples are [Pure Vintage in April](data/photos/PXL_20260403_065904338.json) and [Tony Voyage in October](data/photos/PXL_20261029_130247804.json). Check and then import a manifest:

```sh
perl bin/ingest-photo.pl --dry-run data/photos/PXL_20260403_065904338.json
perl bin/ingest-photo.pl data/photos/PXL_20260403_065904338.json
```

Rerunning an imported manifest reports `already_ingested` and does not create duplicate records. It is not a command for applying later corrections to a record. Application code lives in `lib/ClaphamShopfronts/`; DBIx::Class result classes map all eleven tables under `lib/ClaphamShopfronts/Schema/Result/`. SQLite continues to enforce the constraints and triggers in the DDL.

The importer and page generator use Moose constructors and typed, read-only attributes. Both compose `ClaphamShopfronts::Role::ProjectRoot`, which requires a `root` argument, accepts either a path string or a `Path::Tiny` object, and normalises it to an absolute path. Both named arguments and a hash reference are supported without modifying caller-owned arguments.

If one photograph shows two units, ingest it for the first unit, then use a second manifest with the same original and checksum plus `share_image_from` naming that first unit's code. The importer reuses the archived original and both WebP copies, creating a separate photo/observation association for the second unit with its own caption and business identity. Each manifest can be rerun safely. Shared images appear once among recent homepage photographs. The Jeannette Fashions and Elvira Graham manifests show this workflow:

```sh
perl bin/ingest-photo.pl data/photos/PXL_20260403_070044822.MP.json
perl bin/ingest-photo.pl data/photos/PXL_20260403_070044822.MP-elvira-graham.json
```

For a later photograph of the same physical frontage, retain its existing site and unit codes. The importer validates the address and active unit, then appends a new observation and photo. Each observation can identify its business independently of the occupancy state: the vacant April frontage identifies Pure Vintage; the occupied October frontage identifies Tony Voyage.

An unchanged status and occupant reuse the existing occupancy period. A changed status or occupied business creates a new period. The superseded period ends on its last supported observation date (inclusive), and the new period starts on the new observation date. The intervening gap is undetermined; these dates do not claim to be closure, handover, or opening dates. Backdated observations, conflicting same-day changes, or inconsistent existing timelines stop for manual review. Generate pages separately after a successful import.

When a reliable source establishes a final trading day, a new occupancy can include an optional manifest `occupancy_valid_to` date, with the evidence in `occupancy_notes`. The date is inclusive and must be on or after the photograph date. This ends the historical occupied period without inventing a vacant observation or a successor business. Applying an end date to an existing occupancy needs manual review. [Dentons](data/photos/PXL_20260403_065840506.json) provides an example.

## Database migrations

Fresh databases created from the DDL use schema version 2. For an existing version-0 or version-1 database, run:

```sh
perl bin/migrate-db.pl
```

This assigns each unit a stored, unique address slug in a transaction, preserving IDs, related records, timestamps, views, indexes, and triggers. A version-0 upgrade also adds the optional `observations.business_id` link and its index. Existing photo observations are identified only when their reviewed import metadata matches the recorded unit, date, and original checksum; sign text alone is not used to guess an identity. Migration repeats report `already_current`. Earlier schemas are retained as migration test fixtures in `t/fixtures/schema-v0.sql` and `t/fixtures/schema-v1.sql`.

## Regenerate DBIC classes

After changing [`db/claphamshopfronts.ddl`](db/claphamshopfronts.ddl), regenerate the schema and result classes with:

```sh
bin/regenerate-schema
```

The command uses DBIx::Class::Schema::Loader, already listed among the development dependencies. It loads the DDL into a temporary SQLite database, introspects that database in read-only mode, and writes `lib/ClaphamShopfronts/Schema.pm` and the eleven table classes under `lib/ClaphamShopfronts/Schema/Result/`. It enables `use_moose`, keeps the existing `current` naming convention and excludes the `current_*` views. Generated classes use Moose, with MooseX::NonMoose for result-class construction and MooseX::MarkAsMethods for namespace cleanup; these are runtime dependencies in `cpanfile`.

Custom code below Loader's `DO NOT MODIFY THIS OR ANYTHING ABOVE` marker is preserved, including `connect_database`. Put future custom methods below that marker and before `make_immutable`. Review the generated diff after changing the DDL. Repeating regeneration with unchanged DDL leaves the files unchanged.

Regeneration does not read or modify the populated `db/claphamshopfront.db`, and it does not apply migrations. Keep the migration code in step with the DDL and run migrations separately when upgrading an existing database. The command resolves paths from its own location, so it also works when called from another directory.

## Unit URLs

A unit's public URL uses its postcode and street number: `/shopfronts/sw4-7ts-7/` for 7 Clapham High Street, SW4 7TS. Letter suffixes and number ranges are retained: `sw4-7ts-7a` and `sw4-7ts-7-9`.

The importer generates `units.slug` once when creating a unit; migration assigns it to existing units. It remains stable when a business changes or an address is corrected. Internal identifiers such as `CHS0001-U01` remain unchanged and still select units in manifests and publication configuration.

For units sharing an address, or an address without a usable number or postcode, set an explicit `slug` inside the manifest's `unit` object, for example `"slug": "sw4-7ts-7-u2"`. Slugs accept lowercase letters, digits, and single separating hyphens. Collisions stop the import or migration for an explicit choice rather than silently renumbering units. An import cannot change an existing unit's stored slug.

## Generate the website

```sh
perl bin/build-site.pl
```

The generator reads SQLite in read-only mode and writes the homepage to `docs/index.html`, the photo gallery to `docs/photos/index.html`, and one page per published unit under `docs/shopfronts/<slug>/index.html`. The first unit is [7 Clapham High Street, from Pure Vintage to Tony Voyage](docs/shopfronts/sw4-7ts-7/index.html). Each unit page leads with its latest photograph and identified business, address, category, and dated state. Earlier photographs retain their original identities and dates below it, and the timeline includes each dated observation. The stored address URL remains stable if the business name changes.

Publication choices live in `data/site.json`. Its `shopfronts` entries select each `unit_code`. Photo identities and categories come from their linked observation businesses, so the latest page heading can change without relabelling earlier photos. Optional `reported_events` supply public historical annotations and are always labelled unconfirmed. Use `sourced_events` for events checked against a published source, such as Dentons' closure announcement; these have a “Published source” label and source link. Both event lists require a date, title and description. Sourced events also require a source URL and label; these are optional for owner reports. Event dates can be a year (`2020`), month (`2025-12`) or day (`2026-05-01`), preserving the precision of the evidence. Photograph and occupancy dates remain complete ISO dates. `confirmed_closures` identifies a specific business and observation date; each must match a vacant photo observation. The Pure Vintage opening and closure notes therefore remain attached to its history, not the later salon. Internal database notes are not published or parsed as page copy.

The homepage's **Recent photographs** section shows up to three photographs from published units, ordered by photograph date rather than import date. Each links to its own `#photo-<id>` anchor on the shopfront page. The whole homepage is generated from `templates/home.tt`, including its watercolours, project description and Instagram section. Edit the template and rebuild to update that copy.

The complete [All photos gallery](docs/photos/index.html) is generated at `/photos/`, linked from the top navigation and the homepage's recent section. It includes every photograph from published units, newest first, including earlier photographs of the same unit. A shared image appears once, with a separate dated-photo link for each of its units. Unit pages link back to this gallery. The gallery works without JavaScript and uses the same configurable image base as other archive photographs.

The homepage, unit and gallery templates each use `WRAPPER page.tt`. The shared wrapper supplies the HTML document, skip link, head, navigation, footer and page-specific scripts. Its partials are `templates/head.tt`, `templates/nav.tt` and `templates/footer.tt`; edit these to update shared fonts, analytics, navigation or project credit across the site. Explicit page data supplies escaped metadata, canonical URLs, relative link prefixes, body classes and active navigation.

Page content lives in `templates/home.tt`, `templates/shopfront.tt` and `templates/all-photos.tt`. The reusable `templates/photograph.tt` and `templates/recent-photographs.tt` render photograph sections. Rebuild after editing any template. Generated HTML in `docs/` is output only: it can be removed and regenerated from the templates, metadata and published images. Styling stays in `docs/styles.css`, and the carousel enhancement stays in `docs/photo-modal.js`.

`ClaphamShopfronts::Site->build` coordinates private methods for loading records, preparing photo and unit-page data, grouping shared archive images, rendering pages and applying the output plan. All assets and rendered pages are validated before the output method writes any files, so a missing image, invalid record or template error leaves existing pages unchanged.

On a shopfront page, clicking any photograph or its “View larger” link opens that photograph in a native dialog carousel. Previous/next buttons and the left/right arrow keys browse all photographs of that unit, newest first, wrapping at either end. Each slide shows its business name, date, photographer credit where available, and position in the set. Navigation buttons are hidden for a single photograph. Close it with ×, Escape, or the backdrop; keyboard focus returns to the original link, even after browsing. Without JavaScript, these links still open the image directly. The enhancement is in `docs/photo-modal.js`.

Check whether generated output needs rebuilding without writing files:

```sh
perl bin/build-site.pl --check
```

To move the archive photographs to the intended AWS host later, change `image_base` in `data/site.json` and rebuild. The `--image-base` option can override that setting for a particular build. The generator currently reads the local published image copies to check their existence and dimensions, even when emitting external URLs; retain those local copies while building. No AWS resources are provisioned by this command.

## Checks

Install the runtime, test and development dependencies using Perl 5.36 or later:

```sh
cpanm --with-develop --installdeps .
```

ImageMagick must include JPEG and WebP support, with its `Image::Magick` Perl bindings built for the Perl you are using. A distribution's prebuilt Perl bindings generally require its system Perl; if you use a separate Perl installation, build the bindings for that installation too.

Run all checks with:

```sh
bin/check
```

This runs the Perl test suite, checks generated pages with `bin/build-site.pl --check`, and compares the DBIC classes with a fresh generation from the DDL in a temporary directory. It reports each failing stage, attempts the remaining checks, and exits nonzero if anything fails. The command works from any directory and leaves the populated database, original photographs, generated pages and source files unchanged.

The schema comparison checks generated code, including missing and obsolete classes. It ignores Loader's version, timestamp and checksum comments and custom code below its marker. If the DDL changes, run `bin/regenerate-schema`, review the diff and any obsolete classes, then rerun `bin/check`. Rebuild stale pages with `perl bin/build-site.pl`.

Templates use the same HTML escaping helper as page metadata, including apostrophe escaping, so generated output remains consistent across Template Toolkit versions.

For verbose test output alone, use `prove -Ilib -It/lib -lv t`.

[GitHub Actions](.github/workflows/check.yml) runs the same `bin/check` command on pushes and pull requests, using Perl 5.36 and 5.44. Each job builds a pinned ImageMagick release and its Perl bindings, then installs the Perl dependencies. [`cpanfile.ci`](cpanfile.ci) pins Schema::Loader and DBD::SQLite across the matrix to keep schema generation consistent; install those constraints before the main dependencies to reproduce the CI toolchain locally:

```sh
cpanm --installdeps --cpanfile cpanfile.ci .
cpanm --with-develop --installdeps .
bin/check
```

Formatting checks are not included; those can follow once a shared formatter configuration is agreed.
