# Bunkalunk Specification

## Status

Accepted

## Overview

Bunkalunk is a local-first ride-data analysis tool. It accepts
user-supplied local activity files, decodes them into a stable
intermediate format, and computes segment efforts for a personal
leaderboard.

## Design Principles

- Data ownership: users must be able to analyze their own ride data
  outside vendor platforms and closed ecosystems.
- Local-first: all state lives under a single configurable root
  directory, defaulting to `~/.bunk/`, overridable via `BUNK_HOME`.
- Scriptability: stable command-line workflows over local files.
- Minimal abstraction: one canonical decoded schema, a small number
  of storage roles, no plugin frameworks.
- Format-based decoding: decoders dispatch by file format, not
  acquisition source.
- Narrow scope: sync, archival, backup, and vendor integration are
  out of scope.
- Discover don't prescribe: design decisions not on the critical path
  to a working leaderboard are deferred to implementation.

## Scope

In scope:

- accepting explicit local file paths
- decoding supported formats into a stable HDF5 artifact
- recording a source-file index in SQLite
- computing segment efforts
- displaying a segment leaderboard

Out of scope:

- syncing from devices or vendor platforms
- raw file archival or backup
- semantic deduplication
- recursive directory ingestion
- vendor API integrations

## Technology Stack

- Python 3.9+: decoding, SQLite access, CLI
- Julia: segment matching and analysis
- SQLite: operational index and derived results
- HDF5: decoded activity cache
- `fitdecode`: FIT parsing
- `h5py`: HDF5 access
- `DataFrames`, `ArchGDAL`, `Shapefile`: Julia analysis support

## Architecture

Two storage roles:

- **SQLite** (`$BUNK_HOME/db.sqlite3`): source-file index, decode
  metadata, activity metadata, segment definitions and efforts.
- **HDF5 activity store** (`$BUNK_HOME/activity_store/`):
  content-addressable decoded activity artifacts, sharded by the
  first two characters of the source file's SHA-256 fingerprint.
  e.g. `activity_store/ab/<full-fingerprint>.h5`

Python owns SQLite schema definition, migrations, and
ingestion-oriented writes. Julia reads SQLite directly for analysis
queries and writes to a narrow set of analysis-owned tables.

## Simplifying Assumptions

- One source file decodes to exactly one activity. 
- `.fit` is the only supported format initially.
- Explicit file paths only; no recursive directory ingestion.
- Decode on add is the default; deferred decode is not supported.

## Input Contract

- Input is by explicit file path only.
- Only `.fit` files are accepted initially.
- Unsupported files are rejected up front.

## Storage Model

### SQLite

Minimum tables:

- `source_files` — Python-owned, Julia-readable
  - `source_path`
  - `content_fingerprint` (FK → `activities.source_fingerprint`)
  - `decode_state`
  - `last_decode_error` (nullable)
  - `last_decode_error_at` (nullable)

- `activities` — Python-owned, Julia-readable
  - `activity_id`
  - `source_fingerprint` (CAS address; unique)
  - `start_time`
  - `ride_tag` (nullable)

- `segments` — analysis-owned
  - `segment_id`
  - `name`
  - `version`
  - `definition_path`

- `segment_efforts` — analysis-owned
  - `effort_id`
  - `activity_id`
  - `segment_id`
  - `elapsed_time_s`
  - `start_offset_s`
  - `end_offset_s`
  - `matched_at`
  - `matcher_version`

`activities.source_fingerprint` is the SHA-256 fingerprint of the source file
bytes and serves as the CAS address for the decoded HDF5 artifact.

`activities.start_time` must be indexed for efficient timestamp-based
lookup. `activities.source_fingerprint` must have a unique constraint.
Exact-content duplicates in `source_files` naturally share a single `activities`
row via their common `source_fingerprint`. In other words, multiple
`source_files` rows may share the same `content_fingerprint`; the schema is
intentionally designed to allow this.

### HDF5

Each decoded activity is stored as a single HDF5 file named by the
source file's SHA-256 fingerprint, sharded by the first two
characters of that fingerprint.


Each HDF5 file carries a `schema_version` integer attribute. If the
version does not match the current expected version, the cache entry
is considered stale. Rebuilding stale entries is the user's
responsibility via `bunk decode`.
- version format: YYYYMMDD as an integer

The canonical schema includes:

- timestamps (required)
- latitude / longitude (required)
- elevation (nullable)
- distance (nullable)
- heart rate (nullable)
- speed (nullable)

Failed or interrupted decodes must not leave a completed artifact at
the final path.

## Decode Contract

- Dispatch by file extension.
- Parse source file, extract core fields into the canonical HDF5
  schema.
- Write decoded artifact to HDF5 store.
- Update decode metadata in SQLite.
- One decoded activity per source file (MVP assumption).

## Ingestion Workflow

On `bunk add <path>`:

1. Verify supported file extension.
2. Compute SHA-256 fingerprint.
3. Register or update `source_files` row in SQLite.
4. Decode file and write HDF5 artifact.
5. Insert or update `activities` row in SQLite.
6. Update decode metadata in SQLite.

## CLI

### `bunk`

- `add <path>...` — register and decode files immediately
- `decode [path]...` — manually re-decode previously added files; use this to
  replace stale, missing, or corrupt cache entries (e.g. after a schema bump, or
  a write failure).
  
`bunk decode` is idempotent and safe to run at any time.

### `lunk`

- `segment match <segment-name>` — compute and persist segment
  efforts for activities not yet matched against this segment
- `segment show <segment-name>` — display leaderboard from cached
  results
- `ride show <activity-id|ride-tag>` — display activity summary

## Segment Definitions

Segment definitions are OSM XML files (`resources/segments/*.osm`). Additional
formats may be supported later.
- https://wiki.openstreetmap.org/wiki/OSM_XML

## Directory Layout

```
src/
  julia/         — segment matching and analysis
  python/
    bunkalunk/
      db.py      — SQLite schema, migrations, ingestion DB layer
      bunk.py    — cache manager and ingestion logic
    formats/
      fit.py     — FIT decoder
resources/
  segments/      — segment definition files
docs/
  spec.md
  notes.org
  tasks.org
```

State lives under `~/.bunk/` by default, or `$BUNK_HOME` if set.
The project directory contains no runtime state.

## Deferred

- Additional format decoders (`.tcx`, `.gpx`): the initial data
  corpus contains many files in these formats. `.fit` is the MVP
  target, but `.tcx` and `.gpx` support is an early priority, not
  a distant future concern.
- Recursive directory ingestion
- Extension field capture and catalog
- Automatic cache rebuild on schema version change
- WAL mode
- Richer status reporting
- Semantic deduplication
- App framework model
- Vendor integrations
- Multi-session source files

## Decisions Recorded

- `decode_fingerprint` is omitted from the MVP. `schema_version` on the HDF5
  artifact is sufficient for cache invalidation. If decoder logic changes, bump
  `schema_version` manually.
- Python owns SQLite schema, migrations, and ingestion logic.
- Julia reads SQLite directly for analysis; writes only to
  analysis-owned tables.
- The MVP assumes one activity per source file; the schema supports
  relaxing this later.
- All state is rooted under `BUNK_HOME`.
- HDF5 cache files carry a `schema_version` attribute; stale entries
  are rebuilt manually via `bunk decode`.

## Contribution

Commit messages follow the 50/70 rule (subject line ≤ 50 characters,
body lines ≤ 70 characters). No heading prefixes.

