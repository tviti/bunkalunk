from pathlib import Path
from sqlite3 import Connection, Row, connect


BUNK_SCHEMA_VERSION = 20260705


def _set_user_version(conn: Connection, version: int):
    if not isinstance(version, int):
        raise TypeError(
            f"user_version must be int, got {type(version).__name__} ({version})"
        )
    conn.execute(f"PRAGMA user_version = {version}")


def _create_source_files_table(conn: Connection):
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS source_files (
                source_path TEXT PRIMARY KEY,
                content_fingerprint TEXT NOT NULL,
                decode_state TEXT,
                decode_error TEXT,
                FOREIGN KEY(content_fingerprint) REFERENCES activities(source_fingerprint)
            )
        """
        )
    finally:
        cursor.close()


def _create_activities_table(conn: Connection):
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS activities (
                activity_id INTEGER PRIMARY KEY,
                source_fingerprint TEXT UNIQUE NOT NULL,
                start_time REAL,
                cache_version INT,
                ride_tag TEXT,
                sport TEXT
            )
        """
        )
        cursor.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_activities_start_time
            ON activities(start_time)
        """
        )
    finally:
        cursor.close()


def create_connection(db_path: Path | str) -> Connection:
    conn = connect(db_path)

    user_version = conn.execute("PRAGMA user_version").fetchone()[0]
    if user_version == 0:
        _set_user_version(conn, BUNK_SCHEMA_VERSION)
    elif user_version != BUNK_SCHEMA_VERSION:
        raise RuntimeError(
            "Database user_version mismatch: expected "
            f"{BUNK_SCHEMA_VERSION}, got {user_version}; rebuild the db and cache"
        )

    conn.execute("PRAGMA foreign_keys = ON")
    _create_activities_table(conn)
    _create_source_files_table(conn)
    conn.row_factory = Row
    return conn
