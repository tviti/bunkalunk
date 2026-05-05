"""HDF5 Decode Artifact IO Module."""

import os
from dataclasses import dataclass
from pathlib import Path
from tempfile import mkstemp

import h5py


CACHE_VERSION = 20260504
_SUFFIX = ".h5"


@dataclass
class CacheData:
    """This class strictly represents decode artifacts. It does not store
    operational state.

    """
    latitude: list[float | None]
    longitude: list[float | None]
    time: list[float]

    start_time: str
    sport: str | None = None
    heart_rate: list[float | None] | None = None


def _write_cache_file(file_path: Path, data: CacheData) -> None:
    # TODO: Refactor so that mandatory and optional fields are populated
    # dynamically, instead of hardcoding them
    n = len(data.time)
    if not (n == len(data.latitude) == len(data.longitude)):
        raise ValueError(
            "Unequal length coordinate arrays (time, latitude, longitude); "
            f"Got '{n}', '{data.latitude}', '{data.longitude}'"
        )

    with h5py.File(file_path, "w") as cache:
        time: h5py.Dataset = cache.create_dataset("time", shape=(n,), dtype="float64")
        latitude: h5py.Dataset = cache.create_dataset(
            "latitude", shape=(n,), dtype="float64"
        )
        longitude: h5py.Dataset = cache.create_dataset(
            "longitude", shape=(n,), dtype="float64"
        )

        cache.attrs["cache_version"] = CACHE_VERSION

        cache.attrs["start_time"] = data.start_time
        cache.attrs["sport"] = data.sport
        time[:] = data.time[:]
        latitude[:] = data.latitude[:]
        longitude[:] = data.longitude[:]

        # Optional fields
        if data.heart_rate:
            # TODO: Validate heart_rate length
            heart_rate: h5py.Dataset = cache.create_dataset(
                "heart_rate", shape=(n,), dtype="float64"
            )
            heart_rate[:] = data.heart_rate[:]


def write_cache(file_path: Path, data: CacheData) -> None:
    tmp, tmp_name = mkstemp(dir=file_path.parent, suffix=_SUFFIX)
    os.close(tmp)  # Make sure h5py.File gets a closed fd
    tmp_path = Path(tmp_name)
    try:
        _write_cache_file(tmp_path, data)
        tmp_path.replace(file_path)
    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise


def resolve_cache_path(content_fingerprint: str, activity_store: Path) -> Path:
    shard = content_fingerprint[0:2]
    cache_parent = activity_store / shard
    if not cache_parent.exists():
        cache_parent.mkdir(parents=True)
    cache_path = (cache_parent / content_fingerprint).with_suffix(_SUFFIX)
    return cache_path
