import unittest

from app.allocator import InvalidExpectedMinutes, LotFull, SlotAllocator


class SlotAllocatorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.allocator = SlotAllocator()

    @staticmethod
    def slots(*available: str) -> list[dict[str, str]]:
        return [
            {
                "id": slot_id,
                "state": "AVAILABLE" if slot_id in available else "OCCUPIED",
            }
            for slot_id in SlotAllocator.slot_ids
        ]

    def test_short_stays_choose_nearest_slot(self) -> None:
        slots = self.slots("2", "5")
        self.assertEqual(self.allocator.select(60, slots), "2")
        self.assertEqual(self.allocator.select(120, slots), "2")

    def test_three_hours_prefers_far_group(self) -> None:
        self.assertEqual(self.allocator.select(180, self.slots("2", "4", "6")), "4")
        self.assertEqual(self.allocator.select(180, self.slots("2", "6")), "6")

    def test_four_hours_chooses_farthest_slot(self) -> None:
        self.assertEqual(self.allocator.select(240, self.slots("2", "4", "6")), "6")

    def test_reserved_and_unknown_slots_are_excluded(self) -> None:
        slots = self.slots("2")
        slots[0]["state"] = "RESERVED"
        slots[5]["state"] = "UNKNOWN"
        self.assertEqual(self.allocator.select(60, slots), "2")

    def test_full_and_invalid_duration_errors(self) -> None:
        with self.assertRaisesRegex(LotFull, "^현재 주차장이 만차입니다\\.$"):
            self.allocator.select(60, self.slots())
        with self.assertRaises(InvalidExpectedMinutes):
            self.allocator.select(30, self.slots("1"))


if __name__ == "__main__":
    unittest.main()
