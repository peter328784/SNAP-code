from __future__ import annotations

import asyncio
import inspect
import logging
import re
from collections.abc import AsyncIterator
from datetime import datetime, timezone
from enum import Enum
from typing import Protocol, runtime_checkable

from .serial_transport import (
    SerialFactory,
    SerialLineTransport,
    SerialReadTimeout,
    SerialTransportError,
    SyncSerialPort,
)


DEFAULT_ROBOT_DEVICE = "/dev/serial0"
DEFAULT_ROBOT_BAUDRATE = 9600
# The firmware can remain silent while H reverses for up to 12 seconds, so this
# must be comfortably longer than a single physical action.
DEFAULT_ROBOT_READ_TIMEOUT_SECONDS = 30.0

logger = logging.getLogger("uvicorn.error.snap.serial")


PATH_COMMANDS: dict[str, str] = {
    "1": "LCPSBWB",
    "2": "LWPSBCB",
    "3": "LLCPSBWB",
    "4": "LLWPSBCB",
    "5": "LLLCPSBWB",
    "6": "LLLWPSBCB",
}
SLOT_PATH_COMMANDS = PATH_COMMANDS


class UnoProtocolError(ValueError):
    """Raised for unknown Uno commands or status frames."""


class UnoCommandError(UnoProtocolError):
    """Raised when the Uno reports an ERR:* response."""


class UnoStoppedError(UnoProtocolError):
    """Raised when the Uno reports an emergency STOPPED response."""


class UnsupportedRobotOperationError(UnoProtocolError):
    """Raised when hardware is asked to run a route it does not implement."""


class UnoStatus(str, Enum):
    READY = "READY"
    TRACING = "TRACING"
    APPROACHING = "APPROACHING"
    GRIPPING = "GRIPPING"
    REVERSING = "REVERSING"
    DONE = "DONE"


class UnoStatusCodec:
    action_statuses: dict[str, UnoStatus] = {
        "L": UnoStatus.TRACING,
        "W": UnoStatus.TRACING,
        "C": UnoStatus.TRACING,
        "P": UnoStatus.APPROACHING,
        "S": UnoStatus.GRIPPING,
        "B": UnoStatus.REVERSING,
        "H": UnoStatus.REVERSING,
    }

    @classmethod
    def _action_status(cls, action: str, frame: str) -> UnoStatus:
        try:
            return cls.action_statuses[action]
        except KeyError as error:
            raise UnoProtocolError(
                f"Unknown Uno action {action!r} in frame {frame!r}.",
            ) from error

    @staticmethod
    def _decode_ascii(frame: str | bytes) -> str:
        if isinstance(frame, bytes):
            try:
                text = frame.decode("ascii")
            except UnicodeDecodeError as error:
                raise UnoProtocolError("Uno status must be ASCII.") from error
        elif isinstance(frame, str):
            text = frame
        else:
            raise UnoProtocolError("Uno status must be text or ASCII bytes.")
        return text.rstrip("\r\n")

    @classmethod
    def decode(cls, frame: str | bytes) -> UnoStatus:
        text = cls._decode_ascii(frame)
        if not text:
            raise UnoProtocolError("Uno status frame must not be empty.")

        # Keep the original simulator/contract frames backwards compatible.
        try:
            return UnoStatus(text)
        except ValueError:
            pass

        if text == "ROUTE_DONE":
            return UnoStatus.DONE
        if text == "PONG" or text.startswith("COMMANDS:"):
            return UnoStatus.READY

        if text == "STOPPED":
            raise UnoStoppedError("Uno stopped before completing the route.")
        if text == "ERR" or text.startswith("ERR:"):
            detail = text.partition(":")[2] or "UNKNOWN"
            raise UnoCommandError(f"Uno rejected the command: {detail}.")

        if text.startswith("ROUTE_ACCEPTED:"):
            raw_length = text.partition(":")[2]
            if not raw_length.isdecimal() or not 1 <= int(raw_length) <= 40:
                raise UnoProtocolError(f"Invalid Uno route acceptance: {text!r}.")
            return UnoStatus.TRACING

        if text.startswith("ACTION_START:") or text.startswith("ACTION_DONE:"):
            parts = text.split(":", 2)
            if len(parts) < 2 or len(parts[1]) != 1:
                raise UnoProtocolError(f"Invalid Uno action frame: {text!r}.")
            return cls._action_status(parts[1], text)

        if text == "STATUS:IDLE":
            return UnoStatus.READY
        if text.startswith("STATUS:RUNNING"):
            match = re.search(r"(?:^|,)COMMAND=([LWCPSBH])(?:,|$)", text)
            return (
                cls._action_status(match.group(1), text)
                if match
                else UnoStatus.TRACING
            )

        # These are informational frames emitted by the same SNAP-code sketch.
        if text.startswith("B_MODE:") or text.startswith("H_MODE:"):
            return UnoStatus.REVERSING
        if text.startswith("P_OBJECT_DETECTED:"):
            return UnoStatus.APPROACHING
        if text.startswith("DBG:SENSOR:"):
            match = re.search(r"CMD=([LWCPSBH])", text)
            return (
                cls._action_status(match.group(1), text)
                if match
                else UnoStatus.TRACING
            )

        raise UnoProtocolError(f"Unknown Uno status: {text!r}.")

    @staticmethod
    def encode(status: UnoStatus | str, *, newline: bool = False) -> str:
        try:
            value = UnoStatus(status).value
        except ValueError as error:
            raise UnoProtocolError(f"Unknown Uno status: {status!r}.") from error
        return f"{value}\n" if newline else value


def path_command_for(slot_id: str) -> str:
    try:
        return PATH_COMMANDS[slot_id]
    except KeyError as error:
        raise UnoProtocolError(f"Unknown destination slot: {slot_id!r}.") from error


def decode_uno_status(frame: str | bytes) -> UnoStatus:
    return UnoStatusCodec.decode(frame)


@runtime_checkable
class RobotTransport(Protocol):
    async def write_command(self, command: str) -> None:
        """Write one route command to the Uno UART connection."""

    async def read_status(self) -> str | bytes:
        """Read one Uno status frame."""

    async def close(self) -> None:
        """Release the underlying transport."""


@runtime_checkable
class RobotAdapter(Protocol):
    def supports_operation(self, operation: object) -> bool:
        """Return whether this adapter can safely execute the operation."""

    def execute_path(
        self,
        slot_id: str,
        operation: object = "PARKING",
    ) -> AsyncIterator[UnoStatus]:
        """Execute the route for a slot and yield statuses through DONE."""

    async def close(self) -> None:
        """Release adapter resources."""


def _operation_name(operation: object) -> str:
    value = getattr(operation, "value", operation)
    return value.upper() if isinstance(value, str) else ""


class TransportRobotAdapter:
    def __init__(
        self,
        transport: RobotTransport,
        codec: type[UnoStatusCodec] = UnoStatusCodec,
        *,
        supported_operations: tuple[str, ...] = ("PARKING",),
    ) -> None:
        self._transport = transport
        self._codec = codec
        self._supported_operations = frozenset(
            operation.upper() for operation in supported_operations
        )

    def supports_operation(self, operation: object) -> bool:
        return _operation_name(operation) in self._supported_operations

    async def execute_path(
        self,
        slot_id: str,
        operation: object = "PARKING",
    ) -> AsyncIterator[UnoStatus]:
        if not self.supports_operation(operation):
            name = _operation_name(operation) or repr(operation)
            raise UnsupportedRobotOperationError(
                f"Robot transport does not support operation {name}.",
            )
        command = path_command_for(slot_id)
        await self._transport.write_command(command)
        done_seen = False
        while not done_seen:
            status = self._codec.decode(await self._transport.read_status())
            done_seen = status is UnoStatus.DONE
            yield status

    async def close(self) -> None:
        close = getattr(self._transport, "close", None)
        if close is None:
            return
        result = close()
        if inspect.isawaitable(result):
            await result


class SerialRobotTransport:
    """9600-baud newline transport for SNAP-code sketch_aug24a.ino."""

    def __init__(
        self,
        device: str = DEFAULT_ROBOT_DEVICE,
        baudrate: int = DEFAULT_ROBOT_BAUDRATE,
        read_timeout_seconds: float | None = DEFAULT_ROBOT_READ_TIMEOUT_SECONDS,
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
        self._last_sent_at: str | None = None
        self._last_received_at: str | None = None

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat()

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

    @property
    def last_sent_at(self) -> str | None:
        return self._last_sent_at

    @property
    def last_received_at(self) -> str | None:
        return self._last_received_at

    async def open(self) -> None:
        await self._lines.open()

    async def write_command(self, command: str) -> None:
        logger.info(
            "UART TX robot device=%s baud=%s frame=%r",
            self.device,
            self.baudrate,
            command,
        )
        await self._lines.write_line(command)
        self._last_sent_at = self._now()

    async def read_status(self) -> bytes:
        frame = await self._lines.read_line()
        logger.info(
            "UART RX robot device=%s baud=%s frame=%r",
            self.device,
            self.baudrate,
            frame.rstrip(b"\r\n").decode("ascii", errors="backslashreplace"),
        )
        self._last_received_at = self._now()
        return frame

    async def close(self) -> None:
        await self._lines.close()

    async def __aenter__(self) -> SerialRobotTransport:
        await self.open()
        return self

    async def __aexit__(self, *_: object) -> None:
        await self.close()


class SerialRobotAdapter(TransportRobotAdapter):
    """Real robot adapter; the current firmware implements parking only."""

    def __init__(
        self,
        device: str = DEFAULT_ROBOT_DEVICE,
        baudrate: int = DEFAULT_ROBOT_BAUDRATE,
        read_timeout_seconds: float | None = DEFAULT_ROBOT_READ_TIMEOUT_SECONDS,
        *,
        serial_factory: SerialFactory | None = None,
        serial_port: SyncSerialPort | None = None,
        codec: type[UnoStatusCodec] = UnoStatusCodec,
    ) -> None:
        transport = SerialRobotTransport(
            device=device,
            baudrate=baudrate,
            read_timeout_seconds=read_timeout_seconds,
            serial_factory=serial_factory,
            serial_port=serial_port,
        )
        super().__init__(
            transport,
            codec,
            supported_operations=("PARKING",),
        )
        self.transport = transport

    async def probe(self, max_frames: int = 32) -> None:
        """Verify firmware presence and that it reports an idle route state."""

        if max_frames <= 0:
            raise ValueError("Robot probe max_frames must be positive.")
        await self.transport.write_command("PING")
        for _ in range(max_frames):
            frame = await self.transport.read_status()
            if self._codec._decode_ascii(frame) == "PONG":
                break
        else:
            raise UnoProtocolError(
                f"Robot did not answer PING within {max_frames} serial frames.",
            )

        await self.transport.write_command("STATUS")
        for _ in range(max_frames):
            frame = await self.transport.read_status()
            text = self._codec._decode_ascii(frame)
            if text == "STATUS:IDLE":
                return
            if text.startswith("STATUS:RUNNING"):
                raise UnoProtocolError(
                    f"Robot is already running a route at Gateway startup: {text}.",
                )
        raise UnoProtocolError(
            f"Robot did not report STATUS:IDLE within {max_frames} serial frames.",
        )

    @staticmethod
    def _frame_action(text: str, prefix: str) -> str:
        parts = text.split(":", 2)
        if len(parts) < 2 or len(parts[1]) != 1:
            raise UnoProtocolError(f"Invalid Uno {prefix} frame: {text!r}.")
        return parts[1]

    def _validate_informational_frame(
        self,
        text: str,
        current_action: str | None,
    ) -> None:
        if current_action is None:
            raise UnoProtocolError(
                f"Uno emitted an action detail outside an active action: {text!r}.",
            )
        if text.startswith("P_OBJECT_DETECTED:"):
            reported_action = "P"
        elif text.startswith("B_MODE:"):
            reported_action = "B"
        elif text.startswith("H_MODE:"):
            reported_action = "H"
        else:
            match = re.search(r"(?:^|,)CMD=([LWCPSBH])(?:,|$)", text)
            if match is None:
                raise UnoProtocolError(f"Invalid Uno debug frame: {text!r}.")
            reported_action = match.group(1)
        if reported_action != current_action:
            raise UnoProtocolError(
                "Uno action detail does not match the accepted route: "
                f"expected {current_action!r}, got {reported_action!r}.",
            )

    async def _best_effort_stop(self) -> None:
        try:
            await asyncio.shield(self.transport.write_command("STOP"))
        except BaseException as error:
            logger.warning("Could not send best-effort robot STOP: %s", error)

    async def execute_path(
        self,
        slot_id: str,
        operation: object = "PARKING",
    ) -> AsyncIterator[UnoStatus]:
        if not self.supports_operation(operation):
            name = _operation_name(operation) or repr(operation)
            raise UnsupportedRobotOperationError(
                f"Robot transport does not support operation {name}.",
            )

        command = path_command_for(slot_id)
        route_started = True
        done_seen = False
        try:
            await self.transport.write_command(command)
            accepted = False
            action_index = 0
            current_action: str | None = None
            while not done_seen:
                frame = await self.transport.read_status()
                text = self._codec._decode_ascii(frame)

                if text == "STOPPED" or text == "ERR" or text.startswith("ERR:"):
                    self._codec.decode(text)

                if not accepted:
                    if text.startswith("ROUTE_ACCEPTED:"):
                        raw_length = text.partition(":")[2]
                        if not raw_length.isdecimal() or int(raw_length) != len(command):
                            raise UnoProtocolError(
                                "Uno accepted a different route length: "
                                f"expected {len(command)}, got {raw_length!r}.",
                            )
                        accepted = True
                        yield UnoStatus.TRACING
                        continue
                    if text in {"READY", "PONG", "STATUS:IDLE"} or text.startswith(
                        "COMMANDS:",
                    ):
                        continue
                    raise UnoProtocolError(
                        f"Uno emitted {text!r} before accepting the current route.",
                    )

                if text.startswith("ACTION_START:"):
                    action = self._frame_action(text, "ACTION_START")
                    if current_action is not None or action_index >= len(command):
                        raise UnoProtocolError(
                            f"Unexpected Uno action start: {text!r}.",
                        )
                    expected_action = command[action_index]
                    if action != expected_action:
                        raise UnoProtocolError(
                            "Uno action order does not match the accepted route: "
                            f"expected {expected_action!r}, got {action!r}.",
                        )
                    current_action = action
                    yield self._codec.action_statuses[action]
                    continue

                if text.startswith("ACTION_DONE:"):
                    action = self._frame_action(text, "ACTION_DONE")
                    if current_action is None or action != current_action:
                        raise UnoProtocolError(
                            "Uno completed an action that was not active: "
                            f"active {current_action!r}, got {action!r}.",
                        )
                    current_action = None
                    action_index += 1
                    continue

                if text == "ROUTE_DONE":
                    if current_action is not None or action_index != len(command):
                        raise UnoProtocolError(
                            "Uno reported ROUTE_DONE before every accepted action "
                            f"completed ({action_index}/{len(command)}).",
                        )
                    done_seen = True
                    yield UnoStatus.DONE
                    continue

                if (
                    text.startswith("P_OBJECT_DETECTED:")
                    or text.startswith("B_MODE:")
                    or text.startswith("H_MODE:")
                    or text.startswith("DBG:SENSOR:")
                ):
                    self._validate_informational_frame(text, current_action)
                    continue

                if text.startswith("STATUS:RUNNING"):
                    match = re.search(r"(?:^|,)COMMAND=([LWCPSBH])(?:,|$)", text)
                    if (
                        current_action is None
                        or match is None
                        or match.group(1) != current_action
                    ):
                        raise UnoProtocolError(
                            f"Uno running status conflicts with the route: {text!r}.",
                        )
                    continue

                raise UnoProtocolError(
                    f"Unexpected Uno frame during the accepted route: {text!r}.",
                )
        except BaseException:
            if route_started and not done_seen:
                await self._best_effort_stop()
            raise

    @property
    def device(self) -> str:
        return self.transport.device

    @property
    def baudrate(self) -> int:
        return self.transport.baudrate

    @property
    def is_open(self) -> bool:
        return self.transport.is_open

    @property
    def last_sent_at(self) -> str | None:
        return self.transport.last_sent_at

    @property
    def last_received_at(self) -> str | None:
        return self.transport.last_received_at

    async def open(self) -> None:
        await self.transport.open()


class SimulatorRobotAdapter:
    """Deterministic Uno substitute used by the Pi demo and automated tests."""

    statuses = (
        UnoStatus.READY,
        UnoStatus.TRACING,
        UnoStatus.APPROACHING,
        UnoStatus.GRIPPING,
        UnoStatus.REVERSING,
        UnoStatus.DONE,
    )

    def __init__(self, step_delay_seconds: float = 1.05) -> None:
        self.step_delay_seconds = max(0.0, step_delay_seconds)
        self.commands: list[str] = []

    def supports_operation(self, operation: object) -> bool:
        return _operation_name(operation) in {"PARKING", "RETRIEVAL"}

    async def execute_path(
        self,
        slot_id: str,
        operation: object = "PARKING",
    ) -> AsyncIterator[UnoStatus]:
        if not self.supports_operation(operation):
            name = _operation_name(operation) or repr(operation)
            raise UnsupportedRobotOperationError(
                f"Robot simulator does not support operation {name}.",
            )
        command = path_command_for(slot_id)
        self.commands.append(command)
        for status in self.statuses:
            await asyncio.sleep(self.step_delay_seconds)
            yield status

    async def close(self) -> None:
        return None
