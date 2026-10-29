-- Replacement unit table for schema version 2.
CREATE TABLE units_slug_v2 (
  id                  INTEGER PRIMARY KEY,
  site_id             INTEGER NOT NULL REFERENCES sites(id) ON DELETE RESTRICT,
  unit_code           TEXT NOT NULL UNIQUE,   -- e.g. CHS0001-U01
  slug                TEXT NOT NULL UNIQUE,   -- e.g. sw4-7ts-7; assigned once
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
