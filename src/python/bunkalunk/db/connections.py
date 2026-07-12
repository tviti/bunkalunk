from pathlib import Path
from sqlite3 import Connection, Row, connect


BUNK_SCHEMA_VERSION = 20260711
_SCHEMA_FILE = Path(__file__).resolve().parent / "schema.sql"


def _set_user_version(conn: Connection, version: int):
    if not isinstance(version, int):
        raise TypeError(
            f"user_version must be int, got {type(version).__name__} ({version})"
        )
    conn.execute(f"PRAGMA user_version = {version}")


def _create_tables(conn: Connection):
    cursor = conn.cursor()
    try:
        with open(_SCHEMA_FILE, "r") as f:
            cursor.executescript(f.read())
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
    _create_tables(conn)
    conn.row_factory = Row
    return conn
