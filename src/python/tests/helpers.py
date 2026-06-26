from bunkalunk.db import Connection


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
