# Clapham Shopfronts

A local history website documenting Clapham’s changing shopfronts. The static site lives in `docs/`, ready for GitHub Pages. Perl generates the shopfront pages and recent-photograph section using Template Toolkit and DBIx::Class before publication. The archive HTML is static; a small JavaScript enhancement opens larger photographs in a modal.

## Preview locally

```sh
http_this --host 127.0.0.1 --port 8000 --autoindex docs
```

Run this from the repository root using App::HTTPThis, then visit `http://localhost:8000`. The `--autoindex` option serves `index.html` for directory URLs, including shopfront pages.

## Design and artwork

The page uses Cormorant Garamond, DM Sans, and Caveat from Google Fonts, with local fallback fonts. Styles are in `docs/styles.css`.

The hero is a responsive collage of eight watercolour interpretations of the original photographs in `pics/`. It uses four columns on larger screens and two on phones. The paper, tape, and small rotations are CSS. Motion respects the visitor’s reduced-motion setting.

Finished paintings are in `docs/images/watercolours/`. Each has a full-size WebP and a smaller version for the page. A reusable, flattened collage is in `docs/images/hero-collage.webp`.

See [the artwork notes](artwork/README.md) for individual image links, source photographs, and the exact imagegen prompts.

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

The commands use Perl 5.36 or later, DBIx::Class, Template Toolkit, Image::ExifTool, and the Perl ImageMagick bindings. ImageMagick needs WebP support. Dependencies are listed in `cpanfile`; install them with your usual Perl environment:

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

## Unit URLs

A unit's public URL uses its postcode and street number: `/shopfronts/sw4-7ts-7/` for 7 Clapham High Street, SW4 7TS. Letter suffixes and number ranges are retained: `sw4-7ts-7a` and `sw4-7ts-7-9`.

The importer generates `units.slug` once when creating a unit; migration assigns it to existing units. It remains stable when a business changes or an address is corrected. Internal identifiers such as `CHS0001-U01` remain unchanged and still select units in manifests and publication configuration.

For units sharing an address, or an address without a usable number or postcode, set an explicit `slug` inside the manifest's `unit` object, for example `"slug": "sw4-7ts-7-u2"`. Slugs accept lowercase letters, digits, and single separating hyphens. Collisions stop the import or migration for an explicit choice rather than silently renumbering units. An import cannot change an existing unit's stored slug.

## Generate the website

```sh
perl bin/build-site.pl
```

The generator reads SQLite in read-only mode and writes one page per published unit under `docs/shopfronts/<slug>/index.html`. The first is [7 Clapham High Street, from Pure Vintage to Tony Voyage](docs/shopfronts/sw4-7ts-7/index.html). Each page leads with its latest photograph and identified business, address, category, and dated state. Earlier photographs retain their original identities and dates below it, and the timeline includes each dated observation. The stored address URL remains stable if the business name changes.

Publication choices live in `data/site.json`. Its `shopfronts` entries select each `unit_code`. Photo identities and categories come from their linked observation businesses, so the latest page heading can change without relabelling earlier photos. Optional `reported_events` supply public historical annotations and are always labelled unconfirmed. Use `sourced_events` for events checked against a published source, such as Dentons' closure announcement; these have a “Published source” label and source link. Both event lists require a date, title and description. Sourced events also require a source URL and label; these are optional for owner reports. Event dates can be a year (`2020`), month (`2025-12`) or day (`2026-05-01`), preserving the precision of the evidence. Photograph and occupancy dates remain complete ISO dates. `confirmed_closures` identifies a specific business and observation date; each must match a vacant photo observation. The Pure Vintage opening and closure notes therefore remain attached to its history, not the later salon. Internal database notes are not published or parsed as page copy.

The generator also updates the homepage's **Recent photographs** section, showing up to three photographs from published units, ordered by photograph date rather than import date. Each links to its own `#photo-<id>` anchor on the shopfront page. It preserves the rest of the manually maintained homepage. Keep the `BEGIN GENERATED RECENT PHOTOGRAPHS` and `END GENERATED RECENT PHOTOGRAPHS` comments in place, and rebuild rather than editing the HTML between them.

The complete [All photos gallery](docs/photos/index.html) is generated at `/photos/`, linked from the top navigation and the homepage's recent section. It includes every photograph from published units, newest first, including earlier photographs of the same unit. A shared image appears once, with a separate dated-photo link for each of its units. Unit pages link back to this gallery. The gallery works without JavaScript and uses the same configurable image base as other archive photographs.

Page content is maintained in `templates/shopfront.tt`, the reusable `templates/photograph.tt`, `templates/recent-photographs.tt`, and `templates/all-photos.tt`. Generated pages reuse the homepage's head, navigation, and footer, including its fonts, analytics, and project credit. After changing those shared homepage elements, rebuild to propagate them. Styling stays in `docs/styles.css`.

On a shopfront page, clicking any photograph or its “View larger” link opens that photograph in a native dialog carousel. Previous/next buttons and the left/right arrow keys browse all photographs of that unit, newest first, wrapping at either end. Each slide shows its business name, date, photographer credit where available, and position in the set. Navigation buttons are hidden for a single photograph. Close it with ×, Escape, or the backdrop; keyboard focus returns to the original link, even after browsing. Without JavaScript, these links still open the image directly. The enhancement is in `docs/photo-modal.js`.

Check whether generated output needs rebuilding without writing files:

```sh
perl bin/build-site.pl --check
```

To move the archive photographs to the intended AWS host later, change `image_base` in `data/site.json` and rebuild. The `--image-base` option can override that setting for a particular build. The generator currently reads the local published image copies to check their existence and dimensions, even when emitting external URLs; retain those local copies while building. No AWS resources are provisioned by this command.

## Checks

Run the import and page-generation checks with:

```sh
prove -Ilib -It/lib -lv t
```
