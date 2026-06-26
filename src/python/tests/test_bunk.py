"""Tests for the bunk module. For convenience, most of these are end-to-end CLI
tests instead of unit tests of the Command class implementations.

"""

import os
from sqlite3 import Row, connect

import h5py
import pytest
from bunkalunk import cache
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
    with open(fit_path, "rb") as f:
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
    with open(fit_path, "rb") as f:
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
def registered_source_files_and_activities(monkeypatch, tmp_path, fit_path):
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
    db_path = tmp_path / ".bunk" / "db.sqlite3"
    db_path.parent.mkdir()
    with create_connection(db_path) as conn:
        upsert_source_file(conn, source_file)
        _upsert_activity(conn, activity)
    return db_path


@pytest.fixture(scope="function")
def registered_source_files_and_activities_with_pinned_cache_version(
    monkeypatch, tmp_path, fit_path
):
    patch_home(monkeypatch, tmp_path)
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
    db_path = tmp_path / ".bunk" / "db.sqlite3"
    db_path.parent.mkdir()
    with create_connection(db_path) as conn:
        upsert_source_file(conn, source_file)
        _upsert_activity(conn, activity)
    return db_path


@pytest.fixture(scope="function")
def registered_source_files_with_activity_table(monkeypatch, tmp_path):
    """Setup a source_files row and matching activities row on disk."""
    patch_home(monkeypatch, tmp_path)

    source_path = tmp_path / "file.fit"
    source_path.write_bytes(b"This is not a real FIT file")

    with open(source_path, "rb") as f:
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
            start_time=1767263400.0,
            source_fingerprint=content_fingerprint,
            sport="basket-weaving",
        )
        _upsert_activity(conn, activity)

    return source_file


class TestAddCommand:
    def test_add_rejects_unsupported_extension(self, monkeypatch, tmp_path):
        """bunk add should reject files with unsupported extensions."""
        patch_home(monkeypatch, tmp_path)
        bad_path = tmp_path / "bad-extension.unfit"
        bad_path.write_bytes(b"not a fit file")
        return_code = main(["add", str(bad_path)])
        assert return_code == 1
        with create_bunk_db_conn(tmp_path) as conn:
            assert get_source_file(conn, str(bad_path)) is None

    def test_add_decode_success(self, monkeypatch, tmp_path, fit_path):
        """bunk add should decode a valid FIT file end-to-end."""
        patch_home(monkeypatch, tmp_path)
        return_code = main(["add", str(fit_path.resolve())])
        assert return_code == 0

        with open(fit_path, "rb") as f:
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
        self,
        monkeypatch,
        tmp_path,
        fit_path,
    ):
        """bunk add should not record a row in source_files if decode fails."""
        patch_home(monkeypatch, tmp_path)
        patch_read_fit_failure(monkeypatch, fit_path)
        source_path = str(fit_path.resolve())
        return_code = main(["add", source_path])
        assert return_code == 1
        with create_bunk_db_conn(tmp_path) as conn:
            source_file = get_source_file(conn, source_path)
        assert source_file is None
        _assert_no_decode_artifact(fit_path)

    def test_add_db_failure_after_activity_write_rolls_back(
        self,
        monkeypatch,
        tmp_path,
        fit_path,
    ):
        """A late DB write failure should roll back DB state and new cache."""
        patch_home(monkeypatch, tmp_path)
        called = False

        def mock_record_decode_outcome(conn, source_path, *, state, error=None):
            nonlocal called
            called = True
            raise RuntimeError("mock late DB failure")

        monkeypatch.setattr(bunk, "record_decode_outcome", mock_record_decode_outcome)

        source_path = str(fit_path.resolve())
        with open(fit_path, "rb") as f:
            fingerprint = compute_fingerprint(f)

        return_code = main(["add", source_path])
        assert return_code == 1
        assert called
        with create_bunk_db_conn(tmp_path) as conn:
            source_file = get_source_file(conn, source_path)
            activities = _fetch_activities_by_fingerprint(conn, fingerprint)
        assert source_file is None
        assert activities == []
        _assert_no_decode_artifact(fit_path)

    def test_add_unsupported_fit_no_upsert(
        self,
        registered_source_files_with_activity_table,
        monkeypatch,
        tmp_path,
        fit_path,
    ):
        """bunk add should not record a row in source_files if decode fails."""
        patch_read_fit_failure(monkeypatch, fit_path, exc=UnsupportedFITFileType)
        return_code = main(["add", str(fit_path.resolve())])
        assert return_code == 1
        with open(fit_path, "rb") as f:
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

    def test_add_multiple_files_late_failure_keeps_prior_commit(
        self, monkeypatch, tmp_path, fit_path
    ):
        """A later add failure should not roll back an earlier committed operand."""
        patch_home(monkeypatch, tmp_path)

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

        with create_bunk_db_conn(tmp_path) as conn:
            first_source_file = get_source_file(conn, str(first_path))
            second_source_file = get_source_file(conn, str(second_path))
            first_activities = _fetch_activities_by_fingerprint(conn, first_fingerprint)
            second_activities = _fetch_activities_by_fingerprint(
                conn, second_fingerprint
            )

        assert first_source_file.decode_state == DecodeState.SUCCESS
        assert first_source_file.decode_error is None
        assert second_source_file is None
        assert len(first_activities) == 1
        assert second_activities == []
        assert first_cache_path.exists()
        assert not second_cache_path.exists()

    def test_add_multiple_files_accepted_extensions(self, monkeypatch, tmp_path):
        patch_home(monkeypatch, tmp_path)
        num_calls = 0

        def mock_add_file(self, conn, source_path, logger, ctx):
            nonlocal num_calls
            num_calls += 1
            return 0

        monkeypatch.setattr(bunk.AddCommand, "_add_file", mock_add_file)
        assert 0 == main(["add", "a.fit", "b.fit", "c.fit", "d.fit"])
        assert num_calls == 4

    def test_add_multiple_files_some_bad_extensions(self, monkeypatch, tmp_path):
        patch_home(monkeypatch, tmp_path)
        num_calls = 0
        accepted_files: list[str] = []

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

    def test_decode_rebuilds_stale(
        self,
        tmp_path,
        monkeypatch,
        fit_path,
        registered_source_files_and_activities_with_pinned_cache_version,
    ):
        """bunk decode with no path should rebuild stale cache entries."""
        monkeypatch.setattr(cache, "CACHE_VERSION", 19991231)
        patch_home(monkeypatch, tmp_path)
        db_path = registered_source_files_and_activities_with_pinned_cache_version
        assert 0 == main(["decode"])

        with open(fit_path, "rb") as f:
            fingerprint = compute_fingerprint(f)

        with create_connection(db_path) as conn:
            activities = _fetch_activities_by_fingerprint(conn, fingerprint)
        assert len(activities) == 1
        assert activities[0]["cache_version"] == 19991231

        activity_store = resolve_activity_store(create=False)
        cache_path = resolve_cache_path(fingerprint, activity_store)
        assert cache_path.exists()
        with h5py.File(cache_path, "r") as cache_file:
            assert cache_file.attrs["cache_version"] == 19991231

    def test_decode_rebuilds_missing(
        self, tmp_path, monkeypatch, registered_source_files_and_activities, fit_path
    ):
        patch_home(monkeypatch, tmp_path)
        with open(fit_path, "rb") as f:
            content_fingerprint = compute_fingerprint(f)
        activity_store = resolve_activity_store(create=False)
        cache_path = resolve_cache_path(content_fingerprint, activity_store)
        assert not os.path.exists(cache_path)
        assert main(["decode"]) == 0
        assert os.path.exists(cache_path)

    def test_decode_specific_path(self, monkeypatch, tmp_path, fit_path):
        """bunk decode <path> should rebuild only the given file."""
        patch_home(monkeypatch, tmp_path)
        fake_path = tmp_path / "file.fit"
        fake_path.write_bytes(b"This is not a real FIT file")
        with open(fake_path, "rb") as f:
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
