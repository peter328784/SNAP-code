import unittest

from app.controller import (
    ControllerBusy,
    InvalidParkingDuration,
    ParkingController,
    ParkingLotFull,
    VehicleNotFound,
)


class ParkingControllerTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.controller = ParkingController(step_delay_seconds=0.001)

    async def asyncTearDown(self) -> None:
        await self.controller.close()

    async def test_two_vehicles_remain_independent_after_robot_returns(self) -> None:
        first = self.controller.register_vehicle("customer-1", "12가3456")
        second = self.controller.register_vehicle("customer-1", "34나5678")

        first_request = await self.controller.request_parking(
            customer_id="customer-1",
            vehicle_id=first["vehicleId"],
            expected_minutes=60,
        )
        self.assertEqual(first_request["snapshot"]["activeJob"]["targetSlot"], "1")
        await self.controller.wait_until("IDLE", timeout=1)

        first_parked = self.controller.list_vehicles("customer-1")["vehicles"][0]
        self.assertEqual(first_parked["state"], "PARKED")
        self.assertEqual(first_parked["slotId"], "1")
        self.assertIsNone(self.controller.snapshot()["activeJob"])
        self.assertEqual(
            self.controller.snapshot()["robot"]["actionState"],
            "IDLE_AT_STANDBY",
        )

        second_request = await self.controller.request_parking(
            customer_id="customer-1",
            vehicle_id=second["vehicleId"],
            expected_minutes=240,
        )
        self.assertEqual(second_request["snapshot"]["activeJob"]["targetSlot"], "6")
        await self.controller.wait_until("IDLE", timeout=1)

        vehicles = self.controller.list_vehicles("customer-1")["vehicles"]
        self.assertEqual([vehicle["state"] for vehicle in vehicles], ["PARKED", "PARKED"])
        self.assertEqual([vehicle["slotId"] for vehicle in vehicles], ["1", "6"])

    async def test_retrieving_one_vehicle_does_not_change_another(self) -> None:
        first = self.controller.register_vehicle("customer-1", "12가3456")
        second = self.controller.register_vehicle("customer-1", "34나5678")
        await self.controller.request_parking(
            customer_id="customer-1",
            vehicle_id=first["vehicleId"],
            expected_minutes=60,
        )
        await self.controller.wait_until("IDLE", timeout=1)
        await self.controller.request_parking(
            customer_id="customer-1",
            vehicle_id=second["vehicleId"],
            expected_minutes=240,
        )
        await self.controller.wait_until("IDLE", timeout=1)

        await self.controller.request_retrieval(
            customer_id="customer-1",
            vehicle_id=first["vehicleId"],
        )
        await self.controller.wait_until("IDLE", timeout=1)

        vehicles = {
            vehicle["vehicleId"]: vehicle
            for vehicle in self.controller.list_vehicles("customer-1")["vehicles"]
        }
        self.assertEqual(vehicles[first["vehicleId"]]["state"], "RETRIEVED")
        self.assertNotIn("slotId", vehicles[first["vehicleId"]])
        self.assertEqual(vehicles[second["vehicleId"]]["state"], "PARKED")
        self.assertEqual(vehicles[second["vehicleId"]]["slotId"], "6")

    async def test_only_one_robot_job_can_run(self) -> None:
        first = self.controller.register_vehicle("customer-1", "12가3456")
        second = self.controller.register_vehicle("customer-2", "34나5678")
        await self.controller.request_parking(
            customer_id="customer-1",
            vehicle_id=first["vehicleId"],
            expected_minutes=60,
        )

        with self.assertRaises(ControllerBusy):
            await self.controller.request_parking(
                customer_id="customer-2",
                vehicle_id=second["vehicleId"],
                expected_minutes=120,
            )

    async def test_full_lot_uses_exact_message(self) -> None:
        controller = ParkingController(
            step_delay_seconds=0.001,
            initial_occupancy={slot_id: "OCCUPIED" for slot_id in ParkingController.slot_ids},
        )
        self.addAsyncCleanup(controller.close)
        with self.assertRaisesRegex(ParkingLotFull, "^현재 주차장이 만차입니다\\.$"):
            await controller.request_parking("12가3456", 60)

    async def test_legacy_vehicle_id_is_treated_as_vehicle_number(self) -> None:
        response = await self.controller.request_parking("snap-01", 120, "AUTO")
        internal_id = response["snapshot"]["activeJob"]["vehicleId"]
        self.assertTrue(internal_id.startswith("VEH-"))
        await self.controller.wait_until("IDLE", timeout=1)

        legacy_vehicle = self.controller.list_vehicles("legacy")["vehicles"][0]
        self.assertEqual(legacy_vehicle["vehicleNumber"], "SNAP-01")
        await self.controller.request_retrieval("snap-01")
        await self.controller.wait_until("IDLE", timeout=1)
        self.assertEqual(
            self.controller.list_vehicles("legacy")["vehicles"][0]["state"],
            "RETRIEVED",
        )

    async def test_snapshot_does_not_expose_vehicle_number(self) -> None:
        vehicle = self.controller.register_vehicle("customer-1", "12가3456")
        response = await self.controller.request_parking(
            customer_id="customer-1",
            vehicle_id=vehicle["vehicleId"],
            expected_minutes=60,
        )
        self.assertEqual(
            response["snapshot"]["job"],
            response["snapshot"]["activeJob"],
        )
        await self.controller.wait_until("IDLE", timeout=1)
        snapshot = self.controller.snapshot()
        snapshot_text = repr(snapshot)
        self.assertNotIn("12가3456", snapshot_text)
        self.assertIn(vehicle["vehicleId"], snapshot_text)
        self.assertIsNone(snapshot["activeJob"])
        self.assertEqual(snapshot["job"]["state"], "IDLE")
        self.assertEqual(
            self.controller.get_job(response["requestId"])["state"],
            "COMPLETED",
        )

    async def test_invalid_duration_is_rejected(self) -> None:
        with self.assertRaises(InvalidParkingDuration):
            await self.controller.request_parking("12가3456", 30)

    async def test_mega_occupancy_is_used_by_allocator(self) -> None:
        await self.controller.ingest_occupancy_frame(
            "1:OCCUPIED,2:EMPTY,3:EMPTY,4:EMPTY,5:EMPTY,6:EMPTY",
        )
        response = await self.controller.request_parking("12가3456", 60)
        self.assertEqual(response["snapshot"]["activeJob"]["targetSlot"], "2")

    async def test_customer_cannot_retrieve_another_customers_vehicle(self) -> None:
        vehicle = self.controller.register_vehicle("customer-1", "12가3456")
        await self.controller.request_parking(
            customer_id="customer-1",
            vehicle_id=vehicle["vehicleId"],
            expected_minutes=60,
        )
        await self.controller.wait_until("IDLE", timeout=1)
        with self.assertRaises(VehicleNotFound):
            await self.controller.request_retrieval(
                customer_id="customer-2",
                vehicle_id=vehicle["vehicleId"],
            )


if __name__ == "__main__":
    unittest.main()
