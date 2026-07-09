from pathlib import Path

import pytest
import shutil
from bunkalunk.bunk_helpers import compute_fingerprint
from bunkalunk.db.connections import create_connection


_FIT_DIR = Path(__file__).parent / "fits"


@pytest.fixture(scope="function")
def fake_fit_path(tmp_path):
    source_path = tmp_path / "file.fit"
    source_path.write_bytes(b"This is not a real FIT file")
    return source_path


@pytest.fixture
def fit_path(tmp_path):
    filename = "12759714943_ACTIVITY.fit"
    fit_path = tmp_path / filename
    shutil.copy(_FIT_DIR / filename, fit_path)
    return fit_path


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
