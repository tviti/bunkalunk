from pathlib import Path
from hashlib import sha256
from typing import BinaryIO
from bunkalunk.db import Connection, get_source_file
import os


def validate_extension(input_path: Path) -> bool:
    """Check if the given file path's extension is supported by the archive
    manager."""
    ok_exts = {".fit"}  # Future: .gpx, .tcx
    ext = input_path.suffix.lower()
    if ext not in ok_exts:
        return False

    return True


def compute_fingerprint(input_file: BinaryIO, chunk_size: int = 1_000_000) -> str:
    """Returns the SHA-256 of an input file.

    Requires that ``input_file`` is seekable. The file pointer is first reset to
    the start of the file, and then returned to its original location on exit.

    """
    if not input_file.seekable():
        raise ValueError("input_file must be seekable")

    hasher = sha256()
    old_point = input_file.tell()  # Save current position
    try:
        input_file.seek(0)  # Make sure we read from start
        for chunk in iter(lambda: input_file.read(chunk_size), b""):
            hasher.update(chunk)
    finally:
        input_file.seek(old_point)  # Restore original position
    return hasher.hexdigest()


def validate_path_registration(conn: Connection, source_path: str) -> bool | None:
    """Verify that the source_files row for ``source_path`` is valid.

    Checks that:
    - ``source_path`` exists in the source_files table
    - ``source_path`` exists on disk
    - The content fingerprint of ``source_path`` matches the content_fingerprint
      column in the row

    Returns ``None`` if ``source_path`` does not exist in the table, ``False``
    if any of the remainig checks fail, ``True`` otherwise.

    """
    source_file = get_source_file(conn, str(source_path))
    if source_file is None:
        return None

    if not os.path.isfile(source_path):
        return False

    with open(source_path, "rb") as f:
        content_fingerprint: str = compute_fingerprint(f)

    if content_fingerprint != source_file.content_fingerprint:
        return False

    return True


def resolve_bunk_home(create: bool = True) -> Path:
    bunk_home = Path(os.environ.get("BUNK_HOME", "~/.bunk")).expanduser()
    if not bunk_home.exists() and create:
        bunk_home.mkdir(parents=True)
    return bunk_home


def resolve_source_path(path: Path) -> str:
    return str(path.resolve())


def resolve_activity_store(create: bool = True) -> Path:
    bunk_home = resolve_bunk_home(create)
    activity_store = bunk_home / "activity_store"
    if not activity_store.exists() and create:
        activity_store.mkdir(parents=True, exist_ok=True)
    return activity_store
