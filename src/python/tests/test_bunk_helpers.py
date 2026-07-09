from pathlib import Path
import pytest

from helpers import upsert_dummy_activity

from bunkalunk.bunk_helpers import validate_path_registration, compute_fingerprint
from bunkalunk.db.source_files import DecodeState, SourceFile
from bunkalunk.db.source_files import upsert_source_file


@pytest.fixture(scope="function")
def registered_source_files_table(db_conn, tmp_path, fake_fit_path):
    """Setup a source_files table with a valid registered row."""

    with open(fake_fit_path, "rb") as f:
        content_fingerprint = compute_fingerprint(f)

    source_file = SourceFile(
        source_path=str(fake_fit_path),
        content_fingerprint=content_fingerprint,
        decode_state=DecodeState.PENDING,
        decode_error=None,
    )

    upsert_dummy_activity(db_conn, source_file.content_fingerprint)
    upsert_source_file(db_conn, source_file)
    db_conn.commit()
    return source_file


@pytest.fixture(scope="function")
def source_files_table_bad_fingerprint(db_conn, tmp_path, fake_fit_path):
    """Setup a source_files table with a valid registered row."""
    content_fingerprint = "not-a-real-fingerprint"

    source_file = SourceFile(
        source_path=str(fake_fit_path),
        content_fingerprint=content_fingerprint,
        decode_state=DecodeState.PENDING,
        decode_error=None,
    )
    upsert_dummy_activity(db_conn, source_file.content_fingerprint)
    upsert_source_file(db_conn, source_file)
    db_conn.commit()
    return source_file


def test_validate_path_registration_not_in_database(
    db_conn,
    registered_source_files_table,
):
    source_path = Path("nonexistent-file.fit")
    assert validate_path_registration(db_conn, source_path) is None


def test_validate_path_registration_not_on_disk(
    db_conn,
    registered_source_files_table,
    tmp_path,
):
    source_path = tmp_path / "file.fit"
    source_path.unlink()
    assert not validate_path_registration(db_conn, source_path)


def test_validate_path_registration_fingerprint_mismatch(
    db_conn,
    source_files_table_bad_fingerprint,
    tmp_path,
):
    source_path = tmp_path / "file.fit"
    assert not validate_path_registration(db_conn, source_path)


def test_validate_path_registration_valid(
    db_conn,
    registered_source_files_table,
    tmp_path,
):
    source_path = tmp_path / "file.fit"
    assert validate_path_registration(db_conn, source_path)
