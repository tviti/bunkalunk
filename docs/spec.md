# Bunkalunk Specification

## Status

Draft.

## Overview

Bunkalunk is a local-first ride-data analysis framework for a
user-controlled toolchain.

It accepts explicit user-supplied local activity files via a separate cache
manager (`bunk`), decodes supported formats into a stable intermediate
storage artifact that preserves non-core extension data, and computes
queryable derived analysis results through the analysis CLI (`lunk`).

Bunkalunk is not a sync system, archive manager, backup tool, or vendor API
client. Those responsibilities belong to external tools.

## Design Principles

- Data ownership: users must be able to analyze their own ride data outside
  vendor platforms and closed ecosystems.
- Local-first reproducibility: decoded and derived outputs must be rebuildable
  from user-supplied raw files when decoder logic, schema versions, or analysis
  logic changes. The HDF5 storage artifact is considered ephemeral; it is a
  performance optimization and may be deleted and fully reconstructed from raw
  files using the SQLite index, so long as the index still points to the
  associated raw source file.
- Scriptability: the system must expose stable command-line workflows and
  predictable behavior over local files.
- Minimal abstraction: prefer concrete file-based workflows, one canonical
  decoded schema, and a small number of storage roles.
- Format-based decoding: decoders are organized by file format, not by file
  provenance or acquisition source.
- Extension preservation: non-core fields are preserved in an auxiliary lane
  without silent promotion into the canonical schema.
- Narrow scope: sync, archival layout, backup, and vendor integration are out
  of scope.
- Python layer as schema owner: the Python `db.py` module is the single owner
  of the SQLite schema, migrations, and ingestion-oriented database logic.
  Julia analysis code may read from SQLite directly and may write a narrow,
  explicitly approved set of analysis-owned tables. Julia does not
  participate in schema definition or migration logic.
- Local state isolation: all bunkalunk state (SQLite database and HDF5
  activity store) lives under a single configurable root directory,
  defaulting to `~/.bunk/`. The root may be overridden via the `BUNK_HOME`
  environment variable. This keeps state co-located, predictable, and
  easy to redirect for testing or isolation.
- SQLite as language boundary: SQLite is the durable storage boundary between
  Python ingestion code and Julia analysis code. The project does not define
  a JSON, RPC, or subprocess query protocol for routine database reads and
  writes in the MVP.
- Narrow direct database access: direct SQLite access from Julia is allowed
  only where it keeps the architecture simpler than introducing an
  inter-process API. This access must remain limited to analysis workflows
  and a small set of analysis-owned tables.

## Scope

Bunkalunk is responsible for:

- accepting explicit local file paths
- accepting only supported file formats
- computing content fingerprints
- recording a small source-file index in SQLite
- decoding supported files into a canonical HDF5 activity cache
- preserving extension fields in an auxiliary HDF5 lane
- computing derived analysis results such as segment efforts
- storing query-oriented derived data in SQLite
- incrementally recomputing and persisting derived analysis results when
  cached results are missing or stale

Bunkalunk is not responsible for:

- syncing files from devices or vendor platforms
- copying files into a project-owned raw archive
- defining a canonical raw-file storage layout
- backup or retention of user raw files
- semantic deduplication of files representing the same real-world ride
- vendor-specific proprietary API integrations

The ingestion boundary of this project is user-supplied local files.

## Assumptions

The initial design assumes:

- raw activity files are reasonably sized
- decoding supported files is a reasonably cheap operation
- users explicitly name files they want processed
- built-in recursive directory ingestion is not required initially

Because decoding is assumed to be cheap, the default ingestion workflow is
decode on add rather than deferred decode.

If those assumptions stop holding, future versions may add more explicit
reprocessing workflows without changing the project boundary.

## Technology Stack

Bunkalunk uses the following core technologies:

- Python 3.9+
  - source-file handling and decoding
  - SQLite access layer
  - command-line workflows
- Julia
  - analysis and segment-matching code
- SQLite
  - local operational database for source-file index, decode outcomes,
    derived results, and extension-field discovery metadata
  - configured in WAL mode, which supports concurrent readers and is
    sufficient for expected single-user and light multi-process workloads
- HDF5
  - ephemeral cache of decoded activities and auxiliary extension-field payloads
- `fitdecode`
  - FIT parsing/decoding in the Python layer
- `h5py`
  - HDF5 read/write support in the Python layer
- `ArchGDAL`
  - Julia dependency available in the analysis environment
- SQLite client library for Julia
  - Julia analysis code uses a thin local SQLite access layer for approved
    analysis queries and writes
  - no Python-mediated JSON or RPC database protocol is required for MVP
- `PythonCall` or subprocess interop
  - optional implementation tools for cross-language invocation where useful
  - not required for routine persistence of analysis results
- `DataFrames`
  - Julia tabular analysis support
- `LanguageServer`
  - Julia development tooling
- `Shapefile`
  - Julia geospatial file support

SQLite serves as the operational index for the tool. HDF5 serves as a secondary,
ephemeral cache of decomposed activity data. A minimal Python access API built
on the standard library `sqlite3` module owns schema creation, migrations, and
ingestion-oriented database access. Julia analysis code may use its own thin
SQLite layer for a narrow set of approved analysis workflows. The project
intentionally avoids introducing a custom JSON or RPC protocol for routine
database interop in the MVP.

## Architecture

Bunkalunk consists of three parts:

- SQLite operational index
  - source-file index
  - decode outcome metadata
  - derived analysis results
  - extension-field discovery metadata
- HDF5 activity cache (Content-Addressable Storage)
  - stores decoded activities as individual files sharded by the first two
    characters of their SHA-256 content fingerprint
  - e.g. `activity_store/ab/<full-fingerprint>.h5`
  - decoded activity records
  - core time-series and activity metadata
  - auxiliary extension-field payloads
- Analysis code
  - reads decoded activities from HDF5
  - computes segment efforts and related analysis outputs
  - reads from SQLite for activity and segment metadata
  - writes persistent derived analysis results to analysis-owned SQLite tables
  - uses cached SQLite results for query-time reads where possible rather than
    recomputing all analyses on demand

SQLite serves both as the operational index for ingestion metadata and as the
durable cache for derived analysis results. HDF5 stores decoded activity
artifacts; SQLite stores query-oriented derived outputs such as segment
efforts. This split is intentional: decoded records are cached in HDF5, while
analysis results are cached in SQLite.

## Input Contract

The input to Bunkalunk is one or more explicit user-supplied local file paths.

Initial rules:

- input is by explicit file path
- built-in recursive directory support is out of scope initially
- users who want recursive ingestion may script file discovery externally
- only supported file extensions are accepted
- unsupported files are rejected up front rather than indexed

Initial supported formats:

- `.fit`

Future formats may include:

- `.tcx`
- `.gpx`

Initial decoder dispatch is by filename extension. Content-based format
detection may be added later if needed.

## Source File Model

The source-file index is path-oriented in the initial implementation.

Each row represents one explicitly added source path.

`source_files` models user registrations, not user-facing activity-library
identity. In the initial design, `source_path` is the identity of a registered
local file because ingestion and repair workflows are path-oriented. This does
not make `source_path` the primary lookup handle for activity browsing or
analysis. User-facing activity discovery is expected to rely primarily on
activity metadata such as `start_time` and secondarily on optional handles such
as `ride_tag` or `activity_id`.

Required fields:

- `source_path`
- `content_fingerprint`
- `last_decode_error`
- `last_decode_error_at`

Field rules:

- `content_fingerprint` is the SHA-256 digest of raw file bytes
- `last_decode_error` records a descriptive error from the last decode attempt,
  and should be null if the decode was successful
- `last_decode_error_at` records the time of the last decode failure, and is
  null if the last decode was successful

Notes:

- `source_path` is the user-visible identity for registration and command
  targeting
- `content_fingerprint` is for storage identity
- fingerprints are stored from the beginning so future
  fingerprint-centered features remain possible
- the system does not perform semantic deduplication

If a previously registered path is later missing when touched by an
operation, Bunkalunk should emit a warning and skip it. Missing paths are
an operational condition, not a required persistent lifecycle state.

## Storage Model

### SQLite

SQLite is the single local operational database.

The database file defaults to `~/.bunk/db.sqlite3`. The root directory
may be overridden via the `BUNK_HOME` environment variable, in which case
the database is at `$BUNK_HOME/db.sqlite3`.

SQLite is configured in WAL mode. This is an intentional choice that
supports concurrent readers and is sufficient for expected single-user
and light multi-process workloads without introducing additional
infrastructure.

It stores:

- source-file registrations
- content fingerprints
- decode outcomes
- decode state
- decode artifact fingerprint [optional]
- activities and activity linkage
- segment definitions and efforts
- extension-field discovery metadata

The SQLite database is also the primary discovery index for the local activity
library. In particular, activity timestamps must be stored in SQLite and be
cheap to query so that apps and CLIs can locate rides by date/time without
first consulting source paths or content fingerprints.

### SQLite ownership model

SQLite has split operational ownership:

- Python owns:
  - schema definition
  - schema migrations
  - connection defaults and database initialization
  - source-file registration and decode bookkeeping
  - extension-field catalog registration

- Julia may directly read:
  - `activities`
  - `segments`
  - `segment_efforts`
  - any additional analysis-oriented read models explicitly added later

- Julia may directly write only approved analysis-owned tables:
  - `segments`
  - `segment_efforts`

Julia does not create or migrate tables and does not write ingestion-owned
tables such as `source_files` or extension-field catalog metadata.

Minimum tables:

- `source_files` — Python-owned
  - `source_path`
  - `content_fingerprint`
  - `decode_fingerprint`
  - `decode_state`
  - `last_decode_error`
  - `last_decode_error_at`
- `activities` — Python-owned, Julia-readable
  - `activity_id`
  - `start_time`
  - `content_fingerprint`
  - `decode_fingerprint`
  - `ride_tag` (nullable)

`activities` is the primary library/discovery table for decoded rides. It is
separate from `source_files`: `source_files` tracks registered local files,
while `activities` tracks analyzable activities. User-facing ride lookup should
primarily use activity metadata such as `start_time`, and may additionally use
`ride_tag` or `activity_id`. `content_fingerprint` remains an internal content
identity used for decode bookkeeping, cache addressing, and staleness checks; it
is not intended to be the primary human-facing activity selector.

- `segments` — analysis-owned
  - `segment_id`
  - `name`
  - `version`
  - `definition_path`
- `segment_efforts` — analysis-owned persistent cache
  - `effort_id`
  - `activity_id`
  - `segment_id`
  - `elapsed_time_s`
  - `start_offset_s`
  - `end_offset_s`
  - `matched_at`
  - `matcher_version`
  - `quality_score` (nullable)
- `extension_field_catalog` — Python-owned
  - `field_id`
  - `format`
  - `namespace`
  - `field_name`
  - `value_type`
  - `scope` (`activity` or `timeseries`)
  - `first_seen_at`

At minimum, SQLite indexes must support efficient lookup of activities by
timestamp. The MVP should therefore index `activities.start_time`. Additional
indexes may be added for common lookup paths such as `ride_tag`,
`content_fingerprint`, and analysis-table joins.

### Derived-result cache rules

`segment_efforts` is a durable derived-results cache, not merely an export
table. `lunk` relies on this cache to avoid recomputing segment matches across
the full activity corpus for every query.

Cached analysis results must be treated as stale when relevant inputs change.
At minimum, staleness checks must consider:

- the analyzed activity identity
- the activity content fingerprint or equivalent decoded-input identity
- the segment definition version
- the matcher algorithm version

The implementation may materialize these checks either by joins against
current metadata or by denormalizing additional version/fingerprint fields
into analysis tables. The MVP may choose the simplest approach that supports
reliable incremental recomputation.

### HDF5

The HDF5 activity store defaults to `~/.bunk/activity_store/`. It follows
the same `BUNK_HOME` root as the SQLite database. The store root is always
derived from `BUNK_HOME` and is not separately configurable.

Bunkalunk defines one canonical decoded schema. HDF5 files are ephemeral cache
artifacts implementing that schema; they are not the operational source of
truth. HDF5 is the storage artifact representing a cache of decoded
activities. The cache is implemented as a content-addressable store, with each
artifact corresponding to a single activity. To ensure filesystem performance at
scale, the store uses directory sharding: each decoded activity is stored in a
separate HDF5 file where the directory is the first two characters of the
SHA-256 fingerprint of the source activity, and the filename is the full
fingerprint. This facilitates byte-level deduplication and mitigates the effects
of file corruption.

The choice to map each file to a single activity (as opposed to a monolithic
HDF5 db that uses categories to represent activities), minimizes blast radius in
the event of any type of cache invalidation. For example, a single file
corruption event during activity decoding will invalidate a single cache entry,
and is easy to recover from. In a monolithic cache db, this would potentially
require rebuilding the entire db. This facilitates prototyping, by making schema
changes cheap and low risk.

The canonical schema contains core analysis fields such as:

- timestamps
- latitude / longitude
- elevation
- distance if available or derived
- speed if available or derived
- heart rate if available
- cadence if available
- power if available
- temperature if available
- activity metadata needed for analysis

This schema should remain small, stable, and source-agnostic.

Extension handling:

- format-specific extension payloads are preserved in an auxiliary HDF5 lane
- extension fields are namespaced by format, namespace, and field identifier
  or path
- extension payloads remain outside the canonical schema by default
- SQLite stores extension-field discovery metadata, not the full payload

Use a single concrete HDF5 schema with a version integer.

Failed or interrupted decodes must not publish a final-path HDF5 cache file. A
cache entry is considered present only once a complete decoded artifact has been
successfully written.

## Decode Contract

Decoding is performed by format-specific decoders. The initial implementation
assumes one decoded activity per supported source file. Accordingly,
`activities` may be keyed by content fingerprint.

Decode responsibilities:

- dispatch by supported file extension
- parse the source file
- extract core fields into the canonical HDF5 schema
- capture extension fields into the auxiliary HDF5 lane
- write decoded activity records to a unique HDF5 file named by the source
  file's content fingerprint
- update decode outcome fields in SQLite
- register newly observed extension fields in the SQLite catalog

A `.fit` file is decoded identically regardless of how the user obtained or
stored it.

Decode outputs may invalidate previously cached analysis results indirectly by
changing the decoded activity basis for a given content fingerprint. Analysis
workflows must therefore treat activity content identity as an input to
derived-result staleness checks.

## Ingestion Workflow

The default workflow is decode on add.

When a user adds a supported file, Bunkalunk must:

- verify that the file extension is supported
- read the file and compute its SHA-256 fingerprint
- register or update the source-file row in SQLite
- decode the file immediately
- write decoded content to HDF5 storage artifact
- update decode outcome metadata in SQLite

Bunkalunk may also expose an explicit manual `decode` or `redecode` command for
repair, retry, or schema-evolution workflows, but deferred decode is not the
default design.

Ingestion is responsible for producing decoded activity artifacts and updating
activity metadata, but it does not recompute all downstream analysis caches
automatically. Derived analysis results are refreshed by analysis workflows
when needed.

## Duplicate Handling

Bunkalunk records content fingerprints for exact-content identification.

However, it does not:

- perform semantic deduplication
- decide whether distinct files represent the same real-world ride
- silently collapse records using higher-level ride identity logic

The initial path-oriented source model may tolerate exact-content duplicates at
different paths. Exact duplicate policy may later become warn-only or
operator-configurable, but no semantic duplicate-resolution policy belongs in
ingestion.

Exact-content duplicates at different source paths may exist in the
`source_files` index, but they share the same decoded HDF5 cache object and
activity identity via `content_fingerprint`.

## CLI Contract


### `bunk`

Preferred initial commands:

- `add <path>...`
  - register explicit local source files and decode them immediately
- `decode [selection]`
  - manually decode or re-decode previously added files
- `rebuild [selection|--all]`
  - restore missing, unreadable, or schema-incompatible cache entries for
    registered source files
  - decode **only when needed**, e.g. when:
    - cache file is missing
    - cache file is unreadable/corrupt
    - cache schema version is outdated/incompatible
  - If selected source path is missing, warn and skip.
  - rebuild affects decoded HDF5 cache artifacts; it does not itself refresh
    all derived SQLite analysis caches

In the initial implementation, `decode` and `rebuild` selections are expressed
in terms of registered source paths. `decode` is an explicit operator action
that reprocesses selected source files. `rebuild` is a repair/reconciliation
action that restores missing or invalid cache artifacts for registered source
files without forcing unnecessary re-decodes.

Possible future commands:

- `status`
- `relocate`
- `export`
  - Export to CSV/YAML/JSON for inspection (TODO: decide on one format)

The cache-manager CLI should remain small and avoid source-specific
subcommand systems or plugin-style command registries unless a real need
emerges.

### `lunk`

`lunk` is the reference app for the bunkalunk framework. Its scope is a
CLI replica of the activity summary and segment pages familiar from
platforms like Strava or Garmin Connect: segment leaderboards, segment
efforts per ride, and activity-level summary statistics (heart rate,
power, etc.). If a metric appears on those pages, it is in scope for
`lunk`. Anything outside that scope belongs in a separate app.

`lunk` is also the app that non-technical riders install and run. It
lives in the bunkalunk repo as the reference implementation and may be
split into its own package later if that becomes warranted.

Preferred initial commands:

- `segment match <segment-name>`
  - compute and persist segment efforts for decoded activities relevant to a
    segment
  - by default, process only activities whose cached results are missing or
    stale for the current segment definition and matcher version
  - may support a force/rematch option to ignore cache reuse
- `segment show <segment-name>`
  - print leaderboard for a specific segment from cached SQLite results
  - may warn if relevant activities appear not yet matched or stale
  - may support `--rematch` to recompute stale or missing results before
    display
- `ride show <activity-id|ride-tag>`
  - print activity summary statistics for a single ride
  - future selectors may include timestamp/date-oriented lookup because users
    commonly identify rides by when they occurred rather than by source path
    or opaque IDs

`lunk` is expected to use SQLite as a durable cache for derived analysis
outputs. Leaderboard-oriented commands should read cached results where
available and trigger incremental recomputation only for activities whose
results are missing or stale.

## App Model

Bunkalunk is designed to be used as a framework, not only as a tool.

- `bunk` is the cache manager. Non-technical riders use it directly.
- `lunk` is the reference app. It ships with bunkalunk and covers the
  core use case: segment leaderboards and activity summaries.
- Independent apps are Julia projects that declare a local or registered
  package dependency on bunkalunk. They are not hosted inside the
  bunkalunk repo and do not need to conform to any plugin interface.

An app is any Julia program that imports bunkalunk as a library. It may:

- read decoded activity data from HDF5
- call the `db.py` API to read from or write to SQLite
- perform its own analysis, using the Julia analysis library as needed
- present results however it chooses

Apps are full-stack tools. They are not restricted to reading
pre-computed results. An app that wants to do exploratory data analysis
over raw decoded records is a valid and expected use case.

The Python `db.py` API is the authoritative interface for schema definition,
migrations, and ingestion-owned database operations.

Julia apps may read SQLite directly and may write a narrow, explicitly
approved set of analysis-owned tables. They must not modify ingestion-owned
tables or participate in schema migration logic.

The project does not require a Python-mediated JSON, RPC, or subprocess
database protocol for routine analysis persistence. SQLite itself is the
primary persistence boundary between Python and Julia in the MVP.

## Analysis Workflow

The initial analysis product is a personal segment-time leaderboard.

Expected workflow:

- user adds one or more raw activity files
- `bunk` caches accepted files into the HDF5 CAS via the separate cache manager
- `bunk` records source-file and decode metadata in SQLite
- `lunk` resolves activities and metadata through SQLite, then loads decoded
  activities from the HDF5 cache
- SQLite activity lookup is expected to support timestamp-oriented workflows
  such as locating a ride by day or start time before loading decoded artifacts
  from HDF5

- segment definitions are loaded from `resources/segments/`
- `lunk` determines which activities for the requested segment are missing
  cached efforts or have stale cached efforts
- segment efforts are computed only for those missing or stale activities
- effort rows are written to analysis-owned SQLite tables
- `lunk` leaderboard queries read cached results from SQLite

This incremental model is important because ride archives are typically
append-mostly and grow over time. Recomputing all segment matches for every
leaderboard query is not an acceptable default once the corpus becomes
moderately large.

Leaderboards should display segment times with timestamps or ride tags so that
users can inspect repeated efforts over time.

## Non-Goals

The initial implementation does not provide:

- vendor API integrations
- device sync
- backup tooling
- canonical raw-file archival layout
- copying raw files into a managed archive
- recursive directory ingestion
- semantic deduplication tooling
- content-based format detection
- plugin registries
- generalized adapter frameworks
- generalized migration frameworks
- a custom JSON or RPC protocol for routine cross-language database access

## Directory Layout

Recommended layout:

- `src/`
  - `julia/` — analysis and segment-matching code
    - `db.jl` — thin SQLite access layer for analysis queries and writes
  - `lunk/` — reference app (segment leaderboards, activity summaries)
  - `python/` — source-file handling and decode
    - `bunkalunk/` — Python package containing the cache manager and DB layer
      - `db.py` — authoritative SQLite schema, migrations, and ingestion DB layer
      - `bunk.py` — cache-manager index management, decoding
      - `bunk_helpers.py` — helpers for `bunk.py`
    - `formats/` — modules for working with supported file types
      - `fit.py` — FIT parsing/decoding
      - `gpx.py` — future
      - `tcx.py` — future
      - `csv.py` — future
- `resources/`
  - `segments/` — segment definitions in open formats
- `activity_store/` — CAS directory containing fingerprint-named HDF5 files
- `analysis/` — SQLite database and optional exports
- `docs/` — specifications and decision records
  - `notes.org` — lab notebook and timestamped design notes
  - `spec.md` — project specification and architecture documentation
  - `tasks.org` — org-mode task and issue tracking file

The SQLite database and HDF5 activity store are not part of the project
directory layout. They live under `~/.bunk/` by default, or under
`$BUNK_HOME` if that environment variable is set.

## Build Now

Build now:

- explicit `add <path>...`
- decode on add
- one `.fit` decoder
- one SQLite database for source-file index and results
- one concrete HDF5 schema and writer
- extension-field payload capture in HDF5
- extension-field catalog in SQLite
- segment definitions in `resources/segments/`
- segment matching pipeline
- `lunk` leaderboard CLI
- explicit bulk rebuild tooling
- thin Python `db.py` layer for schema, migrations, and ingestion-owned tables
- thin Julia SQLite layer for approved analysis queries and writes
- persistent SQLite cache for segment efforts and related derived results
- incremental segment matching against missing or stale cached results
- SQLite configured in WAL mode
- all state rooted under `BUNK_HOME`, defaulting to `~/.bunk/`

## Defer

Defer for later:

- recursive directory ingestion
- additional format decoders
- relocate workflow for moved files
- content-based format detection
- richer status reporting
- extension-field promotion tooling
- semantic deduplication support tooling
- sync and acquisition integrations

## Decisions Recorded

- The project remains a single repository with Python and Julia subtrees.
- Python owns SQLite schema definition, migrations, and ingestion-oriented
  database logic.
- Julia may directly access SQLite for a narrow analysis-oriented subset of the
  database.
- The MVP does not introduce a JSON, RPC, or subprocess database protocol for
  routine persistence between Python and Julia.
- `lunk` persists derived analysis results in SQLite and uses incremental
  recomputation rather than full recomputation on every query.

## Contribution

Commit messages follow the 50/70 rule (subject line ≤ 50 characters, body lines
≤ 70 characters). Heading prefixes (e.g., `docs:`, `fix:`) are not used.
