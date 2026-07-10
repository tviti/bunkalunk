BEGIN;

CREATE TABLE IF NOT EXISTS source_files (
    source_path TEXT PRIMARY KEY,
    content_fingerprint TEXT NOT NULL,
    decode_state TEXT,
    decode_error TEXT,
    FOREIGN KEY (content_fingerprint) REFERENCES activities (source_fingerprint)
);

CREATE TABLE IF NOT EXISTS activities (
    activity_id INTEGER PRIMARY KEY,
    source_fingerprint TEXT UNIQUE NOT NULL,
    start_time REAL,
    cache_version INT,
    ride_tag TEXT,
    sport TEXT,
    x_min REAL NOT NULL, x_max REAL NOT NULL,
    y_min REAL NOT NULL, y_max REAL NOT NULL,
    CHECK (x_min <= x_max),
    CHECK (y_min <= y_max)
);

CREATE INDEX IF NOT EXISTS idx_activities_start_time
ON activities (start_time);

COMMIT;

-- Local Variables:
-- flymake-sqlfluff-dialect: "sqlite"
-- indent-tabs-mode: nil
-- tab-stop-list: (4 8)
-- End:
