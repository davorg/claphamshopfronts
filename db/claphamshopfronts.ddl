PRAGMA foreign_keys = ON;

----------------------------------------------------------------------
-- SITES
-- A site is the enduring physical location on the street.
-- Example: "52 Clapham High Street"
-- If later a frontage is split/merged, the site can remain the anchor.
----------------------------------------------------------------------

CREATE TABLE sites (
  id              INTEGER PRIMARY KEY,
  site_code       TEXT NOT NULL UNIQUE,     -- e.g. CHS0001
  street_address  TEXT NOT NULL,
  postcode        TEXT,
  latitude        REAL,
  longitude       REAL,
  notes           TEXT,
  created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sites_address ON sites(street_address);

----------------------------------------------------------------------
-- UNITS
-- A unit is a time-bounded physical retail configuration at a site.
-- When a frontage is materially reconfigured, create a NEW unit row.
----------------------------------------------------------------------

CREATE TABLE units (
  id                  INTEGER PRIMARY KEY,
  site_id             INTEGER NOT NULL REFERENCES sites(id) ON DELETE RESTRICT,
  unit_code           TEXT NOT NULL UNIQUE,   -- e.g. CHS0001-U01
  label               TEXT,                   -- human-readable label if useful
  valid_from          TEXT NOT NULL,          -- ISO date: YYYY-MM-DD
  valid_to            TEXT,                   -- NULL = still current
  lifecycle_status    TEXT NOT NULL DEFAULT 'active',
  frontage_notes      TEXT,
  source_confidence   TEXT NOT NULL DEFAULT 'observed',
  created_at          TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (valid_to IS NULL OR valid_to >= valid_from),
  CHECK (lifecycle_status IN ('active', 'retired', 'superseded')),
  CHECK (source_confidence IN ('observed', 'inferred', 'estimated'))
);

CREATE INDEX idx_units_site_id ON units(site_id);
CREATE INDEX idx_units_valid_from ON units(valid_from);
CREATE INDEX idx_units_valid_to ON units(valid_to);

----------------------------------------------------------------------
-- UNIT RELATIONSHIPS
-- Tracks lineage between units when they split, merge, or are otherwise
-- reconfigured. The "from" unit is the predecessor, the "to" unit is
-- the successor.
----------------------------------------------------------------------

CREATE TABLE unit_relationships (
  id                  INTEGER PRIMARY KEY,
  from_unit_id        INTEGER NOT NULL REFERENCES units(id) ON DELETE RESTRICT,
  to_unit_id          INTEGER NOT NULL REFERENCES units(id) ON DELETE RESTRICT,
  relationship_type   TEXT NOT NULL,
  effective_date      TEXT NOT NULL,
  notes               TEXT,
  created_at          TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (from_unit_id <> to_unit_id),
  CHECK (relationship_type IN (
    'split_into',
    'merged_into',
    'reconfigured_to',
    'renumbered_to'
  ))
);

CREATE INDEX idx_unit_rel_from ON unit_relationships(from_unit_id);
CREATE INDEX idx_unit_rel_to   ON unit_relationships(to_unit_id);
CREATE INDEX idx_unit_rel_date ON unit_relationships(effective_date);

----------------------------------------------------------------------
-- BUSINESS TYPES
-- Controlled vocabulary for analysis.
----------------------------------------------------------------------

CREATE TABLE business_types (
  id              INTEGER PRIMARY KEY,
  name            TEXT NOT NULL UNIQUE,      -- e.g. Cafe, Estate Agent
  notes           TEXT,
  created_at      TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

----------------------------------------------------------------------
-- BUSINESSES
-- A business or brand that may occupy one or more units over time.
----------------------------------------------------------------------

CREATE TABLE businesses (
  id                  INTEGER PRIMARY KEY,
  name                TEXT NOT NULL,
  normalised_name     TEXT NOT NULL UNIQUE,  -- e.g. lowercased canonical form
  business_type_id    INTEGER REFERENCES business_types(id) ON DELETE SET NULL,
  is_chain            INTEGER NOT NULL DEFAULT 0,
  website             TEXT,
  notes               TEXT,
  created_at          TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (is_chain IN (0, 1))
);

CREATE INDEX idx_businesses_type ON businesses(business_type_id);
CREATE INDEX idx_businesses_name ON businesses(name);

----------------------------------------------------------------------
-- OCCUPANCIES
-- The state of a unit over a period.
-- This includes not only occupied states but also vacant/opening soon/etc.
--
-- business_id may be NULL for:
--   vacant
--   under_refurbishment
--   unknown
----------------------------------------------------------------------

CREATE TABLE occupancies (
  id                  INTEGER PRIMARY KEY,
  unit_id             INTEGER NOT NULL REFERENCES units(id) ON DELETE RESTRICT,
  business_id         INTEGER REFERENCES businesses(id) ON DELETE SET NULL,
  occupancy_status    TEXT NOT NULL,
  valid_from          TEXT NOT NULL,
  valid_to            TEXT,
  name_as_displayed   TEXT,
  notes               TEXT,
  created_at          TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (valid_to IS NULL OR valid_to >= valid_from),
  CHECK (occupancy_status IN (
    'occupied',
    'vacant',
    'opening_soon',
    'under_refurbishment',
    'unknown'
  ))
);

CREATE INDEX idx_occupancies_unit_id ON occupancies(unit_id);
CREATE INDEX idx_occupancies_business_id ON occupancies(business_id);
CREATE INDEX idx_occupancies_status ON occupancies(occupancy_status);
CREATE INDEX idx_occupancies_valid_from ON occupancies(valid_from);
CREATE INDEX idx_occupancies_valid_to ON occupancies(valid_to);

----------------------------------------------------------------------
-- OBSERVATIONS
-- Raw field observations. Optional, but useful.
-- Lets you distinguish "what I saw" from "what I later concluded".
----------------------------------------------------------------------

CREATE TABLE observations (
  id                    INTEGER PRIMARY KEY,
  unit_id               INTEGER NOT NULL REFERENCES units(id) ON DELETE RESTRICT,
  observed_on           TEXT NOT NULL,
  observer              TEXT,
  observed_status       TEXT NOT NULL,
  observed_business_name TEXT,
  confidence            TEXT NOT NULL DEFAULT 'high',
  notes                 TEXT,
  created_at            TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (observed_status IN (
    'occupied',
    'vacant',
    'opening_soon',
    'under_refurbishment',
    'unknown'
  )),
  CHECK (confidence IN ('high', 'medium', 'low'))
);

CREATE INDEX idx_observations_unit_id ON observations(unit_id);
CREATE INDEX idx_observations_date ON observations(observed_on);

----------------------------------------------------------------------
-- PHOTOS
-- Supports your own photos, Street View, submitted images, archives, etc.
----------------------------------------------------------------------

CREATE TABLE photos (
  id                  INTEGER PRIMARY KEY,
  unit_id             INTEGER REFERENCES units(id) ON DELETE SET NULL,
  observation_id      INTEGER REFERENCES observations(id) ON DELETE SET NULL,
  taken_on            TEXT NOT NULL,
  source_type         TEXT NOT NULL,
  filename            TEXT,
  source_url          TEXT,
  attribution         TEXT,
  caption             TEXT,
  notes               TEXT,
  created_at          TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (source_type IN ('own_photo', 'street_view', 'submitted', 'archive'))
);

CREATE INDEX idx_photos_unit_id ON photos(unit_id);
CREATE INDEX idx_photos_observation_id ON photos(observation_id);
CREATE INDEX idx_photos_taken_on ON photos(taken_on);

----------------------------------------------------------------------
-- TAGS (OPTIONAL BUT USEFUL)
-- Lets you mark units/photos/businesses with ad hoc tags later.
----------------------------------------------------------------------

CREATE TABLE tags (
  id              INTEGER PRIMARY KEY,
  name            TEXT NOT NULL UNIQUE
);

CREATE TABLE unit_tags (
  unit_id         INTEGER NOT NULL REFERENCES units(id) ON DELETE CASCADE,
  tag_id          INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (unit_id, tag_id)
);

CREATE TABLE business_tags (
  business_id     INTEGER NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  tag_id          INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (business_id, tag_id)
);

----------------------------------------------------------------------
-- USEFUL VIEWS
----------------------------------------------------------------------

-- Current units (physical configurations still current)
CREATE VIEW current_units AS
SELECT
  u.id,
  u.unit_code,
  u.site_id,
  s.site_code,
  s.street_address,
  s.postcode,
  s.latitude,
  s.longitude,
  u.label,
  u.valid_from,
  u.frontage_notes
FROM units u
JOIN sites s ON s.id = u.site_id
WHERE u.valid_to IS NULL;

-- Current occupancies
CREATE VIEW current_occupancies AS
SELECT
  o.id AS occupancy_id,
  u.id AS unit_id,
  u.unit_code,
  s.street_address,
  o.occupancy_status,
  o.valid_from,
  b.id AS business_id,
  b.name AS business_name,
  bt.name AS business_type,
  b.is_chain,
  o.name_as_displayed
FROM occupancies o
JOIN units u ON u.id = o.unit_id
JOIN sites s ON s.id = u.site_id
LEFT JOIN businesses b ON b.id = o.business_id
LEFT JOIN business_types bt ON bt.id = b.business_type_id
WHERE o.valid_to IS NULL
  AND u.valid_to IS NULL;

-- Current vacant/refurb units
CREATE VIEW current_non_occupied_units AS
SELECT *
FROM current_occupancies
WHERE occupancy_status IN ('vacant', 'opening_soon', 'under_refurbishment', 'unknown');

-- Current occupied units only
CREATE VIEW current_occupied_units AS
SELECT *
FROM current_occupancies
WHERE occupancy_status = 'occupied';

----------------------------------------------------------------------
-- TRIGGERS TO KEEP updated_at FRESH
----------------------------------------------------------------------

CREATE TRIGGER trg_sites_updated_at
AFTER UPDATE ON sites
FOR EACH ROW
BEGIN
  UPDATE sites
     SET updated_at = CURRENT_TIMESTAMP
   WHERE id = NEW.id;
END;

CREATE TRIGGER trg_units_updated_at
AFTER UPDATE ON units
FOR EACH ROW
BEGIN
  UPDATE units
     SET updated_at = CURRENT_TIMESTAMP
   WHERE id = NEW.id;
END;

CREATE TRIGGER trg_businesses_updated_at
AFTER UPDATE ON businesses
FOR EACH ROW
BEGIN
  UPDATE businesses
     SET updated_at = CURRENT_TIMESTAMP
   WHERE id = NEW.id;
END;

CREATE TRIGGER trg_occupancies_updated_at
AFTER UPDATE ON occupancies
FOR EACH ROW
BEGIN
  UPDATE occupancies
     SET updated_at = CURRENT_TIMESTAMP
   WHERE id = NEW.id;
END;

