# Photograph intake

Keep original photographs in this directory, organised by ingestion status:

| Directory | Contents |
| --- | --- |
| `incoming/` | Originals waiting to be ingested. Add new photographs here. |
| `processed/` | Originals that have been successfully ingested. Retain them as the source archive. |

Ingestion means that the photograph has a saved record in the database’s `photos` table and its optimised website copies have been generated under `docs/images/photos/`. Once both steps succeed, move the original from `incoming/` to `processed/`, preserving its filename and contents. If either step fails, leave the original in `incoming/` so it is clear that work remains.

The folders track the state of the originals; they are not the public image paths. `photos.filename` should refer to the published image copy relative to the image root, as described in [Photograph storage](../README.md#photograph-storage). Moving an original between these folders should not change that database value.

Two photographs of 7 Clapham High Street are now in `processed/`: `PXL_20260403_065904338.jpg` (Pure Vintage, vacant in April) and `PXL_20261029_130247804.jpg` (Tony Voyage Hair Salon, occupied in October). The seven remaining original photographs are still in `incoming/`. Using a photograph as a reference for the watercolour artwork does not ingest it into the photographic archive.

## Pilot importer

The [Perl importer](../bin/ingest-photo.pl) takes reviewed metadata from `data/photos/`. It checks the original's SHA-256 hash and EXIF date with Image::ExifTool, enables SQLite foreign-key enforcement through DBIx::Class, creates or reuses the site and unit in a transaction, records the observation and photo, and generates two WebP copies with Image::Magick. Their longest edges are at most 1600 pixels and 640 pixels respectively; smaller images are not enlarged. The original is retained without resizing or changing its metadata.

The large copy uses the original filename stem with a `.webp` extension; the smaller copy adds `-small.webp`. Both are stored under `docs/images/photos/YYYY/MM/`, using the EXIF photograph date. Only the large copy's image-root-relative path is stored in `photos.filename`.

A new unit receives a stored address slug, such as `sw4-7ts-7`, for its public page. For shared or unusual addresses, choose an explicit manifest `unit.slug`; collisions stop for review. Later photos retain the existing unit's slug. See [Unit URLs](../README.md#unit-urls).

If generation fails, the importer rolls back the new database records, removes any copies it created, and leaves the original in `incoming/`. If it is interrupted after the database commit but before archiving the original, rerunning the manifest completes the move without duplicating records. Existing published files are not overwritten. Filesystem moves and the database commit are separate operations, so recovery relies on this rerun behaviour.

For a later photo of the same unit, use the same site and unit codes. An unchanged state adds evidence to the existing occupancy. A different status or occupied business starts a new occupancy on the observation date, ending the previous period on its last known observation date. A gap between those dates remains unknown. The importer stops for manual review on backdated observations, conflicting same-day states, mismatched addresses, retired units, or inconsistent existing timelines. If a later image write fails, updates to the previous occupancy are rolled back too. See [Import a photograph](../README.md#import-a-photograph) for commands.

The `.gitkeep` files keep both folders present in Git when empty. Windows `:Zone.Identifier` sidecars are ignored by Git.
