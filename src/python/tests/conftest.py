from pathlib import Path

import pytest
from bunkalunk.bunk_helpers import compute_fingerprint
from bunkalunk.db import DecodeState, SourceFile, create_connection, upsert_source_file
from sqlite3 import connect, Row


_FIT_DIR = Path(__file__).parent / "fits"


@pytest.fixture(scope="function")
def fake_fit_path(tmp_path):
    source_path = tmp_path / "file.fit"
    source_path.write_bytes(b"This is not a real FIT file")
    return source_path


@pytest.fixture
def fit_path():
    return _FIT_DIR / "12759714943_ACTIVITY.fit"


@pytest.fixture
def fit_path_fingerprint(fit_path):
    with open(fit_path, "rb") as f:
        fingerprint = compute_fingerprint(f)
    return fingerprint


@pytest.fixture(scope="function")
def db_conn():
    conn = create_connection(":memory:")
    yield conn
    conn.close()
