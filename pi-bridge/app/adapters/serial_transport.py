from __future__ import annotations

import asyncio
import os
from collections.abc import Callable
from typing import Any, Protocol


class SerialTransportError(OSError):
    """Raised when a serial device cannot be opened or used."""


class SerialDependencyError(SerialTransportError):
    """Raised when hardware mode is requested without pyserial installed."""


class SerialTransportClosedError(SerialTransportError):
    """Raised when I/O is attempted after closing a serial transport."""


class SerialReadTimeout(TimeoutError):
    """Raised when a newline-delimited frame is not received before timeout."""


class SyncSerialPort(Protocol):
    """The small synchronous pyserial surface used by SerialLineTransport."""

    def readline(self) -> bytes:
        ...

    def write(self, data: bytes) -> int | None:
        ...

    def flush(self) -> None:
        ...

    def close(self) -> None:
        ...


SerialFactory = Callable[..., SyncSerialPort]


def _open_pyserial(**options: Any) -> SyncSerialPort:
    try:
        import serial  # type: ignore[import-not-found]
    except ModuleNotFoundError as error:
        raise SerialDependencyError(
            "Hardware serial mode requires pyserial. Install pi-bridge/requirements.txt.",
        ) from error

    try:
        return serial.Serial(**options)
    except Exception as error:
        raise SerialTransportError(
            f"Could not open serial device {options.get('port')!r}: {error}",
        ) from error


class SerialLineTransport:
    """Async newline transport backed by blocking pyserial calls.

    Opening, reading, writing, flushing, cancelling a read, and closing all run in
    worker threads so they never block the FastAPI event loop.
    """

    def __init__(
        self,
        *,
        device: str,
        baudrate: int,
        read_timeout_seconds: float | None,
        serial_factory: SerialFactory | None = None,
        serial_port: SyncSerialPort | None = None,
    ) -> None:
        if not device:
            raise ValueError("Serial device path must not be empty.")
        if baudrate <= 0:
            raise ValueError("Serial baudrate must be positive.")
        if read_timeout_seconds is not None and read_timeout_seconds < 0:
            raise ValueError("Serial read timeout must be zero, positive, or None.")
        if serial_factory is not None and serial_port is not None:
            raise ValueError("Pass serial_factory or serial_port, not both.")

        self.device = device
        self.baudrate = baudrate
        self.read_timeout_seconds = read_timeout_seconds
        self._serial_factory = serial_factory or _open_pyserial
        self._serial = serial_port
        self._open_lock = asyncio.Lock()
        self._write_lock = asyncio.Lock()
        self._closed = False

    @property
    def is_open(self) -> bool:
        if self._serial is None or self._closed:
            return False
        return bool(getattr(self._serial, "is_open", True))

    async def open(self) -> None:
        """Open the device in a worker thread, if it is not already open."""

        await self._get_serial()

    async def _get_serial(self) -> SyncSerialPort:
        if self._closed:
            raise SerialTransportClosedError(
                f"Serial device {self.device!r} is already closed.",
            )
        if self._serial is not None:
            return self._serial

        async with self._open_lock:
            if self._closed:
                raise SerialTransportClosedError(
                    f"Serial device {self.device!r} is already closed.",
                )
            if self._serial is None:
                options = {
                    "port": self.device,
                    "baudrate": self.baudrate,
                    "timeout": self.read_timeout_seconds,
                }
                if os.name == "posix":
                    options["exclusive"] = True
                try:
                    self._serial = await asyncio.to_thread(
                        self._serial_factory,
                        **options,
                    )
                except (SerialTransportError, asyncio.CancelledError):
                    raise
                except Exception as error:
                    raise SerialTransportError(
                        f"Could not open serial device {self.device!r}: {error}",
                    ) from error
        return self._serial

    @staticmethod
    def _readline(port: SyncSerialPort) -> bytes:
        return port.readline()

    async def read_line(self) -> bytes:
        port = await self._get_serial()
        try:
            frame = await asyncio.to_thread(self._readline, port)
        except asyncio.CancelledError:
            await self._cancel_pending_read(port)
            raise
        except Exception as error:
            await self._drop_serial(port)
            raise SerialTransportError(
                f"Failed to read from serial device {self.device!r}: {error}",
            ) from error

        if not frame:
            raise SerialReadTimeout(
                f"No newline-delimited frame received from {self.device!r} "
                f"within {self.read_timeout_seconds!r} seconds.",
            )
        if not isinstance(frame, bytes):
            raise SerialTransportError(
                f"Serial device {self.device!r} returned a non-bytes frame.",
            )
        return frame

    @staticmethod
    def _write_and_flush(port: SyncSerialPort, payload: bytes) -> None:
        written = port.write(payload)
        if written is not None and written != len(payload):
            raise OSError(
                f"Short serial write: wrote {written} of {len(payload)} bytes.",
            )
        port.flush()

    async def write_line(self, line: str) -> None:
        if not isinstance(line, str):
            raise TypeError("Serial line must be a string.")
        if not line or "\n" in line or "\r" in line:
            raise ValueError("Serial line must be non-empty and contain no newline.")
        try:
            payload = f"{line}\n".encode("ascii")
        except UnicodeEncodeError as error:
            raise ValueError("Serial line must contain ASCII only.") from error

        port = await self._get_serial()
        async with self._write_lock:
            try:
                await asyncio.to_thread(self._write_and_flush, port, payload)
            except asyncio.CancelledError:
                raise
            except Exception as error:
                await self._drop_serial(port)
                raise SerialTransportError(
                    f"Failed to write to serial device {self.device!r}: {error}",
                ) from error

    async def _drop_serial(self, port: SyncSerialPort) -> None:
        """Forget a broken handle so the next I/O attempt lazily reconnects."""

        if self._serial is port:
            self._serial = None
        try:
            await asyncio.to_thread(port.close)
        except Exception:
            return

    async def _cancel_pending_read(self, port: SyncSerialPort) -> None:
        cancel_read = getattr(port, "cancel_read", None)
        if not callable(cancel_read):
            return
        try:
            await asyncio.shield(asyncio.to_thread(cancel_read))
        except Exception:
            # Cancellation must retain its original CancelledError. A subsequent
            # close still releases a port whose driver cannot cancel reads.
            return

    async def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        port = self._serial
        if port is None:
            return

        await self._cancel_pending_read(port)
        try:
            await asyncio.to_thread(port.close)
        except Exception as error:
            raise SerialTransportError(
                f"Failed to close serial device {self.device!r}: {error}",
            ) from error

    async def __aenter__(self) -> SerialLineTransport:
        await self.open()
        return self

    async def __aexit__(self, *_: object) -> None:
        await self.close()
