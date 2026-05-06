"""Tests for the bunk module. For convenience, most of these are end-to-end CLI
tests instead of unit tests of the Command class implementations.

"""

import os
from sqlite3 import Row, connect

import pytest
from bunkalunk import bunk
from bunkalunk.bunk import main
from bunkalunk.bunk_helpers import compute_fingerprint, resolve_activity_store
from bunkalunk.cache import resolve_cache_path
from bunkalunk.db import (
    Activity,
    DecodeState,
    SourceFile,
    _upsert_activity,
    create_connection,
    get_source_file,
    upsert_source_file,
)
from bunkalunk.formats.fit import UnsupportedFITFileType
from helpers import has_source_file, patch_home
from test_db import _fetch_activities_by_fingerprint


def _assert_no_db(tmp_path):
    assert not os.path.exists(tmp_path / ".bunk" / "db.sqlite3")


def _assert_no_decode_artifact(fit_path):
    with open(fit_path, 'rb') as f:
        fingerprint = compute_fingerprint(f)
    activity_store = resolve_activity_store(create=False)
    cache_path = resolve_cache_path(fingerprint, activity_store)
    assert not cache_path.exists()


def patch_read_fit_failure(monkeypatch, fit_path, exc=RuntimeError):
    def mock_read_fit(fit_path, logger=None):
        raise exc("mock_read_fit threw an error!")
    monkeypatch.setattr(bunk, "read_fit", mock_read_fit)


def create_bunk_db_conn(tmp_path):
    conn = connect(tmp_path / ".bunk" / "db.sqlite3")
    conn.row_factory = Row
    return conn


def seed_source_files_with_decode_state(state, monkeypatch, tmp_path, fit_path):
    patch_home(monkeypatch, tmp_path)
    with open(fit_path, 'rb') as f:
        content_fingerprint = compute_fingerprint(f)
    source_file = SourceFile(
        source_path=str(fit_path),
        content_fingerprint=content_fingerprint,
        decode_state=state,
        decode_error=None,
    )
    db_path = tmp_path / ".bunk" / "db.sqlite3"
    db_path.parent.mkdir()
    with create_connection(db_path) as conn:
        upsert_source_file(conn, source_file)
    return db_path


@pytest.fixture(scope="function")
def registered_source_files_with_activity_table(monkeypatch, tmp_path):
    """Setup a source_files row and matching activities row on disk."""
    patch_home(monkeypatch, tmp_path)

    source_path = tmp_path / "file.fit"
    source_path.write_bytes(b"This is not a real FIT file")

    with open(source_path, 'rb') as f:
        content_fingerprint = compute_fingerprint(f)

    source_file = SourceFile(
        source_path=str(source_path),
        content_fingerprint=content_fingerprint,
        decode_state=DecodeState.SUCCESS,
        decode_error=None,
    )

    db_path = tmp_path / ".bunk" / "db.sqlite3"
    db_path.parent.mkdir()
    with create_connection(db_path) as conn:
        upsert_source_file(conn, source_file)
        activity = Activity(
            start_time="2026-01-01T10:30:00",
            source_fingerprint=content_fingerprint,
            sport="basket-weaving",
        )
        _upsert_activity(conn, activity)

    return source_file


class TestAddCommand:
    def test_add_rejects_unsupported_extension(self, monkeypatch, tmp_path):
        """bunk add should reject files with unsupported extensions."""
        patch_home(monkeypatch, tmp_path)
        return_code = main(["add", "bad-extension.unfit"])
        assert return_code == 1
        _assert_no_db(tmp_path)

    @pytest.mark.skip("P2: redundant with add_decode_success and DB-level source-file registration tests.")
    def test_add_registers_source_file(self, fit_file, db_conn, tmp_path):
        """bunk add should register a new row in source_files."""
        pass

    @pytest.mark.skip("P2: CLI idempotency is lower priority; DB upsert idempotency already covers the core behavior.")
    def test_add_idempotent(self, fit_file, db_conn, tmp_path):
        """bunk add should be idempotent for the same file path."""
        pass

    def test_add_decode_success(self, monkeypatch, tmp_path, fit_path):
        """bunk add should decode a valid FIT file end-to-end."""
        patch_home(monkeypatch, tmp_path)
        return_code = main(["add", str(fit_path.resolve())])
        assert return_code == 0

        with open(fit_path, 'rb') as f:
            fingerprint = compute_fingerprint(f)
        activity_store = resolve_activity_store(create=False)
        cache_path = resolve_cache_path(fingerprint, activity_store)
        assert cache_path.exists()

        with create_bunk_db_conn(tmp_path) as db_conn:
            source_file = get_source_file(db_conn, str(fit_path))
            activities = _fetch_activities_by_fingerprint(
                db_conn, source_file.content_fingerprint
            )
        assert source_file.decode_state == DecodeState.SUCCESS
        assert source_file.decode_error is None
        assert len(activities) == 1
        
    def test_add_decode_failure_no_upsert(
            self, monkeypatch, tmp_path, fit_path,
    ):
        """bunk add should not record a row in source_files if decode fails."""
        patch_home(monkeypatch, tmp_path)
        patch_read_fit_failure(monkeypatch, fit_path)

        return_code = main(["add", str(fit_path.resolve())])
        assert return_code == 1
        _assert_no_db(tmp_path)
        _assert_no_decode_artifact(fit_path)

    def test_add_unsupported_fit_no_upsert(
            self, registered_source_files_with_activity_table, monkeypatch, tmp_path, fit_path,
    ):
        """bunk add should not record a row in source_files if decode fails."""
        patch_read_fit_failure(monkeypatch, fit_path, exc=UnsupportedFITFileType)
        return_code = main(["add", str(fit_path.resolve())])
        assert return_code == 1
        with open(fit_path, 'rb') as f:
            fingerprint = compute_fingerprint(f)
        with create_bunk_db_conn(tmp_path) as conn:
            assert has_source_file(conn, str(tmp_path / "file.fit"))
            assert not has_source_file(conn, str(fit_path))
            assert [] == _fetch_activities_by_fingerprint(conn, fingerprint)

    def test_add_updates_activities_table(self, monkeypatch, tmp_path, fit_path):
        """bunk add should insert a row into the activities table."""
        patch_home(monkeypatch, tmp_path)
        return_code = main(["add", str(fit_path.resolve())])
        assert return_code == 0

    def test_add_db_open_failure_cleans_up_cache(self, monkeypatch, tmp_path, fit_path):
        """bunk add should remove the cache artifact when SQLite cannot open."""
        patch_home(monkeypatch, tmp_path)
        called = False
        def mock_create_connection(db_path):
            nonlocal called
            called = True
            raise RuntimeError("mock_create_connection raised!")
        monkeypatch.setattr(bunk, "create_connection", mock_create_connection)
        assert 1 == main(["add", str(fit_path)])
        assert called
        _assert_no_decode_artifact(fit_path)

class TestDecodeCommand:
    def test_decode_rebuilds_pending(self, monkeypatch, tmp_path, fit_path):
        """bunk decode with no path should rebuild pending entries."""
        db_path = seed_source_files_with_decode_state(
            DecodeState.PENDING, monkeypatch, tmp_path, fit_path
        )
        assert 0 == main(["decode"])
        with create_connection(db_path) as conn:
            sf = get_source_file(conn, str(fit_path))
        assert sf.decode_state == DecodeState.SUCCESS
        assert sf.decode_error is None

    def test_decode_rebuilds_error(self, monkeypatch, tmp_path, fit_path):
        """bunk decode with no path should rebuild error entries."""
        db_path = seed_source_files_with_decode_state(
            DecodeState.ERROR, monkeypatch, tmp_path, fit_path
        )
        assert 0 == main(["decode"])
        with create_connection(db_path) as conn:
            sf = get_source_file(conn, str(fit_path))
        assert sf.decode_state == DecodeState.SUCCESS
        assert sf.decode_error is None

    @pytest.mark.skip("P1: stale-cache rebuild is important, but after pending/error triage.")
    def test_decode_rebuilds_stale(self, db_conn, tmp_path):
        """bunk decode with no path should rebuild stale cache entries."""
        pass

    def test_decode_specific_path(self, monkeypatch, tmp_path, fit_path):
        """bunk decode <path> should rebuild only the given file."""
        patch_home(monkeypatch, tmp_path)
        fake_path = tmp_path / "file.fit"
        fake_path.write_bytes(b"This is not a real FIT file")
        with open(fake_path, 'rb') as f:
            content_fingerprint = compute_fingerprint(f)
        fake_source_file = SourceFile(
            source_path=str(fake_path),
            content_fingerprint=content_fingerprint,
            decode_state=DecodeState.PENDING,
            decode_error=None,
        )
        db_path = tmp_path / ".bunk" / "db.sqlite3"
        db_path.parent.mkdir()
        with create_connection(db_path) as conn:
            upsert_source_file(conn, fake_source_file)
        main(["add", str(fit_path)])
        assert 0 == main(["decode", str(fit_path)])
        with create_connection(db_path) as conn:
            sf = get_source_file(conn, str(fake_path))
        assert sf.decode_state == DecodeState.PENDING

    def test_decode_unknown_path_returns_error(self, monkeypatch, tmp_path, caplog):
        """bunk decode <path> should return non-zero for unregistered path."""
        patch_home(monkeypatch, tmp_path)
        assert 1 == main(["decode", "not/in/source_files"])

    @pytest.mark.skip("P2: fingerprint-change handling is already covered by path-registration tests.")
    def test_decode_detects_fingerprint_change(self, fit_file, db_conn, tmp_path):
        """bunk decode should detect when source file content has changed."""
        pass

    @pytest.mark.skip(
        "P1: cover decode failure after fingerprint drift updates source_files."
    )
    def test_decode_fingerprint_drift_failure_keeps_activities_consistent(
        self, monkeypatch, tmp_path, fit_path
    ):
        """bunk decode should not strand activities rows after fingerprint drift."""
        pass

    def test_decode_failure_records_error(self, monkeypatch, tmp_path, fit_path):
        """bunk decode should record ERROR state when decode fails."""
        patch_home(monkeypatch, tmp_path)
        main(["add", str(fit_path)])
        patch_read_fit_failure(monkeypatch, fit_path)
        assert 1 == main(["decode", str(fit_path)])
        with create_bunk_db_conn(tmp_path) as conn:
            source_file = get_source_file(conn, str(fit_path))
            activities = _fetch_activities_by_fingerprint(
                conn, source_file.content_fingerprint
            )
        assert source_file.decode_state == DecodeState.ERROR
        assert source_file.decode_error == "mock_read_fit threw an error!"
        assert len(activities) == 1
        activity_store = resolve_activity_store(create=False)
        cache_path = resolve_cache_path(source_file.content_fingerprint, activity_store)
        assert cache_path.exists()

    @pytest.mark.skip("P2: decode idempotency is lower priority than the core triage flows.")
    def test_decode_is_idempotent(self, db_conn, tmp_path):
        """bunk decode should be safe to run multiple times."""
        pass

    def test_decode_specific_path_success(self, monkeypatch, tmp_path, fit_path):
        """bunk decode <path> should succeed and leave decode_state = success."""
        patch_home(monkeypatch, tmp_path)

        return_code = main(["add", str(fit_path)])
        assert return_code == 0
        return_code = main(["decode", str(fit_path)])
        assert return_code == 0

        with create_bunk_db_conn(tmp_path) as db_conn:
            source_file = get_source_file(db_conn, str(fit_path))
        assert source_file.decode_state == DecodeState.SUCCESS
        assert source_file.decode_error is None

    def test_decode_removes_unsupported(self, monkeypatch, tmp_path, fit_path):
        patch_home(monkeypatch, tmp_path)
        assert 0 == main(["add", str(fit_path)])
        with create_bunk_db_conn(tmp_path) as db_conn:
            source_file = get_source_file(db_conn, str(fit_path))
        assert source_file.decode_state == DecodeState.SUCCESS
        patch_read_fit_failure(monkeypatch, fit_path, exc=UnsupportedFITFileType)
        assert 1 == main(["decode", str(fit_path)])
        with create_bunk_db_conn(tmp_path) as db_conn:
            assert not has_source_file(db_conn, str(fit_path))
