from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from typing import Any


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class VehicleState(str, Enum):
    READY_TO_PARK = "READY_TO_PARK"
    PARKING_REQUESTED = "PARKING_REQUESTED"
    PARKING_IN_PROGRESS = "PARKING_IN_PROGRESS"
    PARKED = "PARKED"
    RETRIEVAL_REQUESTED = "RETRIEVAL_REQUESTED"
    RETRIEVING = "RETRIEVING"
    RETRIEVED = "RETRIEVED"
    ERROR = "ERROR"


class RobotState(str, Enum):
    IDLE_AT_STANDBY = "IDLE_AT_STANDBY"
    MOVING_TO_ENTRY = "MOVING_TO_ENTRY"
    ACQUIRING_VEHICLE = "ACQUIRING_VEHICLE"
    CARRYING_TO_SLOT = "CARRYING_TO_SLOT"
    MOVING_TO_PARKED_VEHICLE = "MOVING_TO_PARKED_VEHICLE"
    CARRYING_TO_EXIT = "CARRYING_TO_EXIT"
    RETURNING_TO_STANDBY = "RETURNING_TO_STANDBY"
    OFFLINE = "OFFLINE"
    FAULT = "FAULT"


class JobKind(str, Enum):
    PARKING = "PARKING"
    RETRIEVAL = "RETRIEVAL"


@dataclass
class Vehicle:
    vehicle_id: str
    customer_id: str
    vehicle_number: str
    state: VehicleState = VehicleState.READY_TO_PARK
    slot_id: str | None = None
    expected_minutes: int | None = None
    current_session_id: str | None = None
    updated_at: str = ""

    def __post_init__(self) -> None:
        if not self.updated_at:
            self.updated_at = utc_now()

    def to_dict(self, session: ParkingSession | None = None) -> dict[str, Any]:
        result: dict[str, Any] = {
            "vehicleId": self.vehicle_id,
            "customerId": self.customer_id,
            "vehicleNumber": self.vehicle_number,
            "state": self.state.value,
            "updatedAt": self.updated_at,
        }
        if self.slot_id is not None:
            result["slotId"] = self.slot_id
        if self.expected_minutes is not None:
            result["expectedMinutes"] = self.expected_minutes
        if self.current_session_id is not None:
            result["sessionId"] = self.current_session_id
        if session is not None:
            result["currentSession"] = session.to_dict()
        return result


@dataclass
class ParkingSession:
    session_id: str
    customer_id: str
    vehicle_id: str
    expected_minutes: int
    slot_id: str
    state: VehicleState
    created_at: str
    updated_at: str
    completed_at: str | None = None

    def to_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {
            "sessionId": self.session_id,
            "customerId": self.customer_id,
            "vehicleId": self.vehicle_id,
            "expectedMinutes": self.expected_minutes,
            "slotId": self.slot_id,
            "state": self.state.value,
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
        }
        if self.completed_at is not None:
            result["completedAt"] = self.completed_at
        return result

