from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import Any


ALLOWED_EXPECTED_MINUTES = frozenset({60, 120, 180, 240})


class AllocationError(RuntimeError):
    """Base error for deterministic slot allocation."""


class InvalidExpectedMinutes(AllocationError):
    """Raised when an unsupported parking-duration bucket is supplied."""


class LotFull(AllocationError):
    """Raised when there is no slot that can be reserved."""


class SlotAllocator:
    """Choose a free slot from the server-owned distance policy."""

    slot_ids = ("1", "2", "3", "4", "5", "6")
    _order_by_minutes = {
        60: ("1", "2", "3", "4", "5", "6"),
        120: ("1", "2", "3", "4", "5", "6"),
        180: ("4", "5", "6", "3", "2", "1"),
        240: ("6", "5", "4", "3", "2", "1"),
    }

    def allocation_order(self, expected_minutes: int) -> tuple[str, ...]:
        if expected_minutes not in ALLOWED_EXPECTED_MINUTES:
            raise InvalidExpectedMinutes(
                "예상 주차시간은 60, 120, 180, 240분 중 하나여야 합니다.",
            )
        return self._order_by_minutes[expected_minutes]

    def select(
        self,
        expected_minutes: int,
        slots: Iterable[Mapping[str, Any]],
    ) -> str:
        available = {
            str(slot["id"])
            for slot in slots
            if slot.get("state") == "AVAILABLE"
        }
        for slot_id in self.allocation_order(expected_minutes):
            if slot_id in available:
                return slot_id
        raise LotFull("현재 주차장이 만차입니다.")

    @staticmethod
    def policy_code(expected_minutes: int) -> str:
        if expected_minutes in {60, 120}:
            return "NEAR_FIRST"
        if expected_minutes == 180:
            return "FAR_GROUP_FIRST"
        if expected_minutes == 240:
            return "FARTHEST_FIRST"
        raise InvalidExpectedMinutes(
            "예상 주차시간은 60, 120, 180, 240분 중 하나여야 합니다.",
        )

