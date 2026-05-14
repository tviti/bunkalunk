from sqlite3 import Row

import pytest
from bunkalunk import cache
from bunkalunk.cache import CacheData
from bunkalunk.db import (
    DecodeState,
    SourceFile,
    drop_source_file,
    get_source_file,
    list_source_files_stale_cache,
    record_cache_creation,
    record_decode_outcome,
    record_source_file_fingerprint,
    upsert_source_file,
)


def _fetch_source_file_by_path(conn, source_path) -> Row | None:
    """Helper to fetch a single source_files row by source_path."""
    curse = conn.cursor()
    curse.execute(
        """
        SELECT * FROM source_files WHERE source_path = ?
    """,
        (source_path,),
    )
    row: Row | None = curse.fetchone()
    curse.close()
    return row


def _fetch_source_files_by_path(conn, source_path) -> list[Row]:
    """Helper to fetch all source_files rows by source_path."""
    curse = conn.cursor()
    curse.execute(
        """
        SELECT * FROM source_files WHERE source_path = ?
    """,
        (source_path,),
    )
    rows: list[Row] = curse.fetchall()
    curse.close()
    return rows


def _fetch_activities_by_fingerprint(conn, source_fingerprint) -> list[Row]:
    """Helper to fetch activities rows by source_fingerprint."""
    curse = conn.cursor()
    curse.execute(
        """
        SELECT * FROM activities WHERE source_fingerprint = ?
    """,
        (source_fingerprint,),
    )
    rows: list[Row] = curse.fetchall()
    curse.close()
    return rows


def test_upsert_source_file_roundtrip(db_conn):
    source_file = SourceFile(
        source_path="a/ride/somewhere.fit",
        content_fingerprint="content-fingerprint",
        decode_state="error",
        decode_error="last-decode-error",
    )

    upsert_source_file(db_conn, source_file)
    db_conn.commit()

    row = _fetch_source_file_by_path(db_conn, "a/ride/somewhere.fit")

    assert row["source_path"] == "a/ride/somewhere.fit"
    assert row["content_fingerprint"] == "content-fingerprint"
    assert row["decode_state"] == "error"
    assert row["decode_error"] == "last-decode-error"


def test_upsert_source_file_idempotent(db_conn):
    source_file = SourceFile(
        source_path="a/ride/somewhere.fit",
        content_fingerprint="content-fingerprint",
        decode_state="error",
        decode_error="last-decode-error",
    )

    upsert_source_file(db_conn, source_file)
    upsert_source_file(db_conn, source_file)
    db_conn.commit()

    rows = _fetch_source_files_by_path(db_conn, "a/ride/somewhere.fit")

    assert len(rows) == 1
    row = rows[0]
    assert row["source_path"] == "a/ride/somewhere.fit"
    assert row["content_fingerprint"] == "content-fingerprint"
    assert row["decode_state"] == "error"
    assert row["decode_error"] == "last-decode-error"


def test_upsert_source_file_update(db_conn):
    source_file = SourceFile(
        source_path="a/ride/somewhere.fit",
        content_fingerprint="content-fingerprint",
        decode_state="pending",
        decode_error="last-decode-error",
    )

    upsert_source_file(db_conn, source_file)
    source_file.content_fingerprint = "new-fingerprint"
    source_file.decode_state = "error"
    source_file.content_fingerprint = "new-fingerprint"
    source_file.decode_error = "new-error"
    upsert_source_file(db_conn, source_file)
    db_conn.commit()

    rows = _fetch_source_files_by_path(db_conn, "a/ride/somewhere.fit")

    assert len(rows) == 1
    row = rows[0]
    assert row["source_path"] == "a/ride/somewhere.fit"
    assert row["content_fingerprint"] == "new-fingerprint"
    assert row["decode_state"] == "error"
    assert row["decode_error"] == "new-error"


def test_drop_source_file_drops(db_conn, dummy_source_files_table):
    rows = _fetch_source_files_by_path(db_conn, "a/fit/file.fit")
    assert len(rows) == 1
    assert rows[0]["source_path"] == "a/fit/file.fit"
    drop_source_file(db_conn, "a/fit/file.fit")
    rows = _fetch_source_files_by_path(db_conn, "a/fit/file.fit")
    assert rows == []


def test_record_decode_outcome(db_conn):
    state = DecodeState.SUCCESS
    source_file = SourceFile(
        source_path="ride.fit",
        content_fingerprint="content-fingerprint",
        decode_state="error",
        decode_error="last-decode-error",
    )

    upsert_source_file(db_conn, source_file)
    record_decode_outcome(db_conn, "ride.fit", state=state)
    db_conn.commit()

    row = _fetch_source_file_by_path(db_conn, "ride.fit")

    assert row["decode_state"] == "success"


@pytest.fixture(scope="function")
def dummy_source_files_table(db_conn):
    """Fixture with dummy source_files row."""
    source_file = SourceFile(
        source_path="a/fit/file.fit",
        content_fingerprint="fingerprint123",
        decode_state=DecodeState.SUCCESS,
        decode_error="an-error-code",
    )
    upsert_source_file(db_conn, source_file)
    db_conn.commit()
    return db_conn


def test_record_source_file_fingerprint_updates_fingerprint(
    db_conn, dummy_source_files_table
):
    source_path = "a/fit/file.fit"
    source_file = get_source_file(db_conn, source_path)
    assert "fingerprint123" == source_file.content_fingerprint
    record_source_file_fingerprint(db_conn, source_path, "new-fingerprint")
    source_file = get_source_file(db_conn, source_path)
    assert "new-fingerprint" == source_file.content_fingerprint


def test_get_source_file_found(dummy_source_files_table):
    result = get_source_file(dummy_source_files_table, "a/fit/file.fit")
    assert result is not None
    assert result.source_path == "a/fit/file.fit"
    assert result.content_fingerprint == "fingerprint123"
    assert result.decode_state == DecodeState.SUCCESS
    assert result.decode_error == "an-error-code"


def test_get_source_file_not_found(db_conn):
    result = get_source_file(db_conn, "non/existent/file.fit")
    assert result is None


def test_record_cache_creation_idempotent(db_conn, monkeypatch):
    source_fingerprint = "abc123"
    cache_data = CacheData(
        start_time=1767263400.0,
        latitude=[1.0, 1.1, 1.2],
        longitude=[2.0, 2.1, 2.2],
        time=[0.0, 1.0, 2.0],
        sport="yoyo",
    )

    monkeypatch.setattr(cache, "CACHE_VERSION", 19991230)
    record_cache_creation(db_conn, cache_data, source_fingerprint)
    record_cache_creation(db_conn, cache_data, source_fingerprint)
    db_conn.commit()

    rows = _fetch_activities_by_fingerprint(db_conn, source_fingerprint)

    assert len(rows) == 1
    row = rows[0]
    assert row["source_fingerprint"] == source_fingerprint
    assert row["start_time"] == 1767263400.0
    assert row["sport"] == "yoyo"
    assert row["cache_version"] == 19991230


def test_record_cache_creation_updates(db_conn, monkeypatch):
    source_fingerprint = "abc123"
    cache_data = CacheData(
        start_time=1767263400.0,
        latitude=[1.0, 1.1, 1.2],
        longitude=[2.0, 2.1, 2.2],
        time=[0.0, 1.0, 2.0],
        sport="yoyo",
    )

    monkeypatch.setattr(cache, "CACHE_VERSION", 19991230)
    record_cache_creation(db_conn, cache_data, source_fingerprint)
    monkeypatch.setattr(cache, "CACHE_VERSION", 19991231)
    cache_data.start_time = 1798799400.0
    source_fingerprint = "cde456"
    record_cache_creation(db_conn, cache_data, source_fingerprint)
    db_conn.commit()

    rows = _fetch_activities_by_fingerprint(db_conn, source_fingerprint)
    assert len(rows) == 1
    row = rows[0]
    assert row["start_time"] == 1798799400.0
    assert row["sport"] == "yoyo"
    assert row["source_fingerprint"] == "cde456"
    assert row["cache_version"] == 19991231


@pytest.fixture(scope="function")
def source_file_with_cache_version_factory(db_conn):
    """Factory fixture that creates matching source_files and activities rows.

    Yields a function that accepts cache_version and returns (source_path,
    content_fingerprint).
    """

    def _factory(cache_version: int):
        source_file = SourceFile(
            source_path=f"ride_{cache_version}.fit",
            content_fingerprint=f"fingerprint_{cache_version}",
            decode_state=DecodeState.SUCCESS,
            decode_error=None,
        )
        upsert_source_file(db_conn, source_file)

        cursor = db_conn.cursor()
        try:
            cursor.execute(
                """
                INSERT OR REPLACE INTO activities (
                    source_fingerprint,
                    start_time,
                    cache_version,
                    ride_tag,
                    sport
                ) VALUES (?, ?, ?, ?, ?)
            """,
                (
                    source_file.content_fingerprint,
                    1767263400.0,
                    cache_version,
                    None,
                    None,
                ),
            )
        finally:
            cursor.close()
        db_conn.commit()
        return source_file

    return _factory


def test_list_source_files_stale_cache_stale(
    source_file_with_cache_version_factory, db_conn, monkeypatch
):
    monkeypatch.setattr(cache, "CACHE_VERSION", 19991231)
    source_file = source_file_with_cache_version_factory(19991230)
    result = list_source_files_stale_cache(db_conn)
    assert len(result) == 1
    assert result[0].source_path == source_file.source_path


def test_list_source_files_stale_cache_fresh(
    source_file_with_cache_version_factory, db_conn, monkeypatch
):
    monkeypatch.setattr(cache, "CACHE_VERSION", 19991231)
    source_file_with_cache_version_factory(19991231)
    result = list_source_files_stale_cache(db_conn)
    assert result == []


def test_list_source_files_stale_cache_newer(
    source_file_with_cache_version_factory, db_conn, monkeypatch
):
    monkeypatch.setattr(cache, "CACHE_VERSION", 19991231)
    source_file_with_cache_version_factory(19991232)
    result = list_source_files_stale_cache(db_conn)
    assert result == []
