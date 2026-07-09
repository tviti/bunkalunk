"""Tests for the bunk module. For convenience, most of these are end-to-end CLI
tests instead of unit tests of the Command class implementations.

"""

import os
import shutil
from sqlite3 import connect, Row

import h5py
import pytest
from bunkalunk import cache
from bunkalunk import bunk
from bunkalunk.bunk import main
from bunkalunk.bunk_helpers import compute_fingerprint, resolve_activity_store
from bunkalunk.cache import resolve_cache_path
from bunkalunk.db.activities import Activity, _upsert_activity
from bunkalunk.db.connections import create_connection
from bunkalunk.db.source_files import (
    DecodeState,
    SourceFile,
    get_source_file,
    upsert_source_file,
)
from bunkalunk.formats.fit import UnsupportedFITFileType
from helpers import has_source_file, upsert_dummy_activity
from test_db import _fetch_activities_by_fingerprint


def change_fingerprint_inplace(file_path):
    """Duplicate file data in-place to simulate fingerprint drift.

    Note that if this is used on FIT files, the current FIT decoder
    implementation will return an identical FitData object for the file, since
    it stops processing at the first encountered file boundary.

    """
    file_bytes = file_path.read_bytes()
    file_path.write_bytes(file_bytes + file_bytes)
    with open(file_path, "rb") as f:
        new_fingerprint = compute_fingerprint(f)
    return new_fingerprint


@pytest.fixture(scope="function")
def tmp_db_path(tmp_path):
    db_path = tmp_path / ".bunk" / "db.sqlite3"
    if not db_path.parent.exists():
        db_path.parent.mkdir()
    return db_path


@pytest.fixture(autouse=True)
def patched_home(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path.resolve()))
    monkeypatch.setenv("BUNK_HOME", str(tmp_path.resolve() / ".bunk"))


@pytest.fixture(scope="function")
def tmp_db_conn(tmp_db_path):
    """Fresh connection, no tables.

    If your fixture needs tables, it should instead call create_connection on
    tmb_db_path.

    """
    conn = connect(tmp_db_path)
    conn.row_factory = Row
    yield conn
    conn.close


def _assert_no_decode_artifact(fit_path):
    with open(fit_path, "rb") as f:
        fingerprint = compute_fingerprint(f)
    activity_store = resolve_activity_store(create=False)
    cache_path = resolve_cache_path(fingerprint, activity_store)
    assert not cache_path.exists()


def patch_read_fit_failure(monkeypatch, fit_path, exc=RuntimeError):
    def mock_read_fit(fit_path, logger=None):
        raise exc("mock_read_fit threw an error!")

    monkeypatch.setattr(bunk, "read_fit", mock_read_fit)


def seed_source_files_with_decode_state(db_path, fit_path, state):
    with open(fit_path, "rb") as f:
        content_fingerprint = compute_fingerprint(f)
    source_file = SourceFile(
        source_path=str(fit_path),
        content_fingerprint=content_fingerprint,
        decode_state=state,
        decode_error=None,
    )
    with create_connection(db_path) as conn:
        upsert_dummy_activity(conn, source_file.content_fingerprint)
        upsert_source_file(conn, source_file)
    return db_path


@pytest.fixture(scope="function")
def registered_source_files_and_activities(
    monkeypatch, fit_path, fit_path_fingerprint, tmp_db_path
):
    source_file = SourceFile(
        source_path=str(fit_path),
        content_fingerprint=fit_path_fingerprint,
        decode_state=DecodeState.SUCCESS,
        decode_error=None,
    )
    activity = Activity(
        start_time=1767263400.0,
        source_fingerprint=fit_path_fingerprint,
        sport="basket-weaving",
    )
    with create_connection(tmp_db_path) as conn:
        _upsert_activity(conn, activity)
        upsert_source_file(conn, source_file)
    return tmp_db_path


@pytest.fixture(scope="function")
def registered_source_files_and_activities_with_pinned_cache_version(
    monkeypatch, fit_path, patched_home, tmp_db_path
):
    monkeypatch.setattr(cache, "CACHE_VERSION", 19991201)

    with open(fit_path, "rb") as f:
        content_fingerprint = compute_fingerprint(f)

    source_file = SourceFile(
        source_path=str(fit_path),
        content_fingerprint=content_fingerprint,
        decode_state=DecodeState.SUCCESS,
        decode_error=None,
    )
    activity = Activity(
        start_time=1767263400.0,
        source_fingerprint=content_fingerprint,
        sport="basket-weaving",
    )
    with create_connection(tmp_db_path) as conn:
        _upsert_activity(conn, activity)
        upsert_source_file(conn, source_file)
    return tmp_db_path


@pytest.fixture(scope="function")
def registered_source_files_with_activity_table(
    patched_home, tmp_db_path, fake_fit_path
):

    with open(fake_fit_path, "rb") as f:
        content_fingerprint = compute_fingerprint(f)

    source_file = SourceFile(
        source_path=str(fake_fit_path),
        content_fingerprint=content_fingerprint,
        decode_state=DecodeState.SUCCESS,
        decode_error=None,
    )

    with create_connection(tmp_db_path) as conn:
        upsert_dummy_activity(conn, content_fingerprint)
        upsert_source_file(conn, source_file)
        activity = Activity(
            start_time=1767263400.0,
            source_fingerprint=content_fingerprint,
            sport="basket-weaving",
        )
        _upsert_activity(conn, activity)

    return source_file


class TestAddCommand:
    def test_add_rejects_unsupported_extension(
        self, patched_home, monkeypatch, tmp_path, tmp_db_path
    ):
        """bunk add should reject files with unsupported extensions."""
        bad_path = tmp_path / "bad-extension.unfit"
        bad_path.write_bytes(b"not a fit file")
        return_code = main(["add", str(bad_path)])
        assert return_code == 1
        with connect(tmp_db_path) as conn:
            assert get_source_file(conn, str(bad_path)) is None

    def test_add_decode_success(self, patched_home, fit_path, tmp_db_conn):
        """bunk add should decode a valid FIT file end-to-end."""
        return_code = main(["add", str(fit_path.resolve())])
        assert return_code == 0

        with open(fit_path, "rb") as f:
            fingerprint = compute_fingerprint(f)
        activity_store = resolve_activity_store(create=False)
        cache_path = resolve_cache_path(fingerprint, activity_store)
        assert cache_path.exists()

        source_file = get_source_file(tmp_db_conn, str(fit_path))
        activities = _fetch_activities_by_fingerprint(
            tmp_db_conn, source_file.content_fingerprint
        )
        assert source_file.decode_state == DecodeState.SUCCESS
        assert source_file.decode_error is None
        assert len(activities) == 1

    def test_add_decode_failure_no_upsert(
        self, patched_home, monkeypatch, tmp_path, fit_path, tmp_db_path
    ):
        """bunk add should not record a row in source_files if decode fails."""
        patch_read_fit_failure(monkeypatch, fit_path)
        source_path = str(fit_path.resolve())
        return_code = main(["add", source_path])
        assert return_code == 1
        with connect(tmp_db_path) as conn:
            source_file = get_source_file(conn, source_path)
        assert source_file is None
        _assert_no_decode_artifact(fit_path)

    def test_add_db_failure_after_activity_write_rolls_back(
        self, patched_home, monkeypatch, fit_path, fit_path_fingerprint, tmp_db_path
    ):
        """A late DB write failure should roll back DB state and new cache."""
        called = False

        def mock_record_decode_outcome(conn, source_path, *, state, error=None):
            nonlocal called
            called = True
            raise RuntimeError("mock late DB failure")

        monkeypatch.setattr(bunk, "record_decode_outcome", mock_record_decode_outcome)

        source_path = str(fit_path.resolve())
        return_code = main(["add", source_path])
        assert return_code == 1
        assert called
        with connect(tmp_db_path) as conn:
            source_file = get_source_file(conn, source_path)
            activities = _fetch_activities_by_fingerprint(conn, fit_path_fingerprint)
        assert source_file is None
        assert activities == []
        _assert_no_decode_artifact(fit_path)

    def test_add_unsupported_fit_no_upsert(
        self,
        registered_source_files_with_activity_table,
        monkeypatch,
        tmp_path,
        fit_path,
        fit_path_fingerprint,
        tmp_db_path,
    ):
        """bunk add should not record a row in source_files if decode fails."""
        patch_read_fit_failure(monkeypatch, fit_path, exc=UnsupportedFITFileType)
        return_code = main(["add", str(fit_path.resolve())])
        assert return_code == 1
        with connect(tmp_db_path) as conn:
            assert has_source_file(conn, str(tmp_path / "file.fit"))
            assert not has_source_file(conn, str(fit_path))
            assert [] == _fetch_activities_by_fingerprint(conn, fit_path_fingerprint)

    def test_add_updates_activities_table(self, patched_home, tmp_path, fit_path):
        """bunk add should insert a row into the activities table."""
        return_code = main(["add", str(fit_path.resolve())])
        assert return_code == 0

    def test_add_db_open_failure_cleans_up_cache(
        self, patched_home, monkeypatch, fit_path
    ):
        """bunk add should remove the cache artifact when SQLite cannot open."""
        called = False

        def mock_create_connection(db_path):
            nonlocal called
            called = True
            raise RuntimeError("mock_create_connection raised!")

        monkeypatch.setattr(bunk, "create_connection", mock_create_connection)
        assert 1 == main(["add", str(fit_path)])
        assert called
        _assert_no_decode_artifact(fit_path)

    def test_add_multiple_files_late_failure_keeps_prior_commit(
        self,
        patched_home,
        monkeypatch,
        tmp_path,
        fit_path,
        tmp_db_path,
        tmp_db_conn,
    ):
        """A later add failure should not roll back an earlier committed operand."""
        first_path = tmp_path / "first.fit"
        fit_bytes = fit_path.read_bytes()
        first_path.write_bytes(fit_bytes)

        # Fudge a new fingerprint by stacking FIT data streams
        second_path = tmp_path / "second.fit"
        second_path.write_bytes(fit_bytes + fit_bytes)

        original_record_decode_outcome = bunk.record_decode_outcome
        success_calls = 0

        def mock_record_decode_outcome(conn, source_path, *, state, error=None):
            nonlocal success_calls
            if state is DecodeState.SUCCESS:
                success_calls += 1
                if success_calls == 2:
                    raise RuntimeError("mock late DB failure")

            return original_record_decode_outcome(
                conn, source_path, state=state, error=error
            )

        monkeypatch.setattr(bunk, "record_decode_outcome", mock_record_decode_outcome)

        return_code = main(["add", str(first_path), str(second_path)])
        assert return_code == 1
        assert success_calls == 2

        with open(first_path, "rb") as f:
            first_fingerprint = compute_fingerprint(f)
        with open(second_path, "rb") as f:
            second_fingerprint = compute_fingerprint(f)

        activity_store = resolve_activity_store(create=False)
        first_cache_path = resolve_cache_path(first_fingerprint, activity_store)
        second_cache_path = resolve_cache_path(second_fingerprint, activity_store)

        first_source_file = get_source_file(tmp_db_conn, str(first_path))
        second_source_file = get_source_file(tmp_db_conn, str(second_path))
        first_activities = _fetch_activities_by_fingerprint(
            tmp_db_conn, first_fingerprint
        )
        second_activities = _fetch_activities_by_fingerprint(
            tmp_db_conn, second_fingerprint
        )

        assert first_source_file.decode_state == DecodeState.SUCCESS
        assert first_source_file.decode_error is None
        assert second_source_file is None
        assert len(first_activities) == 1
        assert second_activities == []
        assert first_cache_path.exists()
        assert not second_cache_path.exists()

    def test_add_multiple_files_accepted_extensions(self, patched_home, monkeypatch):
        num_calls = 0

        def mock_add_file(self, conn, source_path, logger, ctx):
            nonlocal num_calls
            num_calls += 1
            return 0

        monkeypatch.setattr(bunk.AddCommand, "_add_file", mock_add_file)
        assert 0 == main(["add", "a.fit", "b.fit", "c.fit", "d.fit"])
        assert num_calls == 4

    def test_add_multiple_files_some_bad_extensions(self, patched_home, monkeypatch):
        num_calls = 0
        accepted_files = []

        def mock_add_file(self, conn, source_path, logger, ctx):
            nonlocal num_calls
            nonlocal accepted_files
            num_calls += 1
            accepted_files.append(os.path.basename(source_path))
            return 0

        monkeypatch.setattr(bunk.AddCommand, "_add_file", mock_add_file)
        assert 1 == main(["add", "a.fit", "b.unfit", "c.fit", "d.unfit"])
        assert num_calls == 2
        assert accepted_files == ["a.fit", "c.fit"]


class TestDecodeCommand:
    def test_decode_rebuilds_pending(self, patched_home, fit_path, tmp_db_path):
        """bunk decode with no path should rebuild pending entries."""
        seed_source_files_with_decode_state(tmp_db_path, fit_path, DecodeState.PENDING)
        assert 0 == main(["decode"])
        with create_connection(tmp_db_path) as conn:
            sf = get_source_file(conn, str(fit_path))
        assert sf.decode_state == DecodeState.SUCCESS
        assert sf.decode_error is None

    def test_decode_rebuilds_error(self, patched_home, fit_path, tmp_db_path):
        """bunk decode with no path should rebuild error entries."""
        seed_source_files_with_decode_state(tmp_db_path, fit_path, DecodeState.ERROR)
        assert 0 == main(["decode"])
        with create_connection(tmp_db_path) as conn:
            sf = get_source_file(conn, str(fit_path))
        assert sf.decode_state == DecodeState.SUCCESS
        assert sf.decode_error is None

    def test_decode_rebuilds_stale(
        self,
        monkeypatch,
        patched_home,
        fit_path,
        fit_path_fingerprint,
        tmp_db_path,
        registered_source_files_and_activities_with_pinned_cache_version,
    ):
        """bunk decode with no path should rebuild stale cache entries."""
        registered_source_files_and_activities_with_pinned_cache_version

        # Re-patch the cache version to trigger re-decode
        monkeypatch.setattr(cache, "CACHE_VERSION", 19991231)
        assert 0 == main(["decode"])

        with create_connection(tmp_db_path) as conn:
            activities = _fetch_activities_by_fingerprint(conn, fit_path_fingerprint)
        assert len(activities) == 1
        assert activities[0]["cache_version"] == 19991231

        activity_store = resolve_activity_store(create=False)
        cache_path = resolve_cache_path(fit_path_fingerprint, activity_store)
        assert cache_path.exists()
        with h5py.File(cache_path, "r") as cache_file:
            assert cache_file.attrs["cache_version"] == 19991231

    def test_decode_rebuilds_missing(
        self, patched_home, registered_source_files_and_activities, fit_path
    ):
        with open(fit_path, "rb") as f:
            content_fingerprint = compute_fingerprint(f)
        activity_store = resolve_activity_store(create=False)
        cache_path = resolve_cache_path(content_fingerprint, activity_store)
        assert not os.path.exists(cache_path)
        assert main(["decode"]) == 0
        assert os.path.exists(cache_path)

    def test_decode_specific_path(
        self, patched_home, tmp_path, fit_path, fake_fit_path, tmp_db_path
    ):
        """bunk decode <path> should rebuild only the given file."""
        with open(fake_fit_path, "rb") as f:
            content_fingerprint = compute_fingerprint(f)
        fake_source_file = SourceFile(
            source_path=str(fake_fit_path),
            content_fingerprint=content_fingerprint,
            decode_state=DecodeState.PENDING,
            decode_error=None,
        )
        with create_connection(tmp_db_path) as conn:
            upsert_dummy_activity(conn, content_fingerprint)
            upsert_source_file(conn, fake_source_file)
        main(["add", str(fit_path)])
        assert 0 == main(["decode", str(fit_path)])
        with create_connection(tmp_db_path) as conn:
            sf = get_source_file(conn, str(fake_fit_path))
        assert sf.decode_state == DecodeState.PENDING

    def test_decode_unknown_path_returns_error(self, patched_home, caplog):
        """bunk decode <path> should return non-zero for unregistered path."""
        assert 1 == main(["decode", "not/in/source_files"])

    def test_decode_fingerprint_drift_drops_old_row(
        self, tmp_db_path, fit_path, fit_path_fingerprint
    ):
        """bunk decode should not strand activities rows after fingerprint drift."""
        assert main(["add", str(fit_path)]) == 0
        # Concatenate the file with itself to spoof a fingerprint change
        new_fingerprint = change_fingerprint_inplace(fit_path)
        assert main(["decode", str(fit_path)]) == 0
        with create_connection(tmp_db_path) as conn:
            assert _fetch_activities_by_fingerprint(conn, fit_path_fingerprint) == []
            activities = _fetch_activities_by_fingerprint(conn, new_fingerprint)
            assert len(activities) == 1
            assert activities[0]["source_fingerprint"] == new_fingerprint
            result = conn.execute(
                "SELECT * FROM source_files WHERE content_fingerprint = ?",
                (new_fingerprint,),
            )
            rows = result.fetchall()
            assert len(rows) == 1
            assert rows[0]["content_fingerprint"] == new_fingerprint

    def test_decode_fingerprint_drift_leaves_old_row_when_still_referenced(
        self, tmp_path, tmp_db_path, fit_path, fit_path_fingerprint
    ):
        assert main(["add", str(fit_path)]) == 0
        alias_path = tmp_path / "alias.fit"
        shutil.copy(fit_path, alias_path)
        assert main(["add", str(alias_path)]) == 0
        # Verify only one cache entry was made
        with create_connection(tmp_db_path) as conn:
            results = conn.execute("SELECT * FROM activities")
            activities = results.fetchall()
            assert len(activities) == 1
            assert activities[0]["source_fingerprint"] == fit_path_fingerprint
        # Concatenate the file with itself to spoof a fingerprint change
        new_fingerprint = change_fingerprint_inplace(fit_path)
        assert main(["decode", str(fit_path)]) == 0
        with create_connection(tmp_db_path) as conn:
            results = conn.execute("SELECT * FROM activities")
            activities = results.fetchall()
            assert len(activities) == 2
            fingerprints = [a["source_fingerprint"] for a in activities]
            assert fit_path_fingerprint in fingerprints
            assert new_fingerprint in fingerprints

    def test_decode_fingerprint_drift_read_failure_leaves_old_activities_row(
        self, tmp_db_path, monkeypatch, tmp_path, fit_path, fit_path_fingerprint
    ):
        assert main(["add", str(fit_path)]) == 0
        # Concatenate the file with itself to spoof a fingerprint change
        new_fingerprint = change_fingerprint_inplace(fit_path)
        patch_read_fit_failure(monkeypatch, fit_path)
        assert main(["decode", str(fit_path)]) == 1
        with create_connection(tmp_db_path) as conn:
            activities = _fetch_activities_by_fingerprint(conn, fit_path_fingerprint)
            assert len(activities) == 1
            assert activities[0]["source_fingerprint"] == fit_path_fingerprint
            result = conn.execute("SELECT * FROM source_files")
            rows = result.fetchall()
            assert len(rows) == 1
            source_file = SourceFile(**rows[0])
            assert source_file.content_fingerprint == fit_path_fingerprint
            assert source_file.decode_state == DecodeState.ERROR
            assert source_file.decode_error == "mock_read_fit threw an error!"
            # New fingerprint doesn't exist
            assert _fetch_activities_by_fingerprint(conn, new_fingerprint) == []

    def test_decode_failure_records_error(
        self, patched_home, monkeypatch, fit_path, tmp_db_conn
    ):
        """bunk decode should record ERROR state when decode fails."""
        main(["add", str(fit_path)])
        patch_read_fit_failure(monkeypatch, fit_path)
        assert main(["decode", str(fit_path)]) == 1
        source_file = get_source_file(tmp_db_conn, str(fit_path))
        activities = _fetch_activities_by_fingerprint(
            tmp_db_conn, source_file.content_fingerprint
        )
        assert source_file.decode_state == DecodeState.ERROR
        assert source_file.decode_error == "mock_read_fit threw an error!"
        assert len(activities) == 1
        activity_store = resolve_activity_store(create=False)
        cache_path = resolve_cache_path(source_file.content_fingerprint, activity_store)
        assert cache_path.exists()

    def test_decode_specific_path_success(self, patched_home, fit_path, tmp_db_conn):
        """bunk decode <path> should succeed and leave decode_state = success."""

        return_code = main(["add", str(fit_path)])
        assert return_code == 0
        return_code = main(["decode", str(fit_path)])
        assert return_code == 0

        source_file = get_source_file(tmp_db_conn, str(fit_path))
        assert source_file.decode_state == DecodeState.SUCCESS
        assert source_file.decode_error is None

    def test_decode_removes_unsupported(
        self, patched_home, monkeypatch, fit_path, tmp_db_conn
    ):
        assert 0 == main(["add", str(fit_path)])
        source_file = get_source_file(tmp_db_conn, str(fit_path))
        assert source_file.decode_state == DecodeState.SUCCESS
        patch_read_fit_failure(monkeypatch, fit_path, exc=UnsupportedFITFileType)
        assert 1 == main(["decode", str(fit_path)])
        assert not has_source_file(tmp_db_conn, str(fit_path))
