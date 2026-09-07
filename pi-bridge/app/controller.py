from __future__ import annotations

import asyncio
import logging
from copy import deepcopy
from typing import Any, Mapping
from uuid import uuid4

from .adapters.occupancy import MegaFrameParser, OccupancyState
from .adapters.robot import RobotAdapter, SimulatorRobotAdapter, UnoStatus
from .allocator import (
    InvalidExpectedMinutes as AllocatorInvalidExpectedMinutes,
    LotFull as AllocatorLotFull,
    SlotAllocator,
)
from .domain import JobKind, ParkingSession, RobotState, Vehicle, VehicleState, utc_now


logger = logging.getLogger("uvicorn.error.snap.jobs")


class ControllerError(RuntimeError):
    """Base error exposed by the Pi controller boundary."""


class ControllerBusy(ControllerError):
    """Raised when a conflicting robot job is already running."""


class VehicleNotFound(ControllerError):
    """Raised when a request cannot find a vehicle owned by the customer."""


class VehicleConflict(ControllerError):
    """Raised when the requested action conflicts with a vehicle state."""


class InvalidParkingDuration(ControllerError):
    """Raised when the parking duration does not match a supported bucket."""


class ParkingLotFull(ControllerError):
    """Raised when all six parking slots are unavailable."""


class JobNotFound(ControllerError):
    """Raised when a job identifier is unknown."""


class UnsupportedRobotOperation(ControllerError):
    """Raised when the connected robot firmware cannot execute an operation."""


class RobotInterlockActive(ControllerError):
    """Raised after a robot fault until an operator restores the standby state."""


class ParkingController:
    """Customer/vehicle parking domain with one serialized robot job.

    Hardware I/O is behind adapters. The default adapter deliberately simulates the
    Uno protocol so the same controller can be exercised without a connected robot.
    """

    lot_id = "demo-01"
    slot_ids = ("1", "2", "3", "4", "5", "6")
    legacy_customer_id = "legacy"

    _parking_status = {
        UnoStatus.READY: (
            RobotState.MOVING_TO_ENTRY,
            "로봇이 입구의 차량으로 이동 중이에요.",
            "ENTRY",
            24,
        ),
        UnoStatus.TRACING: (
            RobotState.CARRYING_TO_SLOT,
            "로봇이 주행 가능한 통로를 따라 이동 중이에요.",
            "AISLE",
            42,
        ),
        UnoStatus.APPROACHING: (
            RobotState.CARRYING_TO_SLOT,
            "배정된 주차면에 접근 중이에요.",
            "SLOT_APPROACH",
            66,
        ),
        UnoStatus.GRIPPING: (
            RobotState.ACQUIRING_VEHICLE,
            "차량을 안전하게 인수하고 있어요.",
            "SLOT_APPROACH",
            72,
        ),
        UnoStatus.REVERSING: (
            RobotState.CARRYING_TO_SLOT,
            "차량을 배정된 주차면에 배치하고 있어요.",
            "SLOT",
            82,
        ),
    }
    _retrieval_status = {
        UnoStatus.READY: (
            RobotState.MOVING_TO_PARKED_VEHICLE,
            "로봇이 주차된 차량으로 이동 중이에요.",
            "AISLE",
            72,
        ),
        UnoStatus.TRACING: (
            RobotState.MOVING_TO_PARKED_VEHICLE,
            "주차장 통로를 따라 차량으로 이동 중이에요.",
            "AISLE",
            66,
        ),
        UnoStatus.APPROACHING: (
            RobotState.MOVING_TO_PARKED_VEHICLE,
            "출차할 차량에 접근 중이에요.",
            "SLOT_APPROACH",
            76,
        ),
        UnoStatus.GRIPPING: (
            RobotState.ACQUIRING_VEHICLE,
            "출차할 차량을 안전하게 인수하고 있어요.",
            "SLOT",
            72,
        ),
        UnoStatus.REVERSING: (
            RobotState.CARRYING_TO_EXIT,
            "차량을 출구 인계 구역으로 옮기고 있어요.",
            "EXIT",
            36,
        ),
    }

    def __init__(
        self,
        step_delay_seconds: float = 1.05,
        *,
        robot_adapter: RobotAdapter | None = None,
        initial_occupancy: Mapping[str, str | OccupancyState] | None = None,
    ) -> None:
        self.step_delay_seconds = max(0.0, step_delay_seconds)
        self._lock = asyncio.Lock()
        self._subscribers: set[asyncio.Queue[dict[str, Any]]] = set()
        self._active_task: asyncio.Task[None] | None = None
        self._allocator = SlotAllocator()
        self._robot_adapter = robot_adapter or SimulatorRobotAdapter(
            self.step_delay_seconds,
        )
        occupancy = initial_occupancy or {}
        self._slots: list[dict[str, Any]] = []
        for slot_id in self.slot_ids:
            sensor_state = OccupancyState(occupancy.get(slot_id, OccupancyState.EMPTY))
            self._slots.append(
                {
                    "id": slot_id,
                    "sensorState": sensor_state.value,
                    "reservationState": "NONE",
                    "state": (
                        "OCCUPIED"
                        if sensor_state is OccupancyState.OCCUPIED
                        else "UNKNOWN"
                        if sensor_state is OccupancyState.UNKNOWN
                        else "AVAILABLE"
                    ),
                },
            )
        self._robot: dict[str, Any] = {
            "state": RobotState.IDLE_AT_STANDBY.value,
            "actionState": RobotState.IDLE_AT_STANDBY.value,
            "message": (
                "입구와 출구 사이 대기 위치에서 요청을 기다리고 있어요."
            ),
            "positionNode": "STANDBY",
            "positionPct": 18,
            "batteryPct": 100,
        }
        self._active_job: dict[str, Any] | None = None
        self._robot_interlocked = False
        self._robot_fault_message: str | None = None
        self._jobs: dict[str, dict[str, Any]] = {}
        self._vehicles: dict[str, Vehicle] = {}
        self._vehicle_by_number: dict[tuple[str, str], str] = {}
        self._sessions: dict[str, ParkingSession] = {}
        self._updated_at = self._now()

    @staticmethod
    def _now() -> str:
        return utc_now()

    @staticmethod
    def _normalize_customer(customer_id: str | None) -> str:
        normalized = (customer_id or ParkingController.legacy_customer_id).strip()
        if not normalized:
            raise VehicleConflict("고객 ID를 입력해 주세요.")
        return normalized

    @staticmethod
    def _normalize_vehicle_number(vehicle_number: str) -> str:
        normalized = "".join(vehicle_number.split()).upper()
        if not normalized:
            raise VehicleConflict("차량 번호를 입력해 주세요.")
        if len(normalized) > 32:
            raise VehicleConflict("차량 번호는 32자 이하여야 합니다.")
        return normalized

    def _public_job(self, job: Mapping[str, Any]) -> dict[str, Any]:
        return {
            key: deepcopy(value)
            for key, value in job.items()
            if key not in {"customerId", "vehicleNumber"}
        }

    def _idle_job(self) -> dict[str, Any]:
        return {
            "state": "IDLE",
            "message": self._robot["message"],
        }

    def _supports_robot_operation(self, operation: JobKind) -> bool:
        supports_operation = getattr(self._robot_adapter, "supports_operation", None)
        if supports_operation is None:
            return True
        return bool(supports_operation(operation.value))

    @property
    def robot_interlocked(self) -> bool:
        return self._robot_interlocked

    @property
    def robot_fault_message(self) -> str | None:
        return self._robot_fault_message

    def _ensure_robot_available(self) -> None:
        if self._robot_interlocked:
            raise RobotInterlockActive(
                "로봇 오류 인터록이 활성화됐습니다. 로봇을 대기 위치로 복구한 뒤 "
                "Gateway를 재시작해 주세요.",
            )

    def snapshot(self) -> dict[str, Any]:
        active_job = (
            self._public_job(self._active_job)
            if self._active_job is not None
            else None
        )
        slots = deepcopy(self._slots)
        return {
            "lotId": self.lot_id,
            "updatedAt": self._updated_at,
            "status": "BUSY" if active_job is not None else "IDLE",
            "isBusy": active_job is not None,
            "availableCount": sum(slot["state"] == "AVAILABLE" for slot in slots),
            "slots": slots,
            "robot": deepcopy(self._robot),
            "activeJob": active_job,
            "job": deepcopy(active_job) if active_job is not None else self._idle_job(),
        }

    def subscribe(self) -> asyncio.Queue[dict[str, Any]]:
        queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=16)
        self._subscribers.add(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue[dict[str, Any]]) -> None:
        self._subscribers.discard(queue)

    def register_vehicle(self, customer_id: str, vehicle_number: str) -> dict[str, Any]:
        customer = self._normalize_customer(customer_id)
        number = self._normalize_vehicle_number(vehicle_number)
        existing_id = self._vehicle_by_number.get((customer, number))
        if existing_id is not None:
            return self._vehicle_dict(self._vehicles[existing_id])

        vehicle_id = f"VEH-{uuid4().hex[:12].upper()}"
        vehicle = Vehicle(
            vehicle_id=vehicle_id,
            customer_id=customer,
            vehicle_number=number,
        )
        self._vehicles[vehicle_id] = vehicle
        self._vehicle_by_number[(customer, number)] = vehicle_id
        self._updated_at = self._now()
        return self._vehicle_dict(vehicle)

    def list_vehicles(self, customer_id: str) -> dict[str, Any]:
        customer = self._normalize_customer(customer_id)
        vehicles = [
            self._vehicle_dict(vehicle)
            for vehicle in self._vehicles.values()
            if vehicle.customer_id == customer
        ]
        return {"customerId": customer, "vehicles": vehicles}

    def _vehicle_dict(self, vehicle: Vehicle) -> dict[str, Any]:
        session = (
            self._sessions.get(vehicle.current_session_id)
            if vehicle.current_session_id is not None
            else None
        )
        return vehicle.to_dict(session)

    def _find_or_register_for_parking(
        self,
        *,
        customer_id: str | None,
        vehicle_id: str | None,
        vehicle_number: str | None,
    ) -> Vehicle:
        if vehicle_id and vehicle_number:
            raise VehicleConflict("vehicleId와 vehicleNumber 중 하나만 보내 주세요.")

        if vehicle_id:
            identifier = vehicle_id.strip()
            existing = self._vehicles.get(identifier)
            if existing is not None:
                if customer_id and existing.customer_id != self._normalize_customer(customer_id):
                    raise VehicleNotFound("해당 고객의 차량을 찾을 수 없습니다.")
                return existing
            customer = self._normalize_customer(customer_id)
            number = self._normalize_vehicle_number(identifier)
        elif vehicle_number:
            customer = self._normalize_customer(customer_id)
            number = self._normalize_vehicle_number(vehicle_number)
        else:
            raise VehicleConflict("vehicleId 또는 vehicleNumber를 입력해 주세요.")

        existing_id = self._vehicle_by_number.get((customer, number))
        if existing_id is not None:
            return self._vehicles[existing_id]
        registered = self.register_vehicle(customer, number)
        return self._vehicles[registered["vehicleId"]]

    def _find_for_retrieval(
        self,
        *,
        customer_id: str | None,
        vehicle_id: str | None,
        vehicle_number: str | None,
    ) -> Vehicle:
        if vehicle_id and vehicle_number:
            raise VehicleConflict("vehicleId와 vehicleNumber 중 하나만 보내 주세요.")
        if vehicle_id:
            identifier = vehicle_id.strip()
            existing = self._vehicles.get(identifier)
            if existing is not None:
                if customer_id and existing.customer_id != self._normalize_customer(customer_id):
                    raise VehicleNotFound("해당 고객의 차량을 찾을 수 없습니다.")
                return existing
            customer = self._normalize_customer(customer_id)
            number = self._normalize_vehicle_number(identifier)
        elif vehicle_number:
            customer = self._normalize_customer(customer_id)
            number = self._normalize_vehicle_number(vehicle_number)
        else:
            raise VehicleConflict("vehicleId 또는 vehicleNumber를 입력해 주세요.")

        existing_id = self._vehicle_by_number.get((customer, number))
        if existing_id is None:
            raise VehicleNotFound(f"차량 {number}을(를) 찾을 수 없습니다.")
        return self._vehicles[existing_id]

    async def request_parking(
        self,
        vehicle_id: str | None = None,
        expected_minutes: int = 120,
        preference: str | None = None,
        *,
        customer_id: str | None = None,
        vehicle_number: str | None = None,
    ) -> dict[str, Any]:
        del preference  # Legacy Web field; slot allocation is server-owned.
        self._ensure_robot_available()
        if not self._supports_robot_operation(JobKind.PARKING):
            raise UnsupportedRobotOperation(
                "연결된 로봇 펌웨어가 입차 동작을 지원하지 않습니다.",
            )
        if isinstance(expected_minutes, bool):
            raise InvalidParkingDuration(
                "예상 주차시간은 60, 120, 180, 240분 중 하나여야 합니다.",
            )
        try:
            self._allocator.allocation_order(expected_minutes)
        except AllocatorInvalidExpectedMinutes as error:
            raise InvalidParkingDuration(str(error)) from error

        async with self._lock:
            if self._active_job is not None:
                raise ControllerBusy("다른 주차·출차 작업이 진행 중입니다.")
            vehicle = self._find_or_register_for_parking(
                customer_id=customer_id,
                vehicle_id=vehicle_id,
                vehicle_number=vehicle_number,
            )
            if vehicle.state not in {
                VehicleState.READY_TO_PARK,
                VehicleState.RETRIEVED,
            }:
                raise VehicleConflict(
                    "이미 입차했거나 입차 작업 중인 차량입니다.",
                )
            try:
                target = self._allocator.select(expected_minutes, self._slots)
            except AllocatorLotFull as error:
                raise ParkingLotFull("현재 주차장이 만차입니다.") from error

            self._reserve_target(target)
            now = self._now()
            session_id = f"SES-{uuid4().hex[:12].upper()}"
            session = ParkingSession(
                session_id=session_id,
                customer_id=vehicle.customer_id,
                vehicle_id=vehicle.vehicle_id,
                expected_minutes=expected_minutes,
                slot_id=target,
                state=VehicleState.PARKING_REQUESTED,
                created_at=now,
                updated_at=now,
            )
            self._sessions[session_id] = session
            vehicle.state = VehicleState.PARKING_REQUESTED
            vehicle.slot_id = target
            vehicle.expected_minutes = expected_minutes
            vehicle.current_session_id = session_id
            vehicle.updated_at = now

            request_id = f"REQ-{uuid4().hex[:8].upper()}"
            job = {
                "id": request_id,
                "kind": JobKind.PARKING.value,
                "state": "REQUESTED",
                "customerId": vehicle.customer_id,
                "vehicleId": vehicle.vehicle_id,
                "sessionId": session_id,
                "targetSlot": target,
                "expectedMinutes": expected_minutes,
                "allocationPolicy": self._allocator.policy_code(expected_minutes),
                "message": "주차 요청을 로봇 제어기에 전달했어요.",
                "startedAt": now,
                "updatedAt": now,
            }
            self._active_job = job
            self._jobs[request_id] = job
            self._set_robot(
                RobotState.MOVING_TO_ENTRY,
                job["message"],
                "ENTRY",
                24,
            )
            self._updated_at = now
            self._active_task = asyncio.create_task(self._run_job(request_id))

        await self._broadcast("JOB_REQUESTED", job["message"])
        return {"requestId": request_id, "snapshot": self.snapshot()}

    async def confirm_parking(self, request_id: str) -> dict[str, Any]:
        if request_id not in self._jobs:
            raise JobNotFound("해당 주차 요청을 찾을 수 없습니다.")
        return {"requestId": request_id, "confirmed": True, "snapshot": self.snapshot()}

    async def request_retrieval(
        self,
        vehicle_id: str | None = None,
        *,
        customer_id: str | None = None,
        vehicle_number: str | None = None,
    ) -> dict[str, Any]:
        self._ensure_robot_available()
        if not self._supports_robot_operation(JobKind.RETRIEVAL):
            raise UnsupportedRobotOperation(
                "현재 로봇 펌웨어에는 출차 경로가 정의되지 않았습니다.",
            )
        async with self._lock:
            if self._active_job is not None:
                raise ControllerBusy("다른 주차·출차 작업이 진행 중입니다.")
            vehicle = self._find_for_retrieval(
                customer_id=customer_id,
                vehicle_id=vehicle_id,
                vehicle_number=vehicle_number,
            )
            if vehicle.state is not VehicleState.PARKED or vehicle.slot_id is None:
                raise VehicleConflict("출차할 수 있는 주차 완료 차량이 아닙니다.")
            parked_slot = next(
                (
                    slot
                    for slot in self._slots
                    if slot["id"] == vehicle.slot_id
                    and slot.get("vehicleId") == vehicle.vehicle_id
                ),
                None,
            )
            if parked_slot is None:
                raise VehicleNotFound("차량의 주차 위치를 찾을 수 없습니다.")

            now = self._now()
            vehicle.state = VehicleState.RETRIEVAL_REQUESTED
            vehicle.updated_at = now
            session = self._current_session(vehicle)
            session.state = VehicleState.RETRIEVAL_REQUESTED
            session.updated_at = now
            request_id = f"RET-{uuid4().hex[:8].upper()}"
            job = {
                "id": request_id,
                "kind": JobKind.RETRIEVAL.value,
                "state": "REQUESTED",
                "customerId": vehicle.customer_id,
                "vehicleId": vehicle.vehicle_id,
                "sessionId": session.session_id,
                "targetSlot": vehicle.slot_id,
                "message": f"{vehicle.slot_id}번 주차면으로 이동 중이에요.",
                "startedAt": now,
                "updatedAt": now,
            }
            self._active_job = job
            self._jobs[request_id] = job
            self._set_robot(
                RobotState.MOVING_TO_PARKED_VEHICLE,
                job["message"],
                "AISLE",
                72,
            )
            self._updated_at = now
            self._active_task = asyncio.create_task(self._run_job(request_id))

        await self._broadcast("RETRIEVAL_REQUESTED", job["message"])
        return {"requestId": request_id, "snapshot": self.snapshot()}

    def get_job(self, job_id: str) -> dict[str, Any]:
        job = self._jobs.get(job_id)
        if job is None:
            raise JobNotFound("해당 작업을 찾을 수 없습니다.")
        return self._public_job(job)

    async def wait_until(self, state: str, timeout: float = 5.0) -> None:
        expected = state.upper()

        def matches() -> bool:
            if expected == "IDLE":
                return self._active_job is None
            if self._active_job is not None and self._active_job["state"] == expected:
                return True
            if self._robot["actionState"] == expected:
                return True
            return any(vehicle.state.value == expected for vehicle in self._vehicles.values())

        async def wait() -> None:
            while not matches():
                await asyncio.sleep(0.005)

        await asyncio.wait_for(wait(), timeout=timeout)

    async def ingest_occupancy_frame(self, frame: str | bytes) -> dict[str, Any]:
        occupancy = MegaFrameParser.parse(frame)
        return await self.update_occupancy_states(occupancy)

    async def update_occupancy_states(
        self,
        occupancy: Mapping[str, str | OccupancyState],
    ) -> dict[str, Any]:
        if set(occupancy) != set(self.slot_ids):
            raise ValueError("Occupancy update must contain slots 1 through 6.")
        normalized = {
            slot_id: OccupancyState(occupancy[slot_id])
            for slot_id in self.slot_ids
        }
        async with self._lock:
            for slot in self._slots:
                incoming = normalized[slot["id"]]
                known_vehicle = slot.get("vehicleId") is not None
                if known_vehicle and incoming is OccupancyState.EMPTY:
                    slot["sensorState"] = OccupancyState.UNKNOWN.value
                else:
                    slot["sensorState"] = incoming.value
                self._refresh_slot_state(slot)
            self._updated_at = self._now()
        await self._broadcast("OCCUPANCY_UPDATED", "주차면 센서 상태가 갱신됐어요.")
        return self.snapshot()

    async def update_occupancy(self, frame: str | bytes) -> dict[str, Any]:
        return await self.ingest_occupancy_frame(frame)

    async def mark_occupancy_unknown(self) -> dict[str, Any]:
        async with self._lock:
            for slot in self._slots:
                slot["sensorState"] = OccupancyState.UNKNOWN.value
                self._refresh_slot_state(slot)
            self._updated_at = self._now()
        await self._broadcast("OCCUPANCY_STALE", "주차면 센서 연결을 확인해 주세요.")
        return self.snapshot()

    def _reserve_target(self, target: str) -> None:
        slot = next(slot for slot in self._slots if slot["id"] == target)
        if slot["state"] != "AVAILABLE":
            raise ParkingLotFull("현재 주차장이 만차입니다.")
        slot["reservationState"] = "RESERVED"
        slot["state"] = "RESERVED"
        slot.pop("vehicleId", None)

    def _refresh_slot_state(self, slot: dict[str, Any]) -> None:
        if slot["sensorState"] == OccupancyState.UNKNOWN.value:
            slot["state"] = "UNKNOWN"
        elif slot["reservationState"] == "RESERVED":
            slot["state"] = "RESERVED"
        elif slot["sensorState"] == OccupancyState.OCCUPIED.value:
            slot["state"] = "OCCUPIED"
        else:
            slot["state"] = "AVAILABLE"

    def _current_session(self, vehicle: Vehicle) -> ParkingSession:
        if vehicle.current_session_id is None:
            raise VehicleConflict("차량의 주차 세션을 찾을 수 없습니다.")
        session = self._sessions.get(vehicle.current_session_id)
        if session is None:
            raise VehicleConflict("차량의 주차 세션을 찾을 수 없습니다.")
        return session

    def _set_robot(
        self,
        state: RobotState,
        message: str,
        position_node: str,
        position_pct: int,
    ) -> None:
        self._robot.update(
            {
                "state": state.value,
                "actionState": state.value,
                "message": message,
                "positionNode": position_node,
                "positionPct": position_pct,
            },
        )

    async def _run_job(self, job_id: str) -> None:
        try:
            job = self._jobs[job_id]
            logger.info(
                "Robot job start jobId=%s kind=%s slot=%s",
                job_id,
                job["kind"],
                job["targetSlot"],
            )
            async for status in self._robot_adapter.execute_path(
                job["targetSlot"],
                operation=job["kind"],
            ):
                if status is UnoStatus.DONE:
                    await self._complete_robot_path(job_id)
                    logger.info("Robot job route complete jobId=%s", job_id)
                    return
                await self._apply_robot_status(job_id, status)
            raise RuntimeError("Uno status stream ended before DONE.")
        except asyncio.CancelledError:
            raise
        except Exception as error:
            logger.error("Robot job failed jobId=%s error=%s", job_id, error)
            await self._fail_job(job_id, error)

    async def _apply_robot_status(self, job_id: str, status: UnoStatus) -> None:
        async with self._lock:
            if self._active_job is None or self._active_job["id"] != job_id:
                return
            job = self._active_job
            vehicle = self._vehicles[job["vehicleId"]]
            session = self._current_session(vehicle)
            mapping = (
                self._parking_status
                if job["kind"] == JobKind.PARKING.value
                else self._retrieval_status
            )
            robot_state, message, position_node, position_pct = mapping[status]
            now = self._now()
            job.update(
                {
                    "state": "RUNNING",
                    "unoStatus": status.value,
                    "message": message,
                    "updatedAt": now,
                },
            )
            vehicle.state = (
                VehicleState.PARKING_IN_PROGRESS
                if job["kind"] == JobKind.PARKING.value
                else VehicleState.RETRIEVING
            )
            vehicle.updated_at = now
            session.state = vehicle.state
            session.updated_at = now
            self._set_robot(robot_state, message, position_node, position_pct)
            self._robot["batteryPct"] = max(0, self._robot["batteryPct"] - 1)
            self._updated_at = now
        await self._broadcast(status.value, message)

    async def _complete_robot_path(self, job_id: str) -> None:
        async with self._lock:
            if self._active_job is None or self._active_job["id"] != job_id:
                return
            job = self._active_job
            vehicle = self._vehicles[job["vehicleId"]]
            session = self._current_session(vehicle)
            target = job["targetSlot"]
            slot = next(slot for slot in self._slots if slot["id"] == target)
            now = self._now()
            if job["kind"] == JobKind.PARKING.value:
                slot.update(
                    {
                        "sensorState": OccupancyState.OCCUPIED.value,
                        "reservationState": "NONE",
                        "state": "OCCUPIED",
                        "vehicleId": vehicle.vehicle_id,
                    },
                )
                vehicle.state = VehicleState.PARKED
                session.state = VehicleState.PARKED
                event_type = "PARKED"
                message = (
                    "주차가 완료됐어요. 로봇이 대기 위치로 복귀 중이에요."
                )
            else:
                slot.update(
                    {
                        "sensorState": OccupancyState.EMPTY.value,
                        "reservationState": "NONE",
                        "state": "AVAILABLE",
                    },
                )
                slot.pop("vehicleId", None)
                vehicle.state = VehicleState.RETRIEVED
                vehicle.slot_id = None
                session.state = VehicleState.RETRIEVED
                session.completed_at = now
                event_type = "RETRIEVED"
                message = (
                    "출차가 완료됐어요. 로봇이 대기 위치로 복귀 중이에요."
                )
            vehicle.updated_at = now
            session.updated_at = now
            job.update(
                {
                    "state": "RETURNING_TO_STANDBY",
                    "unoStatus": UnoStatus.DONE.value,
                    "message": message,
                    "updatedAt": now,
                },
            )
            self._set_robot(
                RobotState.RETURNING_TO_STANDBY,
                message,
                "AISLE",
                28,
            )
            self._updated_at = now
        await self._broadcast(event_type, message)

        await asyncio.sleep(self.step_delay_seconds)
        async with self._lock:
            if self._active_job is None or self._active_job["id"] != job_id:
                return
            now = self._now()
            self._active_job.update(
                {
                    "state": "COMPLETED",
                    "message": "로봇이 대기 위치로 복귀했어요.",
                    "updatedAt": now,
                    "completedAt": now,
                },
            )
            self._set_robot(
                RobotState.IDLE_AT_STANDBY,
                "입구와 출구 사이 대기 위치에서 요청을 기다리고 있어요.",
                "STANDBY",
                18,
            )
            self._active_job = None
            self._updated_at = now
        await self._broadcast("ROBOT_IDLE", "로봇이 대기 위치로 복귀했어요.")

    async def _fail_job(self, job_id: str, error: Exception) -> None:
        async with self._lock:
            if self._active_job is None or self._active_job["id"] != job_id:
                return
            job = self._active_job
            vehicle = self._vehicles[job["vehicleId"]]
            session = self._current_session(vehicle)
            now = self._now()
            if job["kind"] == JobKind.PARKING.value:
                slot = next(slot for slot in self._slots if slot["id"] == job["targetSlot"])
                slot["reservationState"] = "NONE"
                slot.pop("vehicleId", None)
                self._refresh_slot_state(slot)
            vehicle.state = VehicleState.ERROR
            vehicle.updated_at = now
            session.state = VehicleState.ERROR
            session.updated_at = now
            message = f"로봇 작업을 완료하지 못했습니다: {error}"
            self._robot_interlocked = True
            self._robot_fault_message = message
            job.update(
                {
                    "state": "FAILED",
                    "message": message,
                    "updatedAt": now,
                    "completedAt": now,
                },
            )
            self._set_robot(RobotState.FAULT, message, "UNKNOWN", self._robot["positionPct"])
            self._active_job = None
            self._updated_at = now
        await self._broadcast("JOB_FAILED", message)

    async def _broadcast(self, event_type: str, message: str) -> None:
        event = {
            "type": event_type,
            "message": message,
            "snapshot": self.snapshot(),
        }
        for queue in tuple(self._subscribers):
            if queue.full():
                try:
                    queue.get_nowait()
                except asyncio.QueueEmpty:
                    pass
            queue.put_nowait(deepcopy(event))

    async def close(self) -> None:
        task = self._active_task
        if task is not None and not task.done():
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)
