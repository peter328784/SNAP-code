import unittest
from unittest.mock import patch

from fastapi import HTTPException
from pydantic import ValidationError

import app.main as main_module
from app.controller import ParkingController
from app.main import (
    ParkingRequest,
    RetrievalRequest,
    VehicleRegistrationRequest,
    create_parking_request,
    create_retrieval_request,
    customer_vehicles,
    register_customer_vehicle,
)


class ApiContractTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.controller = ParkingController(step_delay_seconds=0.001)
        self.controller_patch = patch.object(main_module, "controller", self.controller)
        self.controller_patch.start()

    async def asyncTearDown(self) -> None:
        await self.controller.close()
        self.controller_patch.stop()

    async def test_customer_can_register_and_list_multiple_vehicles(self) -> None:
        first = await register_customer_vehicle(
            "customer-1",
            VehicleRegistrationRequest(vehicleNumber="12가 3456"),
        )
        second = await register_customer_vehicle(
            "customer-1",
            VehicleRegistrationRequest(vehicleNumber="34나5678"),
        )
        self.assertNotEqual(
            first["vehicle"]["vehicleId"],
            second["vehicle"]["vehicleId"],
        )

        response = await customer_vehicles("customer-1")
        self.assertEqual(response["customerId"], "customer-1")
        self.assertEqual(len(response["vehicles"]), 2)
        self.assertEqual(response["vehicles"][0]["vehicleNumber"], "12가3456")

    def test_parking_request_rejects_invalid_duration_and_target_slot(self) -> None:
        with self.assertRaises(ValidationError):
            ParkingRequest(vehicleId="12가3456", expectedMinutes=30)
        with self.assertRaises(ValidationError):
            ParkingRequest.model_validate(
                {
                    "vehicleNumber": "12가3456",
                    "customerId": "customer-1",
                    "expectedMinutes": 60,
                    "targetSlot": "3",
                },
            )

    async def test_full_lot_returns_exact_409_message(self) -> None:
        full_controller = ParkingController(
            step_delay_seconds=0,
            initial_occupancy={slot_id: "OCCUPIED" for slot_id in ParkingController.slot_ids},
        )
        with patch.object(main_module, "controller", full_controller):
            with self.assertRaises(HTTPException) as raised:
                await create_parking_request(
                    ParkingRequest(
                        customerId="customer-1",
                        vehicleNumber="12가3456",
                        expectedMinutes=60,
                    ),
                )
        self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(raised.exception.detail, "현재 주차장이 만차입니다.")

    async def test_legacy_preference_is_accepted_but_ignored(self) -> None:
        response = await create_parking_request(
            ParkingRequest(
                vehicleId="LEGACY-12",
                expectedMinutes=60,
                preference="NEAR_EXIT",
            ),
        )
        self.assertEqual(response["snapshot"]["activeJob"]["targetSlot"], "1")

    async def test_hardware_firmware_without_retrieval_route_returns_409(self) -> None:
        class ParkingOnlyAdapter:
            def supports_operation(self, operation: object) -> bool:
                return operation == "PARKING"

            async def execute_path(self, slot_id: str, operation: object = "PARKING"):
                del slot_id, operation
                yield

            async def close(self) -> None:
                return None

        hardware_controller = ParkingController(robot_adapter=ParkingOnlyAdapter())
        self.addAsyncCleanup(hardware_controller.close)
        with patch.object(main_module, "controller", hardware_controller):
            with self.assertRaises(HTTPException) as raised:
                await create_retrieval_request(
                    RetrievalRequest(
                        customerId="customer-1",
                        vehicleNumber="12가3456",
                    ),
                )

        self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(
            raised.exception.detail,
            "현재 로봇 펌웨어에는 출차 경로가 정의되지 않았습니다.",
        )


if __name__ == "__main__":
    unittest.main()
