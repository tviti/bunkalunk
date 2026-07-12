from dataclasses import asdict, dataclass
from sqlite3 import Connection

from bunkalunk import cache


@dataclass
class Activity:
    start_time: float
    source_fingerprint: str

    x_min: float
    y_min: float

    x_max: float
    y_max: float

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
                cache_version,
                x_min, x_max,
                y_min, y_max
            ) VALUES (
                :start_time,
                :source_fingerprint,
                :ride_tag,
                :sport,
                :cache_version,
                :x_min, :x_max,
                :y_min, :y_max
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
    x_nanless = [x for x in cache_data.longitude if x is not None]
    y_nanless = [y for y in cache_data.latitude if y is not None]

    if len(x_nanless) > 0 and len(y_nanless) > 0:
        x_min = min(x_nanless)
        x_max = max(x_nanless)
        y_min = min(y_nanless)
        y_max = max(y_nanless)
    else:
        x_min = None
        x_max = None
        y_min = None
        y_max = None

    activity = Activity(
        start_time=cache_data.start_time,
        source_fingerprint=source_fingerprint,
        sport=cache_data.sport,
        x_min=x_min,
        x_max=x_max,
        y_min=y_min,
        y_max=y_max,
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
