import asyncio
import os
import unittest

try:
    import pty
except ImportError:  # pragma: no cover - Windows has no POSIX pseudo terminals.
    pty = None

from app.controller import ParkingController
from app.runtime import GatewayRuntime, GatewaySettings


def read_line(file_descriptor: int) -> bytes:
    frame = bytearray()
    while not frame.endswith(b"\n"):
        frame.extend(os.read(file_descriptor, 1))
    return bytes(frame)


@unittest.skipIf(pty is None, "POSIX pseudo terminals are required")
class SerialGatewayIntegrationTest(unittest.IsolatedAsyncioTestCase):
    async def test_real_pyserial_transports_drive_controller(self) -> None:
        mega_master, mega_slave = pty.openpty()
        robot_master, robot_slave = pty.openpty()
        self.addCleanup(os.close, mega_master)
        self.addCleanup(os.close, mega_slave)
        self.addCleanup(os.close, robot_master)
        self.addCleanup(os.close, robot_slave)

        settings = GatewaySettings(
            hardware_mode="serial",
            step_delay_seconds=0,
            mega_port=os.ttyname(mega_slave),
            mega_baud=115200,
            mega_read_timeout_seconds=0.1,
            robot_port=os.ttyname(robot_slave),
            robot_baud=9600,
            robot_read_timeout_seconds=1,
            serial_reconnect_delay_seconds=0.01,
        )
        runtime = GatewayRuntime.from_settings(settings)
        self.assertIsInstance(runtime.controller, ParkingController)
        self.addAsyncCleanup(runtime.close)

        async def emulate_probe() -> tuple[bytes, bytes]:
            ping = await asyncio.to_thread(read_line, robot_master)
            await asyncio.to_thread(os.write, robot_master, b"PONG\r\n")
            status = await asyncio.to_thread(read_line, robot_master)
            await asyncio.to_thread(os.write, robot_master, b"STATUS:IDLE\r\n")
            return ping, status

        probe_responder = asyncio.create_task(emulate_probe())
        await runtime.start()
        self.assertEqual(await probe_responder, (b"PING\n", b"STATUS\n"))

        await asyncio.to_thread(os.write, mega_master, b"0\r\n")
        for _ in range(100):
            if runtime.health()["hardware"]["mega"]["occupancyInitialized"]:
                break
            await asyncio.sleep(0.005)
        self.assertEqual(runtime.controller.snapshot()["availableCount"], 6)

        async def emulate_robot() -> bytes:
            command = await asyncio.to_thread(read_line, robot_master)
            route = command.rstrip(b"\r\n").decode("ascii")
            frames = [f"ROUTE_ACCEPTED:{len(route)}\r\n"]
            for action in route:
                frames.extend(
                    [
                        f"ACTION_START:{action}:TEST\r\n",
                        f"ACTION_DONE:{action}\r\n",
                    ],
                )
            frames.append("ROUTE_DONE\r\n")
            await asyncio.to_thread(
                os.write,
                robot_master,
                "".join(frames).encode("ascii"),
            )
            return command

        responder = asyncio.create_task(emulate_robot())
        vehicle = runtime.controller.register_vehicle("customer-1", "12가3456")
        request = await runtime.controller.request_parking(
            customer_id="customer-1",
            vehicle_id=vehicle["vehicleId"],
            expected_minutes=60,
        )
        self.assertEqual(request["snapshot"]["activeJob"]["targetSlot"], "1")
        await runtime.controller.wait_until("IDLE", timeout=2)

        self.assertEqual(await responder, b"LCPSBWB\n")
        parked = runtime.controller.list_vehicles("customer-1")["vehicles"][0]
        self.assertEqual(parked["state"], "PARKED")
        self.assertEqual(parked["slotId"], "1")
        self.assertEqual(runtime.health()["status"], "ok")


if __name__ == "__main__":
    unittest.main()
