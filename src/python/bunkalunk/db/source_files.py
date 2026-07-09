from dataclasses import asdict, dataclass
from enum import StrEnum
from sqlite3 import Connection, Row

from bunkalunk import cache


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
        cursor.execute(
            """
            DELETE FROM source_files WHERE source_path = ?
        """,
            (source_path,),
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


def list_source_files_by_content_fingerprint(
    conn: Connection, content_fingerprint: str
) -> list[SourceFile]:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT * FROM source_files WHERE content_fingerprint = ?",
            (content_fingerprint,),
        )
        rows: list[Row] = cursor.fetchall()
    finally:
        cursor.close()

    return [SourceFile(**row) for row in rows]


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
