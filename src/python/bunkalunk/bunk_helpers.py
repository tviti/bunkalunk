from pathlib import Path
from hashlib import sha256
from typing import BinaryIO

def validate_extension(input_path: Path) -> bool:
    """Check if the given file path's extension is supported by the archive
    manager."""
    ok_exts = {".fit"}  # Future: .gpx, .tcx
    ext = input_path.suffix
    if ext not in ok_exts:
        return False
    return True


def compute_fingerprint(input_file: BinaryIO, chunk_size: int = 1_000_000) -> str:
    hasher = sha256()
    old_point = input_file.tell()  # Save current position
    try:
        input_file.seek(0)  # Make sure we read from start
        for chunk in iter(lambda: input_file.read(chunk_size), b""):
            hasher.update(chunk)
    finally:
        input_file.seek(old_point)  # Restore original position
    return hasher.hexdigest()
