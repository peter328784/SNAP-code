import asyncio
import unittest

from app.adapters.occupancy import MegaFrameError, OccupancyState
from app.adapters.robot import SimulatorRobotAdapter, UnoStatus
from app.controller import (
    ParkingController,
    RobotInterlockActive,
    UnsupportedRobotOperation,
)
from app.runtime import GatewayRuntime, GatewaySettings


class FakeOccupancyAdapter:
    def __init__(self) -> None:
        self.device = "/dev/test-mega"
        self.baudrate = 115200
        self.is_open = False
        self.frames: asyncio.Queue[dict[str, OccupancyState]] = asyncio.Queue()

    async def open(self) -> None:
        self.is_open = True

    async def read_occupancy(self) -> dict[str, OccupancyState]:
        return await self.frames.get()

    async def close(self) -> None:
        self.is_open = False


class FakeParkingOnlyRobotAdapter:
    def __init__(self) -> None:
        self.device = "/dev/test-robot"
        self.baudrate = 9600
        self.is_open = False
        self.commands: list[str] = []

    def supports_operation(self, operation: object) -> bool:
        value = getattr(operation, "value", operation)
        return isinstance(value, str) and value.upper() == "PARKING"

    async def open(self) -> None:
        self.is_open = True

    async def probe(self) -> None:
        return None

    async def execute_path(self, slot_id: str, operation: object = "PARKING"):
        self.commands.append(slot_id)
        for status in (
            UnoStatus.READY,
            UnoStatus.TRACING,
            UnoStatus.APPROACHING,
            UnoStatus.GRIPPING,
            UnoStatus.REVERSING,
            UnoStatus.DONE,
        ):
            yield status

    async def close(self) -> None:
        self.is_open = False


class FailingParkingRobotAdapter(FakeParkingOnlyRobotAdapter):
    async def execute_path(self, slot_id: str, operation: object = "PARKING"):
        del slot_id, operation
        if False:
            yield UnoStatus.READY
        raise RuntimeError("robot link lost")


class GatewaySettingsTest(unittest.TestCase):
    def test_simulator_is_the_safe_default(self) -> None:
        settings = GatewaySettings.from_environment({})
        runtime = GatewayRuntime.from_settings(settings)

        self.assertEqual(settings.hardware_mode, "simulator")
        self.assertIsInstance(runtime.robot_adapter, SimulatorRobotAdapter)
        self.assertEqual(
            runtime.health(),
            {"status": "ok", "mode": "pi-simulator-multi-vehicle"},
        )
        self.assertTrue(
            all(
                slot["state"] == "AVAILABLE"
                for slot in runtime.controller.snapshot()["slots"]
            ),
        )

    def test_serial_mode_starts_unknown_without_a_real_mega_frame(self) -> None:
        settings = GatewaySettings.from_environment(
            {"SNAP_HARDWARE_MODE": "serial"},
        )
        runtime = GatewayRuntime.from_settings(settings)

        self.assertTrue(
            all(slot["state"] == "UNKNOWN" for slot in runtime.controller.snapshot()["slots"]),
        )
        health = runtime.health()
        self.assertEqual(health["mode"], "pi-hardware-snap-code")
        self.assertEqual(health["status"], "degraded")
        self.assertFalse(
            health["hardware"]["mega"]["occupancyInitialized"],
        )

    def test_explicit_initial_mask_and_serial_options_are_validated(self) -> None:
        settings = GatewaySettings.from_environment(
            {
                "SNAP_HARDWARE_MODE": "serial",
                "SNAP_MEGA_PORT": "/dev/serial/by-id/mega",
                "SNAP_MEGA_BAUD": "115200",
                "SNAP_MEGA_INITIAL_MASK": "33",
                "SNAP_ROBOT_PORT": "/dev/serial/by-id/robot",
                "SNAP_ROBOT_BAUD": "9600",
            },
        )
        occupancy = settings.initial_occupancy()
        self.assertIs(occupancy["1"], OccupancyState.OCCUPIED)
        self.assertIs(occupancy["6"], OccupancyState.OCCUPIED)

        invalid_environments = (
            {"SNAP_HARDWARE_MODE": "bluetooth"},
            {
                "SNAP_HARDWARE_MODE": "serial",
                "SNAP_MEGA_PORT": "/dev/same",
                "SNAP_ROBOT_PORT": "/dev/same",
            },
            {"SNAP_MEGA_BAUD": "0"},
        )
        for environment in invalid_environments:
            with self.subTest(environment=environment), self.assertRaises(ValueError):
                GatewaySettings.from_environment(environment)
        with self.assertRaises(MegaFrameError):
            GatewaySettings.from_environment({"SNAP_MEGA_INITIAL_MASK": "64"})


class GatewayRuntimeTest(unittest.IsolatedAsyncioTestCase):
    async def test_serial_lifecycle_applies_mega_frames_and_reports_health(self) -> None:
        settings = GatewaySettings(
            hardware_mode="serial",
            mega_port="/dev/test-mega",
            robot_port="/dev/test-robot",
            serial_reconnect_delay_seconds=0.001,
        )
        occupancy_adapter = FakeOccupancyAdapter()
        robot_adapter = FakeParkingOnlyRobotAdapter()
        controller = ParkingController(
            step_delay_seconds=0,
            robot_adapter=robot_adapter,
            initial_occupancy=settings.initial_occupancy(),
        )
        runtime = GatewayRuntime(
            settings=settings,
            controller=controller,
            occupancy_adapter=occupancy_adapter,
            robot_adapter=robot_adapter,
        )
        self.addAsyncCleanup(runtime.close)

        await runtime.start()
        health = runtime.health()
        self.assertEqual(health["status"], "degraded")
        self.assertTrue(health["hardware"]["mega"]["connected"])
        self.assertTrue(health["hardware"]["robot"]["connected"])
        self.assertTrue(health["hardware"]["robot"]["ready"])
        self.assertEqual(
            health["hardware"]["robot"]["supportedOperations"],
            ["PARKING"],
        )

        await occupancy_adapter.frames.put(
            {
                "1": OccupancyState.OCCUPIED,
                "2": OccupancyState.EMPTY,
                "3": OccupancyState.EMPTY,
                "4": OccupancyState.EMPTY,
                "5": OccupancyState.EMPTY,
                "6": OccupancyState.OCCUPIED,
            },
        )
        for _ in range(100):
            if runtime.health()["hardware"]["mega"]["lastFrameAt"] is not None:
                break
            await asyncio.sleep(0.001)

        slots = controller.snapshot()["slots"]
        self.assertEqual(slots[0]["state"], "OCCUPIED")
        self.assertEqual(slots[1]["state"], "AVAILABLE")
        self.assertEqual(slots[5]["state"], "OCCUPIED")
        self.assertTrue(
            runtime.health()["hardware"]["mega"]["occupancyInitialized"],
        )
        self.assertEqual(runtime.health()["status"], "ok")

    async def test_parking_only_firmware_rejects_retrieval_without_mutation(self) -> None:
        robot_adapter = FakeParkingOnlyRobotAdapter()
        controller = ParkingController(
            step_delay_seconds=0,
            robot_adapter=robot_adapter,
        )
        self.addAsyncCleanup(controller.close)
        vehicle = controller.register_vehicle("customer-1", "12가3456")
        await controller.request_parking(
            customer_id="customer-1",
            vehicle_id=vehicle["vehicleId"],
            expected_minutes=60,
        )
        await controller.wait_until("IDLE", timeout=1)
        before = controller.list_vehicles("customer-1")

        with self.assertRaisesRegex(
            UnsupportedRobotOperation,
            "현재 로봇 펌웨어에는 출차 경로가 정의되지 않았습니다",
        ):
            await controller.request_retrieval(
                customer_id="customer-1",
                vehicle_id=vehicle["vehicleId"],
            )

        self.assertEqual(controller.list_vehicles("customer-1"), before)
        self.assertIsNone(controller.snapshot()["activeJob"])

    async def test_robot_failure_interlocks_all_followup_hardware_jobs(self) -> None:
        settings = GatewaySettings(
            hardware_mode="serial",
            mega_port="/dev/test-mega",
            mega_initial_mask=0,
            robot_port="/dev/test-robot",
        )
        occupancy_adapter = FakeOccupancyAdapter()
        robot_adapter = FailingParkingRobotAdapter()
        controller = ParkingController(
            step_delay_seconds=0,
            robot_adapter=robot_adapter,
            initial_occupancy=settings.initial_occupancy(),
        )
        runtime = GatewayRuntime(
            settings=settings,
            controller=controller,
            occupancy_adapter=occupancy_adapter,
            robot_adapter=robot_adapter,
        )
        self.addAsyncCleanup(runtime.close)
        await runtime.start()
        first = controller.register_vehicle("customer-1", "12가3456")
        second = controller.register_vehicle("customer-1", "34나5678")

        failed = await controller.request_parking(
            customer_id="customer-1",
            vehicle_id=first["vehicleId"],
            expected_minutes=60,
        )
        await controller.wait_until("IDLE", timeout=1)

        self.assertTrue(controller.robot_interlocked)
        self.assertIn("robot link lost", controller.robot_fault_message)
        self.assertEqual(controller.get_job(failed["requestId"])["state"], "FAILED")
        health = runtime.health()
        self.assertEqual(health["status"], "degraded")
        self.assertFalse(health["hardware"]["robot"]["ready"])
        self.assertTrue(health["hardware"]["robot"]["interlocked"])
        self.assertIn("robot link lost", health["hardware"]["robot"]["lastError"])
        with self.assertRaisesRegex(RobotInterlockActive, "인터록"):
            await controller.request_parking(
                customer_id="customer-1",
                vehicle_id=second["vehicleId"],
                expected_minutes=60,
            )


if __name__ == "__main__":
    unittest.main()
