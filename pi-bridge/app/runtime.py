from __future__ import annotations

import asyncio
import logging
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Mapping

from .adapters.occupancy import (
    DEFAULT_MEGA_BAUDRATE,
    DEFAULT_MEGA_DEVICE,
    DEFAULT_MEGA_READ_TIMEOUT_SECONDS,
    MegaBitmaskParser,
    MegaFrameError,
    OccupancyState,
    SerialOccupancyAdapter,
)
from .adapters.robot import (
    DEFAULT_ROBOT_BAUDRATE,
    DEFAULT_ROBOT_DEVICE,
    DEFAULT_ROBOT_READ_TIMEOUT_SECONDS,
    SerialRobotAdapter,
    SimulatorRobotAdapter,
)
from .adapters.serial_transport import SerialReadTimeout, SerialTransportError
from .controller import ParkingController


logger = logging.getLogger("uvicorn.error.snap.hardware")

SIMULATOR_MODE = "simulator"
SERIAL_MODE = "serial"


def _positive_int(environment: Mapping[str, str], name: str, default: int) -> int:
    raw_value = environment.get(name, str(default)).strip()
    try:
        value = int(raw_value)
    except ValueError as error:
        raise ValueError(
            f"{name} must be a positive integer, got {raw_value!r}.",
        ) from error
    if value <= 0:
        raise ValueError(f"{name} must be a positive integer, got {raw_value!r}.")
    return value


def _non_negative_float(
    environment: Mapping[str, str],
    name: str,
    default: float,
) -> float:
    raw_value = environment.get(name, str(default)).strip()
    try:
        value = float(raw_value)
    except ValueError as error:
        raise ValueError(
            f"{name} must be zero or positive, got {raw_value!r}.",
        ) from error
    if value < 0:
        raise ValueError(f"{name} must be zero or positive, got {raw_value!r}.")
    return value


def _positive_float(
    environment: Mapping[str, str],
    name: str,
    default: float,
) -> float:
    value = _non_negative_float(environment, name, default)
    if value == 0:
        raw_value = environment.get(name, str(default)).strip()
        raise ValueError(f"{name} must be positive, got {raw_value!r}.")
    return value


@dataclass(frozen=True)
class GatewaySettings:
    hardware_mode: str = SIMULATOR_MODE
    step_delay_seconds: float = 1.05
    mega_port: str = DEFAULT_MEGA_DEVICE
    mega_baud: int = DEFAULT_MEGA_BAUDRATE
    mega_read_timeout_seconds: float = DEFAULT_MEGA_READ_TIMEOUT_SECONDS
    mega_initial_mask: int | None = None
    robot_port: str = DEFAULT_ROBOT_DEVICE
    robot_baud: int = DEFAULT_ROBOT_BAUDRATE
    robot_read_timeout_seconds: float = DEFAULT_ROBOT_READ_TIMEOUT_SECONDS
    robot_startup_timeout_seconds: float = 5.0
    serial_reconnect_delay_seconds: float = 1.0

    @classmethod
    def from_environment(
        cls,
        environment: Mapping[str, str] | None = None,
    ) -> GatewaySettings:
        values = os.environ if environment is None else environment
        hardware_mode = (
            values.get("SNAP_HARDWARE_MODE", SIMULATOR_MODE).strip().lower()
        )
        if hardware_mode not in {SIMULATOR_MODE, SERIAL_MODE}:
            raise ValueError(
                "SNAP_HARDWARE_MODE must be 'simulator' or 'serial', "
                f"got {hardware_mode!r}.",
            )

        mega_port = values.get("SNAP_MEGA_PORT", DEFAULT_MEGA_DEVICE).strip()
        robot_port = values.get("SNAP_ROBOT_PORT", DEFAULT_ROBOT_DEVICE).strip()
        if not mega_port:
            raise ValueError("SNAP_MEGA_PORT must not be empty.")
        if not robot_port:
            raise ValueError("SNAP_ROBOT_PORT must not be empty.")
        if hardware_mode == SERIAL_MODE and mega_port == robot_port:
            raise ValueError(
                "SNAP_MEGA_PORT and SNAP_ROBOT_PORT must be different devices.",
            )

        raw_initial_mask = values.get("SNAP_MEGA_INITIAL_MASK")
        initial_mask: int | None = None
        if raw_initial_mask is not None and raw_initial_mask.strip():
            normalized = raw_initial_mask.strip()
            MegaBitmaskParser.parse(normalized)
            initial_mask = int(normalized, 10)

        return cls(
            hardware_mode=hardware_mode,
            step_delay_seconds=_non_negative_float(
                values,
                "SNAP_STEP_DELAY_SECONDS",
                1.05,
            ),
            mega_port=mega_port,
            mega_baud=_positive_int(
                values,
                "SNAP_MEGA_BAUD",
                DEFAULT_MEGA_BAUDRATE,
            ),
            mega_read_timeout_seconds=_positive_float(
                values,
                "SNAP_MEGA_READ_TIMEOUT_SECONDS",
                DEFAULT_MEGA_READ_TIMEOUT_SECONDS,
            ),
            mega_initial_mask=initial_mask,
            robot_port=robot_port,
            robot_baud=_positive_int(
                values,
                "SNAP_ROBOT_BAUD",
                DEFAULT_ROBOT_BAUDRATE,
            ),
            robot_read_timeout_seconds=_positive_float(
                values,
                "SNAP_ROBOT_READ_TIMEOUT_SECONDS",
                DEFAULT_ROBOT_READ_TIMEOUT_SECONDS,
            ),
            robot_startup_timeout_seconds=_positive_float(
                values,
                "SNAP_ROBOT_STARTUP_TIMEOUT_SECONDS",
                5.0,
            ),
            serial_reconnect_delay_seconds=_positive_float(
                values,
                "SNAP_SERIAL_RECONNECT_DELAY_SECONDS",
                1.0,
            ),
        )

    def initial_occupancy(self) -> dict[str, OccupancyState] | None:
        if self.hardware_mode != SERIAL_MODE:
            return None
        if self.mega_initial_mask is not None:
            return MegaBitmaskParser.parse(str(self.mega_initial_mask))
        return {
            str(slot_id): OccupancyState.UNKNOWN
            for slot_id in range(1, MegaBitmaskParser.slot_count + 1)
        }


class GatewayRuntime:
    """Own the controller and, in serial mode, both Arduino connections."""

    def __init__(
        self,
        *,
        settings: GatewaySettings,
        controller: ParkingController,
        occupancy_adapter: SerialOccupancyAdapter | None = None,
        robot_adapter: SerialRobotAdapter | SimulatorRobotAdapter,
    ) -> None:
        self.settings = settings
        self.controller = controller
        self.occupancy_adapter = occupancy_adapter
        self.robot_adapter = robot_adapter
        self._occupancy_task: asyncio.Task[None] | None = None
        self._started = False
        self._occupancy_initialized = settings.mega_initial_mask is not None
        self._occupancy_source = (
            "configured-initial-mask"
            if self._occupancy_initialized
            else "waiting-for-mega-frame"
        )
        self._last_occupancy_frame_at: str | None = None
        self._last_occupancy_error: str | None = None
        self._occupancy_faulted = False
        self._mega_verified = False
        self._robot_ready = False
        self._last_robot_probe_at: str | None = None

    @classmethod
    def from_settings(cls, settings: GatewaySettings) -> GatewayRuntime:
        if settings.hardware_mode == SERIAL_MODE:
            occupancy_adapter = SerialOccupancyAdapter(
                device=settings.mega_port,
                baudrate=settings.mega_baud,
                read_timeout_seconds=settings.mega_read_timeout_seconds,
            )
            robot_adapter = SerialRobotAdapter(
                device=settings.robot_port,
                baudrate=settings.robot_baud,
                read_timeout_seconds=settings.robot_read_timeout_seconds,
            )
            controller = ParkingController(
                step_delay_seconds=settings.step_delay_seconds,
                robot_adapter=robot_adapter,
                initial_occupancy=settings.initial_occupancy(),
            )
            return cls(
                settings=settings,
                controller=controller,
                occupancy_adapter=occupancy_adapter,
                robot_adapter=robot_adapter,
            )

        robot_adapter = SimulatorRobotAdapter(settings.step_delay_seconds)
        controller = ParkingController(
            step_delay_seconds=settings.step_delay_seconds,
            robot_adapter=robot_adapter,
        )
        return cls(
            settings=settings,
            controller=controller,
            robot_adapter=robot_adapter,
        )

    @classmethod
    def from_environment(
        cls,
        environment: Mapping[str, str] | None = None,
    ) -> GatewayRuntime:
        return cls.from_settings(GatewaySettings.from_environment(environment))

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat()

    async def start(self) -> None:
        if self._started:
            return
        if self.settings.hardware_mode == SERIAL_MODE:
            assert self.occupancy_adapter is not None
            try:
                await self.occupancy_adapter.open()
                await self.robot_adapter.open()
                probe = getattr(self.robot_adapter, "probe", None)
                if probe is None:
                    raise RuntimeError("Serial robot adapter does not provide probe().")
                try:
                    await asyncio.wait_for(
                        probe(),
                        timeout=self.settings.robot_startup_timeout_seconds,
                    )
                except TimeoutError as error:
                    raise SerialReadTimeout(
                        "Robot did not answer PING within "
                        f"{self.settings.robot_startup_timeout_seconds} seconds.",
                    ) from error
                self._robot_ready = True
                self._last_robot_probe_at = self._now()
            except Exception:
                await asyncio.gather(
                    self.occupancy_adapter.close(),
                    self.robot_adapter.close(),
                    return_exceptions=True,
                )
                logger.exception(
                    "SNAP hardware startup failed (Mega %s @ %s, robot %s @ %s).",
                    self.settings.mega_port,
                    self.settings.mega_baud,
                    self.settings.robot_port,
                    self.settings.robot_baud,
                )
                raise
            self._occupancy_task = asyncio.create_task(
                self._read_occupancy_forever(),
                name="snap-mega-occupancy",
            )
            logger.info(
                "SNAP hardware connected: Mega %s @ %s, robot %s @ %s.",
                self.settings.mega_port,
                self.settings.mega_baud,
                self.settings.robot_port,
                self.settings.robot_baud,
            )
        self._started = True

    async def _mark_occupancy_fault(self, error: Exception) -> None:
        self._last_occupancy_error = str(error)
        self._mega_verified = False
        if not self._occupancy_faulted:
            self._occupancy_faulted = True
            await self.controller.mark_occupancy_unknown()

    async def _read_occupancy_forever(self) -> None:
        assert self.occupancy_adapter is not None
        while True:
            try:
                occupancy = await self.occupancy_adapter.read_occupancy()
                await self.controller.update_occupancy_states(occupancy)
                occupied = [
                    slot_id
                    for slot_id, state in occupancy.items()
                    if state is OccupancyState.OCCUPIED
                ]
                self._occupancy_initialized = True
                self._mega_verified = True
                self._occupancy_source = "mega-serial-frame"
                self._last_occupancy_frame_at = self._now()
                self._last_occupancy_error = None
                self._occupancy_faulted = False
                logger.info(
                    "SNAP Mega occupancy applied: occupied slots=%s.",
                    occupied or "none",
                )
            except SerialReadTimeout:
                # The Mega firmware is event-driven and legitimately remains silent
                # while no sensor state changes.
                continue
            except asyncio.CancelledError:
                raise
            except (MegaFrameError, SerialTransportError) as error:
                logger.warning("SNAP Mega occupancy unavailable: %s", error)
                await self._mark_occupancy_fault(error)
                await asyncio.sleep(self.settings.serial_reconnect_delay_seconds)
            except Exception as error:
                logger.exception("Unexpected SNAP Mega reader failure.")
                await self._mark_occupancy_fault(error)
                await asyncio.sleep(self.settings.serial_reconnect_delay_seconds)

    def health(self) -> dict[str, object]:
        if self.settings.hardware_mode != SERIAL_MODE:
            return {"status": "ok", "mode": "pi-simulator-multi-vehicle"}

        assert self.occupancy_adapter is not None
        mega_connected = self.occupancy_adapter.is_open
        robot_connected = self.robot_adapter.is_open
        robot_interlocked = self.controller.robot_interlocked
        robot_ready = self._robot_ready and not robot_interlocked
        ready = (
            mega_connected
            and robot_connected
            and self._occupancy_initialized
            and self._mega_verified
            and self._last_occupancy_error is None
            and robot_ready
        )
        status = "ok" if ready else "degraded"
        return {
            "status": status,
            "mode": "pi-hardware-snap-code",
            "hardware": {
                "mega": {
                    "device": self.settings.mega_port,
                    "baudrate": self.settings.mega_baud,
                    "connected": mega_connected,
                    "verified": self._mega_verified,
                    "occupancyInitialized": self._occupancy_initialized,
                    "occupancySource": self._occupancy_source,
                    "lastFrameAt": self._last_occupancy_frame_at,
                    "lastError": self._last_occupancy_error,
                },
                "robot": {
                    "device": self.settings.robot_port,
                    "baudrate": self.settings.robot_baud,
                    "connected": robot_connected,
                    "ready": robot_ready,
                    "interlocked": robot_interlocked,
                    "lastProbeAt": self._last_robot_probe_at,
                    "lastSentAt": getattr(self.robot_adapter, "last_sent_at", None),
                    "lastFrameAt": getattr(
                        self.robot_adapter,
                        "last_received_at",
                        None,
                    ),
                    "lastError": self.controller.robot_fault_message,
                    "supportedOperations": ["PARKING"],
                },
            },
        }

    async def close(self) -> None:
        occupancy_task = self._occupancy_task
        if occupancy_task is not None and not occupancy_task.done():
            occupancy_task.cancel()
            await asyncio.gather(occupancy_task, return_exceptions=True)
        self._occupancy_task = None

        await self.controller.close()
        closers = [self.robot_adapter.close()]
        if self.occupancy_adapter is not None:
            closers.append(self.occupancy_adapter.close())
        results = await asyncio.gather(*closers, return_exceptions=True)
        for result in results:
            if isinstance(result, Exception):
                logger.warning("SNAP hardware close failed: %s", result)
        self._robot_ready = False
        self._started = False
