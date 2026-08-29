"""HDF5 Decode Artifact IO Module."""

import os
from dataclasses import dataclass, fields, MISSING
from pathlib import Path
from tempfile import mkstemp

import h5py


CACHE_VERSION = 20260828
_SUFFIX = ".h5"


@dataclass
class CacheData:
    """This class strictly represents decode artifacts. It does not store
    operational state.

    """

    latitude: list[float | None]
    longitude: list[float | None]
    time: list[float]

    start_time: float
    sport: str | None = None
    heart_rate: list[float | None] | None = None
    elevation: list[float | None] | None = None
    distance: list[float | None] | None = None
    speed: list[float | None] | None = None


_CACHE_FIELDS_OPTIONAL_SCALAR = {"sport"}
# Optional row-aligned fields
_CACHE_FIELDS_OPTIONAL_VECTOR = {
    f.name
    for f in fields(CacheData)
    if f.default is not MISSING or f.default_factory is not MISSING
} - _CACHE_FIELDS_OPTIONAL_SCALAR


def _write_cache_file(file_path: Path, data: CacheData) -> None:
    # TODO: Refactor so that mandatory and optional fields are populated
    # dynamically, instead of hardcoding them
    n = len(data.time)
    if not (n == len(data.latitude) == len(data.longitude)):
        raise ValueError(
            "Unequal length coordinate arrays (time, latitude, longitude); "
            f"Got '{n}', '{data.latitude}', '{data.longitude}'"
        )

    if data.heart_rate and n != len(data.heart_rate):
        raise ValueError(f"Unequal length data array 'heart_rate'. Got '{n}'")

    with h5py.File(file_path, "w") as cache:
        time: h5py.Dataset = cache.create_dataset("time", shape=(n,), dtype="float64")
        latitude: h5py.Dataset = cache.create_dataset(
            "latitude", shape=(n,), dtype="float64"
        )
        longitude: h5py.Dataset = cache.create_dataset(
            "longitude", shape=(n,), dtype="float64"
        )

        cache.attrs.create("cache_version", CACHE_VERSION, dtype=int)

        cache.attrs.create("start_time", data.start_time, dtype=float)
        time[:] = data.time[:]
        latitude[:] = data.latitude[:]
        longitude[:] = data.longitude[:]

        for field_name in _CACHE_FIELDS_OPTIONAL_VECTOR:
            val = getattr(data, field_name, None)
            if val is not None:
                cache_var: h5py.Dataset = cache.create_dataset(
                    field_name, shape=(n,), dtype="float64"
                )
                cache_var[:] = val[:]

        # Only one optional scalar so no need to loop over the set
        if data.sport is not None:
            cache.attrs.create("sport", data.sport, dtype=h5py.string_dtype())


class CacheWriteFailure(Exception):
    pass


def write_cache(file_path: Path, data: CacheData) -> None:
    tmp, tmp_name = mkstemp(dir=file_path.parent, suffix=_SUFFIX)
    os.close(tmp)  # Make sure h5py.File gets a closed fd
    tmp_path = Path(tmp_name)
    try:
        _write_cache_file(tmp_path, data)
        tmp_path.replace(file_path)
    except Exception as e:
        tmp_path.unlink(missing_ok=True)
        raise CacheWriteFailure(f"Cache write for '{file_path.name}' failed.") from e


def resolve_cache_path(content_fingerprint: str, activity_store: Path) -> Path:
    shard = content_fingerprint[0:2]
    cache_parent = activity_store / shard
    if not cache_parent.exists():
        cache_parent.mkdir(parents=True, exist_ok=True)
    cache_path = (cache_parent / content_fingerprint).with_suffix(_SUFFIX)
    return cache_path
