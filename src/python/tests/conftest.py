from pathlib import Path

import pytest
from bunkalunk.bunk_helpers import compute_fingerprint
from bunkalunk.db import DecodeState, SourceFile, create_connection, upsert_source_file


_FIT_DIR = Path(__file__).parent / "fits"


@pytest.fixture
def fit_path():
    return _FIT_DIR / "12759714943_ACTIVITY.fit"


@pytest.fixture(scope="function")
def db_conn():
    conn = create_connection(":memory:")
    yield conn
    conn.close()


@pytest.fixture(scope="function")
def source_files_table_bad_fingerprint(db_conn, tmp_path):
    """Setup a source_files table with a valid registered row."""
    source_path = tmp_path / "file.fit"
    source_path.write_bytes(b"This is not a real FIT file")
    content_fingerprint = "not-a-real-fingerprint"

    source_file = SourceFile(
        source_path=str(source_path),
        content_fingerprint=content_fingerprint,
        decode_state=DecodeState.PENDING,
        decode_error=None,
    )
    upsert_source_file(db_conn, source_file)
    db_conn.commit()
    return source_file


@pytest.fixture(scope="function")
def registered_source_files_table(db_conn, tmp_path):
    """Setup a source_files table with a valid registered row."""
    source_path = tmp_path / "file.fit"
    source_path.write_bytes(b"This is not a real FIT file")

    with open(source_path, 'rb') as f:
        content_fingerprint = compute_fingerprint(f)

    source_file = SourceFile(
        source_path=str(source_path),
        content_fingerprint=content_fingerprint,
        decode_state=DecodeState.PENDING,
        decode_error=None,
    )
    upsert_source_file(db_conn, source_file)
    db_conn.commit()
    return source_file


