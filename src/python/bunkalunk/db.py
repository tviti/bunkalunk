from dataclasses import asdict, dataclass
from enum import StrEnum
from pathlib import Path
from sqlite3 import Connection, Row, connect

from bunkalunk import cache

"""SQLite operational database schema plus HDF5 canonical decoded schema.

SQLite stores source-file registrations, content fingerprints, decode outcomes,
activities, segment definitions/efforts, and extension-field discovery metadata.

HDF5 is a separate ephemeral cache implementing the canonical decoded schema for
core analysis fields (timestamps, lat/lon, elevation, speed, distance, heart
rate, cadence, power, temperature). Extension payloads live in an auxiliary lane
outside the canonical schema."""


class DecodeState(StrEnum):
    PENDING = "pending"
    SUCCESS = "success"
    ERROR = "error"


@dataclass
class SourceFile:
    source_path: str
    content_fingerprint: str
    decode_state: DecodeState = DecodeState.PENDING
    decode_error: str | None = None


@dataclass
class Activity:
    start_time: str
    source_fingerprint: str
    ride_tag: str | None = None
    activity_id: int | None = None
    sport: str | None = None


def _create_source_files_table(conn: Connection):
    cursor = conn.cursor()
    try:
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS source_files (
                source_path TEXT PRIMARY KEY,
                content_fingerprint TEXT NOT NULL,
                decode_state TEXT,
                decode_error TEXT
            )
        """)
    finally:
        cursor.close()


def _create_activities_table(conn: Connection):
    cursor = conn.cursor()
    try:
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS activities (
                activity_id INTEGER PRIMARY KEY,
                source_fingerprint TEXT UNIQUE NOT NULL,
                start_time TEXT,
                cache_version INT,
                ride_tag TEXT,
                sport TEXT
            )
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_activities_start_time
            ON activities(start_time)
        """)
    finally:
        cursor.close()


def create_connection(db_path: Path | str) -> Connection:
    conn = connect(db_path)
    _create_source_files_table(conn)
    _create_activities_table(conn)
    conn.row_factory = Row
    return conn


def upsert_source_file(conn: Connection, source_file: SourceFile) -> None:
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            INSERT INTO source_files (
                source_path,
                content_fingerprint,
                decode_state,
                decode_error
            ) VALUES (
                :source_path,
                :content_fingerprint,
                :decode_state,
                :decode_error
            ) ON CONFLICT(source_path) DO UPDATE SET
                content_fingerprint=excluded.content_fingerprint,
                decode_state=excluded.decode_state,
                decode_error=excluded.decode_error
        """,
            asdict(source_file),
        )
    finally:
        cursor.close()


def drop_source_file(
        conn: Connection,
        source_path: str,
) -> None:
    cursor = conn.cursor()
    try:
        cursor.execute("""
            DELETE FROM source_files WHERE source_path = ?
        """,
        (source_path,)
        )
    finally:
        cursor.close()


def record_decode_outcome(
    conn: Connection, source_path: str, *, state: DecodeState, error: str | None = None
) -> None:
    decode_error = error if state == DecodeState.ERROR else None
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            UPDATE source_files
            SET decode_state = :decode_state,
                decode_error = :decode_error
            WHERE source_path = :source_path
        """,
            {
                "decode_state": state.value,
                "decode_error": decode_error,
                "source_path": source_path,
            },
        )
    finally:
        cursor.close()


def record_source_file_fingerprint(
    conn: Connection, source_path: str, content_fingerprint: str
) -> None:
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            UPDATE source_files
            SET content_fingerprint = :content_fingerprint,
                decode_state = :decode_state,
                decode_error = :decode_error
            WHERE source_path = :source_path
        """,
            {
                "content_fingerprint": content_fingerprint,
                "decode_state": DecodeState.PENDING.value,
                "decode_error": None,
                "source_path": source_path,
            },
        )
    finally:
        cursor.close()


def get_source_file(conn: Connection, source_path: str) -> SourceFile | None:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT * FROM source_files WHERE source_path = ?",
            (source_path,),
        )
        row: Row | None = cursor.fetchone()
    finally:
        cursor.close()

    if row is None:
        return None

    return SourceFile(
        source_path=row["source_path"],
        content_fingerprint=row["content_fingerprint"],
        decode_state=row["decode_state"],
        decode_error=row["decode_error"],
    )


def list_source_files_by_decode_state(
    conn: Connection, state: DecodeState
) -> list[SourceFile]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT * FROM source_files WHERE decode_state = ?", (state.value,)
        )
        rows: list[Row] = cursor.fetchall()
    finally:
        cursor.close()

    return [SourceFile(**row) for row in rows]


def list_source_files_stale_cache(conn: Connection) -> list[SourceFile]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            """
            SELECT source_files.* from source_files
            JOIN activities
              ON activities.source_fingerprint = source_files.content_fingerprint
            WHERE activities.cache_version < ?
        """,
            (cache.CACHE_VERSION,),
        )
        rows: list[Row] = cursor.fetchall()
    finally:
        cursor.close()

    return [SourceFile(**row) for row in rows]


def _upsert_activity(conn: Connection, activity: Activity) -> None:
    cursor = conn.cursor()
    try:
        row = asdict(activity)
        row["cache_version"] = cache.CACHE_VERSION
        cursor.execute(
            """
            INSERT INTO activities (
                start_time,
                source_fingerprint,
                ride_tag,
                sport,
                cache_version
            ) VALUES (
                :start_time,
                :source_fingerprint,
                :ride_tag,
                :sport,
                :cache_version
            ) ON CONFLICT(source_fingerprint) DO UPDATE SET
                start_time=excluded.start_time,
                ride_tag=excluded.ride_tag,
                sport=excluded.sport,
                cache_version=excluded.cache_version
        """,
            row,
        )
    finally:
        cursor.close()


def record_cache_creation(
    conn: Connection, cache_data: cache.CacheData, source_fingerprint: str
):
    activity = Activity(
        start_time=cache_data.start_time,
        source_fingerprint=source_fingerprint,
        sport=cache_data.sport,
    )
    _upsert_activity(conn, activity)
