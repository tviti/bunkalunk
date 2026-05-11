from bunkalunk.formats import fit
from bunkalunk.formats.fit import FitData, read_fit, fit_to_cache, UnsupportedFITFileType
from pathlib import Path
from datetime import datetime
import pytest
import logging

from dataclasses import dataclass

import fitdecode


@dataclass
class FakeField:
    name: str
    value: object


class FakeFrame:
    def __init__(self, name, fields, frame_type):
        self.name = name
        self.fields = fields
        self.frame_type = frame_type
    def get_value(self, name, fallback=None):
        for field in self.fields:
            if field.name == name:
                return field.value
        return None


class FakeReader:
    def __init__(self, frames):
        self._frames = frames
    def __enter__(self):
        return iter(self._frames)
    def __exit__(self, exc_type, exc, tb):
        return False


def test_read_fit(fit_path):
    with open(fit_path, "rb") as f:
        fit_data = read_fit(f)

    n_timestamp = len(fit_data.timestamp)
    n_lat = len(fit_data.position_lat)
    n_lon = len(fit_data.position_long)

    assert 2148 == n_timestamp == n_lat == n_lon
    assert fit_data.sport == "cycling"
    assert fit_data.start_time.isoformat() == "2023-11-16T20:37:44+00:00"
    assert fit_data.heart_rate is not None and len(fit_data.heart_rate) > 0


def test_fit_to_cache_raises_on_no_start_time():
    fit_data = FitData(start_time=None)

    with pytest.raises(ValueError):
        fit_to_cache(fit_data)


def test_fit_to_cache_converts_start_time_to_epoch(fake_reader_activity_fit):
    fit_data = read_fit("any-path")
    cache_data = fit_to_cache(fit_data)
    assert cache_data.start_time == 1777593600.0


def patch_fit_reader(monkeypatch, reader):
    def _get_fake_reader(fit_path, processor):
        return reader

    monkeypatch.setattr(fit, "FitReader", _get_fake_reader)

def _make_activity_fit_fields():
    file_id_fields = [FakeField("type", "activity")]
    file_id_frame = FakeFrame(name="file_id",
                              fields=file_id_fields,
                              frame_type=fitdecode.FIT_FRAME_DATAMESG)

    rec_fields = [
        FakeField("heart_rate", 99),
        FakeField("position_lat", 0.0),
        FakeField("position_long", 0.0),
        FakeField("timestamp", datetime.fromisoformat("2026-05-02T00:00:00+00:00"))
    ]
    rec_frame = FakeFrame(name="record",
                          fields=rec_fields,
                          frame_type=fitdecode.FIT_FRAME_DATAMESG)

    session_fields = [
        FakeField("start_time", datetime.fromisoformat("2026-05-01T00:00:00+00:00"))
    ]
    session_frame = FakeFrame(name="session",
                              fields=session_fields,
                              frame_type=fitdecode.FIT_FRAME_DATAMESG)

    sport_fields = [FakeField("sport", "competetive-gardening")]
    sport_frame = FakeFrame(name="sport",
                            fields=sport_fields,
                            frame_type=fitdecode.FIT_FRAME_DATAMESG)

    fields = [file_id_frame, sport_frame, rec_frame, session_frame]
    return fields
    

@pytest.fixture
def fake_reader_activity_fit(monkeypatch):
    fields = _make_activity_fit_fields()
    reader = FakeReader(fields)
    patch_fit_reader(monkeypatch, reader)

    return reader


@pytest.fixture
def fake_reader_wellness_fit(monkeypatch):
    file_id_fields = [FakeField("type", "wellness")]
    file_id_frame = FakeFrame(name="file_id",
                              fields=file_id_fields,
                              frame_type=fitdecode.FIT_FRAME_DATAMESG)

    reader = FakeReader([file_id_frame])
    patch_fit_reader(monkeypatch, reader)

    return reader


@pytest.fixture
def fake_reader_two_activity_fit(monkeypatch):
    fields = _make_activity_fit_fields()

    file_id_fields_2 = [FakeField("type", "activity")]
    file_id_frame_2 = FakeFrame(name="file_id",
                                fields=file_id_fields_2,
                                frame_type=fitdecode.FIT_FRAME_DATAMESG)

    rec_fields_2 = [
        FakeField("heart_rate", 199),
        FakeField("position_lat", 1.0),
        FakeField("position_long", 1.0),
        FakeField("timestamp", datetime.fromisoformat("2026-05-03T00:00:00+00:00"))
    ]
    rec_frame_2 = FakeFrame(name="record",
                            fields=rec_fields_2,
                            frame_type=fitdecode.FIT_FRAME_DATAMESG)

    fields += [file_id_frame_2, rec_frame_2]
    reader = FakeReader(fields)
    patch_fit_reader(monkeypatch, reader)

    return reader
    

def test_read_fit_collects_record_fields(fake_reader_activity_fit):
    """Test that read_fit collects data from record frames."""
    fit_data = read_fit("any-path")
    assert fit_data.timestamp[0].isoformat() == "2026-05-02T00:00:00+00:00"
    assert fit_data.position_lat == [0.0]
    assert fit_data.position_long == [0.0]
    assert fit_data.heart_rate == [99]


def test_read_fit_reads_session_start_time(fake_reader_activity_fit):
    """Test that read_fit extracts start_time from session frames."""
    fit_data = read_fit("any-path")
    assert fit_data.start_time.isoformat() == "2026-05-01T00:00:00+00:00"


def test_read_fit_reads_sport_name(fake_reader_activity_fit):
    """Test that read_fit extracts sport name from sport frames."""
    fit_data = read_fit("any-path")
    assert fit_data.sport == "competetive-gardening"


def test_read_fit_rejects_non_activity_file(fake_reader_wellness_fit):
    """Test that read_fit raises UnsupportedFITFileType for non-activity files."""
    with pytest.raises(UnsupportedFITFileType):
        read_fit("any-path")


def test_read_fit_stops_at_second_file_id(fake_reader_two_activity_fit, caplog):
    """Test that read_fit stops reading when encountering a second file_id frame."""
    with caplog.at_level(logging.WARNING):
        fit_data = read_fit("any-path")
    assert "Encountered another FIT in the stream" in caplog.text
    assert len(fit_data.timestamp) == 1
    assert fit_data.timestamp[0].isoformat() == "2026-05-02T00:00:00+00:00"
    assert fit_data.position_lat == [0.0]
    assert fit_data.position_long == [0.0]
    assert fit_data.heart_rate == [99]
