import h5py
import numpy as np
import pytest
from numpy.testing import assert_equal

from bunkalunk import cache
from bunkalunk.cache import CacheData, write_cache, _write_cache_file, CacheWriteFailure


# TODO: Monkeypatch
_CACHE_VERSION = 19991230


def make_unequal_length_cache_data():
    return CacheData(
        latitude=[1.0, 1.1, 1.2],
        longitude=[2.0, 2.1],
        time=[0.0],
        start_time=1767225600.0,
        sport="yoyo",
    )


def make_cache_data():
    return CacheData(
        latitude=[1.0, 1.1, 1.2],
        longitude=[2.0, 2.1, 2.2],
        time=[0.0, 1.0, 2.0],
        start_time=1767225600.0,
        sport="yoyo",
    )


def test_write_cache(tmp_path, monkeypatch):
    file_path = tmp_path / "test.hdf5"
    data = make_cache_data()

    monkeypatch.setattr(cache, "CACHE_VERSION", _CACHE_VERSION)

    write_cache(file_path, data)

    with h5py.File(file_path, "r") as cache_file:
        assert_equal(cache_file["latitude"][:], [1.0, 1.1, 1.2])
        assert_equal(cache_file["longitude"][:], [2.0, 2.1, 2.2])
        assert_equal(cache_file["time"][:], [0.0, 1.0, 2.0])
        assert_equal(cache_file.attrs["start_time"], 1767225600.0)
        assert cache_file.attrs["cache_version"] == 19991230
        assert cache_file.attrs["sport"] == "yoyo"


def test_write_cache_unequal_length_arrays(tmp_path, monkeypatch):
    file_path = tmp_path / "test.hdf5"
    data = make_unequal_length_cache_data()

    monkeypatch.setattr(cache, "CACHE_VERSION", _CACHE_VERSION)

    with pytest.raises(CacheWriteFailure, match="Cache write"):
        write_cache(file_path, data)


def test_write_cache_cleanup(tmp_path, monkeypatch):
    file_path = tmp_path / "test.hdf5"
    data = make_cache_data()

    def mock_write(file_path, data):
        _write_cache_file(file_path, data)
        raise RuntimeError("mock failure")

    monkeypatch.setattr(cache, "_write_cache_file", mock_write)

    ls_before = [f for f in file_path.parent.iterdir()]
    with pytest.raises(CacheWriteFailure, match="Cache write"):
        write_cache(file_path, data)
    ls_after = [f for f in file_path.parent.iterdir()]
    assert ls_before == ls_after


def test_write_cache_attribute_types(tmp_path, monkeypatch):
    file_path = tmp_path / "test.hdf5"
    data = make_cache_data()

    monkeypatch.setattr(cache, "CACHE_VERSION", _CACHE_VERSION)

    write_cache(file_path, data)

    with h5py.File(file_path, "r") as cache_file:
        assert isinstance(cache_file.attrs["cache_version"], np.int64)
        assert isinstance(cache_file.attrs["start_time"], float)
        assert isinstance(cache_file.attrs["sport"], str)


def test_write_cache_rejects_non_string_sport(tmp_path, monkeypatch):
    file_path = tmp_path / "test.hdf5"
    data = make_cache_data()

    monkeypatch.setattr(cache, "CACHE_VERSION", _CACHE_VERSION)
    data.sport = 42  # type: ignore[assignment]

    with pytest.raises(CacheWriteFailure):
        write_cache(file_path, data)


def test_resolve_cache_path_creates_parents(tmp_path):
    fingerprint = "abcdef123456"
    shard_dir = tmp_path / fingerprint[0:2]
    assert not shard_dir.exists()
    result = cache.resolve_cache_path(fingerprint, tmp_path)
    expected = tmp_path / fingerprint[0:2] / f"{fingerprint}.h5"
    assert result == expected
    assert expected.parent.exists()
