from pathlib import Path

from bunkalunk.bunk_helpers import validate_path_registration


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
