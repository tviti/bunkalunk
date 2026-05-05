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
    start_time: datetime | None = None
    sport: str | None = None
    manufacturer: str | None = None

    timestamp: list[datetime] = field(default_factory=list)
    position_long: list[float | None] = field(default_factory=list)
    position_lat: list[float | None] = field(default_factory=list)
    heart_rate: list[float | None] = field(default_factory=list)


_RECORD_FIELDS_REQUIRED = {'timestamp'}
_RECORD_FIELDS_OPTIONAL = {'position_long', 'position_lat', 'heart_rate'}

class UnsupportedFITFileType(Exception):
    pass
    

class MissingRequiredField(Exception):
    pass


# TODO: Maybe this should be a classmethod
def _append_record(frame: FitDataMessage, fit_data: FitData) -> None:
    for name in _RECORD_FIELDS_REQUIRED:
        # get_value with no fallback raises on lookup failure
        try:
            attr = getattr(fit_data, name)
            attr.append(frame.get_value(name))
        except KeyError as e:
            raise MissingRequiredField(
                f"Record is missing '{name}' field."
            ) from e
            

    for name in _RECORD_FIELDS_OPTIONAL:
        attr = getattr(fit_data, name)
        attr.append(frame.get_value(name, fallback=None))


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
                    fit_data.manufacturer = frame.get_value('manufacturer')
                    _assert_is_activity(frame)
                    file_id = frame
                continue

            if _is_data(frame) and frame.name == 'sport':
                fit_data.sport = frame.get_value('sport', fallback=None)

            if _is_data(frame) and frame.name == 'session':
                # A Session message is a Summary message type. Start Time, Total
                # Elapsed Time, Total Timer Time, and Timestamp are required
                # fields for all summary messages.
                fit_data.start_time = frame.get_value('start_time')
                if fit_data.sport is None:
                    fit_data.sport = frame.get_value('sport', fallback=None)
                
            if _is_data(frame) and frame.name == 'record':
                _append_record(frame, fit_data)

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
