from __future__ import annotations

import inspect
import logging
from enum import Enum
from typing import Protocol, runtime_checkable

from .serial_transport import (
    SerialFactory,
    SerialLineTransport,
    SerialReadTimeout,
    SerialTransportError,
    SyncSerialPort,
)


DEFAULT_MEGA_DEVICE = "/dev/ttyACM0"
DEFAULT_MEGA_BAUDRATE = 115200
DEFAULT_MEGA_READ_TIMEOUT_SECONDS = 2.0

logger = logging.getLogger("uvicorn.error.snap.serial")


class MegaFrameError(ValueError):
    """Raised when a Mega occupancy frame violates the wire contract."""


class OccupancyState(str, Enum):
    EMPTY = "EMPTY"
    OCCUPIED = "OCCUPIED"
    UNKNOWN = "UNKNOWN"


def _decode_ascii_frame(frame: str | bytes) -> str:
    if isinstance(frame, bytes):
        try:
            text = frame.decode("ascii")
        except UnicodeDecodeError as error:
            raise MegaFrameError("Mega frame must be ASCII.") from error
    elif isinstance(frame, str):
        text = frame
    else:
        raise MegaFrameError("Mega frame must be text or ASCII bytes.")
    return text.rstrip("\r\n")


class MegaBitmaskParser:
    """Decode SNAP-code's ASCII decimal six-slot occupancy bitmask.

    Bit 0 is slot 1 and bit 5 is slot 6. A set bit means OCCUPIED.
    """

    slot_count = 6
    min_value = 0
    max_value = (1 << slot_count) - 1

    @classmethod
    def parse(cls, frame: str | bytes) -> dict[str, OccupancyState]:
        text = _decode_ascii_frame(frame)
        if not text or not text.isascii() or not text.isdecimal():
            raise MegaFrameError(
                "Mega bitmask must be an ASCII decimal integer from 0 through 63.",
            )

        value = int(text, 10)
        if not cls.min_value <= value <= cls.max_value:
            raise MegaFrameError("Mega bitmask must be between 0 and 63.")

        return {
            str(index + 1): (
                OccupancyState.OCCUPIED
                if value & (1 << index)
                else OccupancyState.EMPTY
            )
            for index in range(cls.slot_count)
        }


class MegaFrameParser:
    """Parse the real bitmask frame and the legacy six-item CSV contract."""

    slot_ids = frozenset({"1", "2", "3", "4", "5", "6"})
    max_frame_length = 128

    @classmethod
    def parse(cls, frame: str | bytes) -> dict[str, OccupancyState]:
        text = _decode_ascii_frame(frame)
        if not text or len(text) > cls.max_frame_length:
            raise MegaFrameError("Mega frame is empty or too long.")

        if "," not in text and ":" not in text:
            return MegaBitmaskParser.parse(text)

        parts = text.split(",")
        if len(parts) != 6:
            raise MegaFrameError("Mega frame must contain exactly six slots.")

        result: dict[str, OccupancyState] = {}
        for part in parts:
            if part.count(":") != 1:
                raise MegaFrameError("Each Mega item must use SLOT:STATE.")
            slot_id, raw_state = part.split(":", 1)
            if slot_id not in cls.slot_ids:
                raise MegaFrameError(f"Unknown Mega slot: {slot_id!r}.")
            if slot_id in result:
                raise MegaFrameError(f"Duplicate Mega slot: {slot_id}.")
            try:
                result[slot_id] = OccupancyState(raw_state)
            except ValueError as error:
                raise MegaFrameError(f"Invalid occupancy state: {raw_state!r}.") from error

        if set(result) != cls.slot_ids:
            raise MegaFrameError("Mega frame must contain slots 1 through 6.")
        return result


def parse_mega_frame(frame: str | bytes) -> dict[str, OccupancyState]:
    return MegaFrameParser.parse(frame)


@runtime_checkable
class OccupancyTransport(Protocol):
    async def read_frame(self) -> str | bytes:
        """Read one newline-delimited frame from Bluetooth/serial transport."""

    async def close(self) -> None:
        """Release the underlying transport."""


class OccupancyAdapter:
    def __init__(
        self,
        transport: OccupancyTransport,
        parser: type[MegaFrameParser] = MegaFrameParser,
    ) -> None:
        self._transport = transport
        self._parser = parser

    async def read_occupancy(self) -> dict[str, OccupancyState]:
        return self._parser.parse(await self._transport.read_frame())

    async def close(self) -> None:
        close = getattr(self._transport, "close", None)
        if close is None:
            return
        result = close()
        if inspect.isawaitable(result):
            await result


class SerialOccupancyTransport:
    """Arduino Mega transport for SNAP-code ADV_6_CODE0629.ino."""

    def __init__(
        self,
        device: str = DEFAULT_MEGA_DEVICE,
        baudrate: int = DEFAULT_MEGA_BAUDRATE,
        read_timeout_seconds: float | None = DEFAULT_MEGA_READ_TIMEOUT_SECONDS,
        *,
        serial_factory: SerialFactory | None = None,
        serial_port: SyncSerialPort | None = None,
    ) -> None:
        self._lines = SerialLineTransport(
            device=device,
            baudrate=baudrate,
            read_timeout_seconds=read_timeout_seconds,
            serial_factory=serial_factory,
            serial_port=serial_port,
        )

    @property
    def device(self) -> str:
        return self._lines.device

    @property
    def baudrate(self) -> int:
        return self._lines.baudrate

    @property
    def read_timeout_seconds(self) -> float | None:
        return self._lines.read_timeout_seconds

    @property
    def is_open(self) -> bool:
        return self._lines.is_open

    async def open(self) -> None:
        await self._lines.open()

    async def read_frame(self) -> bytes:
        frame = await self._lines.read_line()
        logger.info(
            "UART RX mega device=%s baud=%s frame=%r",
            self.device,
            self.baudrate,
            frame.rstrip(b"\r\n").decode("ascii", errors="backslashreplace"),
        )
        return frame

    async def close(self) -> None:
        await self._lines.close()

    async def __aenter__(self) -> SerialOccupancyTransport:
        await self.open()
        return self

    async def __aexit__(self, *_: object) -> None:
        await self.close()


class SerialOccupancyAdapter(OccupancyAdapter):
    """Ready-to-use Mega adapter with the real 0..63 bitmask parser."""

    def __init__(
        self,
        device: str = DEFAULT_MEGA_DEVICE,
        baudrate: int = DEFAULT_MEGA_BAUDRATE,
        read_timeout_seconds: float | None = DEFAULT_MEGA_READ_TIMEOUT_SECONDS,
        *,
        serial_factory: SerialFactory | None = None,
        serial_port: SyncSerialPort | None = None,
    ) -> None:
        transport = SerialOccupancyTransport(
            device=device,
            baudrate=baudrate,
            read_timeout_seconds=read_timeout_seconds,
            serial_factory=serial_factory,
            serial_port=serial_port,
        )
        super().__init__(transport, MegaBitmaskParser)
        self.transport = transport

    @property
    def device(self) -> str:
        return self.transport.device

    @property
    def baudrate(self) -> int:
        return self.transport.baudrate

    @property
    def is_open(self) -> bool:
        return self.transport.is_open

    async def open(self) -> None:
        await self.transport.open()
