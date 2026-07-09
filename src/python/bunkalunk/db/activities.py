from dataclasses import asdict, dataclass
from sqlite3 import Connection

from bunkalunk import cache


@dataclass
class Activity:
    start_time: float
    source_fingerprint: str
    ride_tag: str | None = None
    activity_id: int | None = None
    sport: str | None = None


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


def drop_activity(conn: Connection, source_fingerprint: str) -> None:
    cursor = conn.cursor()
    try:
        cursor.execute(
            "DELETE FROM activities WHERE source_fingerprint = ?", (source_fingerprint,)
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


def is_stale(conn: Connection, source_fingerprint: str) -> bool:
    cursor = conn.cursor()
    row = None
    try:
        cursor.execute(
            """
            SELECT cache_version FROM activities
            WHERE source_fingerprint = :source_fingerprint
            """,
            {
                "source_fingerprint": source_fingerprint,
            },
        )
        row = cursor.fetchone()
    finally:
        cursor.close()

    if row is None:
        return True

    return row["cache_version"] < cache.CACHE_VERSION
