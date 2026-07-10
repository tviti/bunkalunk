from sqlite3 import Connection

from bunkalunk.db.activities import Activity, _upsert_activity


def upsert_dummy_activity(db_conn, fingerprint):
    """Add row with dummy start_time and no on-disk counterpart.

    Use in tests that exercise the FK constraint but don't utilise a cache
    entry.

    """
    activity = Activity(99.999, fingerprint, x_min=0.0, y_min=0.0, x_max=1.0, y_max=2.0)
    _upsert_activity(db_conn, activity)
    return activity


def has_source_file(conn: Connection, source_path: str) -> bool:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT EXISTS(SELECT 1 FROM source_files WHERE source_path = ?)",
            (source_path,),
        )
        return cursor.fetchone()[0] == 1
    finally:
        conn.rollback()
