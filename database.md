# The Clapham Shopfronts database

The database records how Clapham’s shopfronts change over time: the physical premises, the businesses using them, and the observations and photographs that provide evidence of those changes.

The files are:

| File | Purpose |
| --- | --- |
| [`db/claphamshopfront.db`](db/claphamshopfront.db) | The SQLite database. Note the singular `shopfront` in its filename. |
| [`db/claphamshopfronts.ddl`](db/claphamshopfronts.ddl) | SQL defining the tables, indexes, views, and triggers. |
| [`db.png`](db.png) | The original diagram of the tables and their columns. |

On inspection on 27 October 2026, the database schema matched the DDL: **11 tables, 4 views, 4 triggers, and 19 explicitly defined indexes**, plus SQLite’s automatic indexes for unique constraints and composite primary keys. All tables were empty. SQLite’s integrity check returned `ok`, and its foreign-key check found no violations. The examples below illustrate intended use rather than existing records.

## The central idea: location, unit, and occupant

These are three separate things:

| Concept | Meaning | Example |
| --- | --- | --- |
| **Site** | An enduring physical location on the street. | A location recorded as “52 Clapham High Street”. |
| **Unit** | A physical retail configuration at that site, with a period of validity. | One shop frontage, later divided into two smaller units. |
| **Occupancy** | The state of a unit during a particular period, optionally associated with a business. | A café occupies the unit; later it is vacant; then another business moves in. |

A change of business normally creates a new occupancy for the same unit. A material physical reconfiguration creates new units, with relationships linking them to their predecessors. The site remains the geographical anchor.

A business has its own identity so it can be associated with multiple units, either simultaneously or at different times. A vacant period is an occupancy record too: it is part of the unit’s history.

## Relationships

This diagram shows the foreign-key relationships and selected identifying columns. A circle means the relationship is optional; the forked end means there can be many related records.

```mermaid
erDiagram
    sites ||--o{ units : contains
    units ||--o{ occupancies : "has occupancy history"
    business_types |o--o{ businesses : classifies
    businesses |o--o{ occupancies : "occupies through"
    units ||--o{ observations : "is observed"
    units |o--o{ photos : "is pictured"
    observations |o--o{ photos : "is documented by"
    units ||--o{ unit_relationships : "predecessor: from_unit_id"
    units ||--o{ unit_relationships : "successor: to_unit_id"
    units ||--o{ unit_tags : "has tag links"
    tags ||--o{ unit_tags : "labels units"
    businesses ||--o{ business_tags : "has tag links"
    tags ||--o{ business_tags : "labels businesses"

    sites {
        INTEGER id PK
        TEXT site_code UK
        TEXT street_address
    }
    units {
        INTEGER id PK
        INTEGER site_id FK
        TEXT unit_code UK
        TEXT valid_from
        TEXT valid_to
    }
    unit_relationships {
        INTEGER id PK
        INTEGER from_unit_id FK
        INTEGER to_unit_id FK
        TEXT relationship_type
        TEXT effective_date
    }
    business_types {
        INTEGER id PK
        TEXT name UK
    }
    businesses {
        INTEGER id PK
        INTEGER business_type_id FK
        TEXT name
        TEXT normalised_name UK
    }
    occupancies {
        INTEGER id PK
        INTEGER unit_id FK
        INTEGER business_id FK
        TEXT occupancy_status
        TEXT valid_from
        TEXT valid_to
    }
    observations {
        INTEGER id PK
        INTEGER unit_id FK
        TEXT observed_on
        TEXT observed_status
    }
    photos {
        INTEGER id PK
        INTEGER unit_id FK
        INTEGER observation_id FK
        TEXT taken_on
        TEXT source_type
    }
    tags {
        INTEGER id PK
        TEXT name UK
    }
    unit_tags {
        INTEGER unit_id PK, FK
        INTEGER tag_id PK, FK
    }
    business_tags {
        INTEGER business_id PK, FK
        INTEGER tag_id PK, FK
    }
```

Every table except the two tag-link tables has an integer `id` primary key. The tag-link tables use the pair of foreign keys as their primary key. Human-facing codes such as `CHS0001` are stored separately from numeric IDs; their uniqueness is enforced, but their format is a convention.

## What each table represents

### `sites`: enduring street locations

One row identifies a location independently of which business is there or how its frontage is arranged.

- `site_code`: required, unique project identifier, for example `CHS0001`.
- `street_address`: required address; addresses are indexed but are not unique.
- `postcode`, `latitude`, `longitude`: optional geographical information.
- `notes`: additional context.

One site can have multiple units, including successive historical configurations and units that exist alongside one another.

### `units`: physical shop configurations

Each unit belongs to exactly one site through `site_id`. It has a required, unique `unit_code`, such as `CHS0001-U01`, and an optional human-readable `label`.

`valid_from` and `valid_to` describe when that configuration exists. A null `valid_to` means it remains current. `frontage_notes` describe its physical features or changes.

Two controlled fields provide further context:

| Field | Allowed values | Default |
| --- | --- | --- |
| `lifecycle_status` | `active`, `retired`, `superseded` | `active` |
| `source_confidence` | `observed`, `inferred`, `estimated` | `observed` |

When a frontage is materially split, merged, or reconfigured, create new unit records and retain the old ones for history. A new occupant alone does not require a new unit.

### `unit_relationships`: splits, mergers, and other changes

Each row connects a predecessor (`from_unit_id`) to a successor (`to_unit_id`), with an `effective_date` and optional `notes`.

| `relationship_type` | Meaning |
| --- | --- |
| `split_into` | The predecessor becomes one of several successor units. Use one relationship row for each successor. |
| `merged_into` | The predecessor becomes part of a combined successor. Use one relationship row for each predecessor. |
| `reconfigured_to` | A physical configuration is replaced by another. |
| `renumbered_to` | A successor unit record represents a renumbering. |

For example, splitting unit A into B and C needs two rows: A → B and A → C. Merging B and C into D likewise needs B → D and C → D.

The database prevents a unit from linking directly to itself. It does not enforce matching dates, same-site relationships, or the absence of longer cycles; those need to be checked when recording changes.

### `business_types`: a shared classification list

A controlled vocabulary such as “Café”, “Estate Agent”, or “Restaurant”. Each row has a unique required `name`, optional `notes`, and a creation timestamp. No initial categories have been populated.

This lets queries group businesses consistently instead of relying on free-text descriptions. Each business can have one type, or none.

### `businesses`: businesses and brands

One row represents a business or brand independently of the premises it occupies.

- `name`: required readable name; it is indexed but not unique.
- `normalised_name`: required unique canonical name, intended to help avoid duplicates. The application must supply and normalise it; SQLite does not generate or lowercase it.
- `business_type_id`: optional link to `business_types`.
- `is_chain`: `0` or `1`, defaulting to `0`.
- `website`, `notes`: optional supporting information.

A business’s occupancies record where and when it trades. The schema does not have a separate branch table.

### `occupancies`: the history of each unit’s use

Each row records a unit’s state over a period. `unit_id`, `occupancy_status`, and `valid_from` are required. `valid_to` is null for an ongoing period.

| `occupancy_status` | Meaning |
| --- | --- |
| `occupied` | In use by a business. |
| `vacant` | Empty premises. |
| `opening_soon` | A forthcoming opening has been identified. |
| `under_refurbishment` | Refurbishment is taking place. |
| `unknown` | The state cannot yet be established. |

`business_id` is optional, allowing periods such as vacancy or refurbishment to be recorded without inventing a business. There is no constraint requiring a business for `occupied`, or forbidding one for other statuses.

`name_as_displayed` preserves the wording on the shopfront for that period, separately from the canonical business name. `notes` hold supporting context.

When the occupant or state changes, end the previous period and insert a new one. Replacing the old row’s details would lose the history.

### `observations`: what was seen on a particular date

Each observation belongs to a unit and records an `observed_on` date, an `observed_status`, and optionally the `observer`, `observed_business_name`, and `notes`.

`observed_status` uses the same five values as occupancy status. `confidence` must be `high`, `medium`, or `low`, and defaults to `high`.

Observations preserve the evidence separately from the occupancy timeline inferred from it. For example, seeing an empty shop on a particular day establishes its observed state that day; it does not necessarily establish the date the previous business closed.

There is no direct foreign key from an observation to an occupancy, and inserting an observation does not automatically create or update an occupancy.

### `photos`: photographic evidence and its source

The database stores photo metadata and references, rather than image bytes.

- `taken_on`: required date of the photograph, distinct from the date the record was created.
- `source_type`: required; one of `own_photo`, `street_view`, `submitted`, or `archive`.
- `filename`: optional reference to a local image file.
- `source_url`: optional reference to an external source.
- `attribution`, `caption`, `notes`: optional descriptive and source information.
- `unit_id`, `observation_id`: independent, optional links to the subject unit and an observation the photo supports.

A photo can be associated with a unit, an observation, both, or neither while it awaits identification. If both links are supplied, the database does not check that the photo’s unit matches the observation’s unit. It also does not require either a filename or a source URL, or check whether a file or URL exists.

Each photo can directly reference at most one unit and one observation. There is no linking table for a photograph covering several units. The image files in `pics/` are not automatically registered in this table.

### `tags`, `unit_tags`, and `business_tags`: flexible labels

`tags` is a list of unique tag names for ad hoc classification beyond the business-type list.

`unit_tags` connects units to tags; `business_tags` connects businesses to tags. These allow each unit or business to have multiple tags, and each tag to be reused. Their composite primary keys prevent the same tag being attached twice to the same record.

Although the DDL’s comments mention tagging photographs as a possible use, the implemented schema has **no `photo_tags` table**.

## Dates and the meaning of “current”

Historical dates are stored as `TEXT`, intended to use ISO format `YYYY-MM-DD`. For units and occupancies, `valid_from` is required and `valid_to` may be null. A check constraint prevents a non-null `valid_to` from sorting before `valid_from`.

The schema does not validate date formatting, define whether an end date is inclusive or exclusive, or prevent overlapping periods. Data-entry code should use consistent date and boundary conventions, keep occupancy periods within their unit’s lifetime, and avoid multiple ongoing occupancies for one unit.

The four views provide convenient joined queries:

| View | What it returns |
| --- | --- |
| `current_units` | Units with `valid_to IS NULL`, joined to their site’s address and coordinates. |
| `current_occupancies` | Occupancies where both the occupancy and its unit have `valid_to IS NULL`, with address, business, and business-type information. Optional business details may be null. |
| `current_occupied_units` | Rows from `current_occupancies` whose status is `occupied`. |
| `current_non_occupied_units` | Rows from `current_occupancies` whose status is `vacant`, `opening_soon`, `under_refurbishment`, or `unknown`. |

These views define “current” using null end dates. They do not compare `valid_from` with today or check `lifecycle_status`. Future-dated rows with no end date can therefore appear, and a unit without an ongoing occupancy appears only in `current_units`. A missing occupancy is not automatically treated as a vacancy.

## Keys, deletion, and timestamps

Foreign-key enforcement must be enabled **for each SQLite connection**, before starting a transaction:

```sql
PRAGMA foreign_keys = ON;
```

The DDL contains this statement as a comment, so running the file does not itself enable enforcement. It was disabled on the read-only connection used for inspection; that is a connection setting, not a permanent property of the database file.

With enforcement enabled, deletion behaves as follows:

| Action | Result |
| --- | --- |
| Delete a site that still has units | Blocked by `ON DELETE RESTRICT`. |
| Delete a unit referenced by occupancies, observations, or either end of a unit relationship | Blocked by `ON DELETE RESTRICT`. |
| Delete a business type | Its businesses remain, with `business_type_id` set to null. |
| Delete a business | Its occupancies remain, with `business_id` set to null; its tag links are deleted. |
| Delete an otherwise deletable unit | Photo references to it become null; its unit-tag links are deleted. |
| Delete an observation | Its photos remain, with `observation_id` set to null. |
| Delete a tag | Its unit-tag and business-tag links are deleted. |

Most main tables have `created_at`, defaulting to SQLite’s `CURRENT_TIMESTAMP` in UTC. `sites`, `units`, `businesses`, and `occupancies` also have `updated_at`, refreshed by four `AFTER UPDATE` triggers. These timestamps describe database record maintenance, rather than the historical dates being documented. The other tables have no automatic update timestamp; `tags` and the two tag-link tables have no timestamps at all.

The 19 explicit indexes support address and business-name lookups, common foreign-key joins, status filtering, and date searches. Unique constraints additionally protect site and unit codes, normalised business names, business-type names, tag names, and tag associations.

## A typical recording workflow

1. Find or create the site for the street location.
2. Find or create the unit representing its physical configuration, recording when that configuration is known to exist.
3. Record a dated observation and any supporting photos.
4. Find or create the business and, if known, its business type.
5. Use the evidence to create or revise occupancy periods, retaining earlier periods and recording uncertainty in notes.
6. If the frontage is physically reconfigured, end the old unit and relevant occupancy periods, create the successor units, and connect them through `unit_relationships`. Make these related changes in a transaction so they are saved together.

For example, a café closing and an estate agent opening behind the same frontage produces successive occupancies for one unit. Dividing that frontage into two shops produces two new units, each with its own occupancy history, linked back to the old unit by two `split_into` relationships.

## Example queries

Show the recorded current occupants and states:

```sql
SELECT unit_code, street_address, occupancy_status,
       business_name, business_type, name_as_displayed
FROM current_occupancies
ORDER BY street_address, unit_code;
```

Show a unit’s full occupancy history, including periods with no named business:

```sql
SELECT u.unit_code, o.valid_from, o.valid_to,
       o.occupancy_status, b.name AS business_name,
       o.name_as_displayed, o.notes
FROM occupancies AS o
JOIN units AS u ON u.id = o.unit_id
LEFT JOIN businesses AS b ON b.id = o.business_id
WHERE u.unit_code = 'CHS0001-U01'
ORDER BY o.valid_from, o.id;
```

Follow the recorded physical changes from a predecessor unit:

```sql
SELECT predecessor.unit_code AS from_unit,
       successor.unit_code AS to_unit,
       r.relationship_type, r.effective_date, r.notes
FROM unit_relationships AS r
JOIN units AS predecessor ON predecessor.id = r.from_unit_id
JOIN units AS successor ON successor.id = r.to_unit_id
WHERE predecessor.unit_code = 'CHS0001-U01'
ORDER BY r.effective_date, r.id;
```

Find photographs associated with a unit either directly or through an observation:

```sql
SELECT p.id, p.taken_on, p.source_type,
       p.filename, p.source_url, p.attribution, p.caption
FROM photos AS p
LEFT JOIN observations AS o ON o.id = p.observation_id
WHERE p.unit_id = :unit_id OR o.unit_id = :unit_id
ORDER BY p.taken_on, p.id;
```

Here `:unit_id` is a parameter to bind to the numeric unit ID. All four examples currently return no rows because the database has not yet been populated.
