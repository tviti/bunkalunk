"""Garmin FIT file decoder.

To narrow the project scope to something tractable, this module is targeted at Activity FIT files. Other FIT file types could be supported in the future, such as:
- Monitoring
- MonitoringDaily
- Weight

"""
import logging
from dataclasses import dataclass, field, fields
from datetime import datetime
from typing import BinaryIO

from fitdecode import (FitReader, StandardUnitsDataProcessor,
                       FIT_FRAME_DATAMESG, FitDataMessage, FitHeader,
                       FitDefinitionMessage, FitCRC)

from bunkalunk.cache import CacheData


@dataclass
class FitData():
    timestamp: list[datetime] = field(default_factory=list)
    position_long: list[float] = field(default_factory=list)
    position_lat: list[float] = field(default_factory=list)
    sport: str | None = None

    start_time: datetime | None = None

    manufacturer: str = ''

    heart_rate: list[float] = field(default_factory=list)
    # distance: list[float] | None = None
    # enhanced_speed: list[float] | None = None
    # enhanced_altitude: list[float] | None = None


class UnsupportedFITFileType(Exception):
    pass
    

def _append_fit_data(
        frame: FitDataMessage,
        field_names: set[str],
        fit_data: FitData
) -> None:
    for f in frame.fields:
        if f.name in field_names:
            getattr(fit_data, f.name).append(f.value)


def _is_data(frame: FitHeader | FitDefinitionMessage | FitDataMessage | FitCRC):
    return frame.frame_type == FIT_FRAME_DATAMESG


def _assert_is_activity(file_id: FitDataMessage):
    type = next((a.value for a in file_id.fields if a.name == 'type'), None)
    if type != 'activity':
        raise UnsupportedFITFileType(
            'FIT decoder only supports activity files. '
            f'Got {type}'
        )


def read_fit(fit_path: BinaryIO, *, logger: logging.Logger | None = None) -> FitData:
    """Construct a ``FitData`` object from an Activity FIT file.

    For simplicity, this function only supports Activity FIT files, and will
    raise ``UnsupportedFITFileType`` for anything else.

    """
    logger = logger or logging.getLogger(__name__)
    fit_data = FitData()
    fit_data_fieldnames: set[str] = {f.name for f in fields(fit_data)}
    file_id = None

    # In general, it isn't a good idea to rely on frames/fields in any sort of
    # FIT file. Each FIT file type does have a small set of required frame
    # types, and those in turn have a small set of required fields, but the
    # protocol seems to be intentionally designed to have a loose standard.

    with FitReader(fit_path, processor=StandardUnitsDataProcessor()) as fit:
        for frame in fit:
            # Skip till we've hit the start of a file in the stream
            if file_id is None:
                if _is_data(frame) and frame.name == 'file_id':
                    # file_id frames are guaranteed to have type, manufacturer,
                    # and product fields.
                    _assert_is_activity(frame)
                    file_id = frame
                continue

            if _is_data(frame) and frame.name == 'sport':
                fit_data.sport = frame.get_value('sport')

            if _is_data(frame) and frame.name == 'session':
                # A Session message is a Summary message type. Start Time, Total
                # Elapsed Time, Total Timer Time, and Timestamp are required
                # fields for all summary messages.
                fit_data.start_time = frame.get_value('start_time')
                sport = frame.get_value('sport')
                fit_data.sport = sport or fit_data.sport
                
            if _is_data(frame) and frame.name == 'record':
                _append_fit_data(frame, fit_data_fieldnames, fit_data)

            if _is_data(frame) and frame.name == 'file_id':
                logger.warning('Encountered another FIT in the stream. Breaking.')
                break

    return fit_data


def fit_to_cache(fit_data: FitData) -> CacheData:
    if fit_data.start_time is None:
        raise ValueError(
            'Cache schema requires start_time, but given fit_data has none!'
        )

    time = [t.timestamp() for t in fit_data.timestamp]
    return CacheData(
        heart_rate=fit_data.heart_rate,
        latitude=fit_data.position_lat,
        longitude=fit_data.position_long,
        time=time,
        start_time=fit_data.start_time.isoformat(),
        sport=fit_data.sport,
    )
