import asyncio
import threading
import unittest

from app.adapters.occupancy import (
    DEFAULT_MEGA_BAUDRATE,
    DEFAULT_MEGA_DEVICE,
    MegaBitmaskParser,
    MegaFrameError,
    MegaFrameParser,
    OccupancyState,
    SerialOccupancyAdapter,
)
from app.adapters.robot import (
    DEFAULT_ROBOT_BAUDRATE,
    DEFAULT_ROBOT_DEVICE,
    PATH_COMMANDS,
    SerialRobotAdapter,
    SimulatorRobotAdapter,
    TransportRobotAdapter,
    UnoCommandError,
    UnoProtocolError,
    UnoStatus,
    UnoStatusCodec,
    UnoStoppedError,
    UnsupportedRobotOperationError,
)
from app.adapters.serial_transport import (
    SerialLineTransport,
    SerialReadTimeout,
    SerialTransportError,
)


class FakeRobotTransport:
    def __init__(self, statuses: list[str]) -> None:
        self.statuses = iter(statuses)
        self.commands: list[str] = []

    async def write_command(self, command: str) -> None:
        self.commands.append(command)

    async def read_status(self) -> str:
        return next(self.statuses)


class FakeSerialPort:
    def __init__(self, lines: list[bytes] | None = None) -> None:
        self.lines = iter(lines or [])
        self.writes: list[bytes] = []
        self.flush_count = 0
        self.close_count = 0
        self.cancel_count = 0
        self.is_open = True

    def readline(self) -> bytes:
        return next(self.lines, b"")

    def write(self, data: bytes) -> int:
        self.writes.append(data)
        return len(data)

    def flush(self) -> None:
        self.flush_count += 1

    def cancel_read(self) -> None:
        self.cancel_count += 1

    def close(self) -> None:
        self.close_count += 1
        self.is_open = False


class FailingReadSerialPort(FakeSerialPort):
    def readline(self) -> bytes:
        raise OSError("USB disconnected")


class BlockingSerialPort(FakeSerialPort):
    def __init__(self) -> None:
        super().__init__()
        self.read_started = threading.Event()
        self.read_released = threading.Event()

    def readline(self) -> bytes:
        self.read_started.set()
        self.read_released.wait(timeout=2)
        return b""

    def cancel_read(self) -> None:
        super().cancel_read()
        self.read_released.set()


class MegaFrameParserTest(unittest.TestCase):
    def test_parses_all_six_slots_in_any_order(self) -> None:
        parsed = MegaFrameParser.parse(
            "6:OCCUPIED,1:EMPTY,3:EMPTY,2:OCCUPIED,5:EMPTY,4:EMPTY\r\n",
        )
        self.assertEqual(parsed["1"], OccupancyState.EMPTY)
        self.assertEqual(parsed["6"], OccupancyState.OCCUPIED)

    def test_rejects_missing_duplicate_and_invalid_states(self) -> None:
        invalid_frames = (
            "1:EMPTY,2:EMPTY,3:EMPTY,4:EMPTY,5:EMPTY",
            "1:EMPTY,1:EMPTY,2:EMPTY,3:EMPTY,4:EMPTY,5:EMPTY",
            "1:EMPTY,2:EMPTY,3:EMPTY,4:EMPTY,5:EMPTY,6:FULL",
            "1: EMPTY,2:EMPTY,3:EMPTY,4:EMPTY,5:EMPTY,6:EMPTY",
        )
        for frame in invalid_frames:
            with self.subTest(frame=frame), self.assertRaises(MegaFrameError):
                MegaFrameParser.parse(frame)

    def test_real_mega_decimal_bitmask_uses_bit_zero_for_slot_one(self) -> None:
        parsed = MegaBitmaskParser.parse(b"33\r\n")
        self.assertEqual(
            parsed,
            {
                "1": OccupancyState.OCCUPIED,
                "2": OccupancyState.EMPTY,
                "3": OccupancyState.EMPTY,
                "4": OccupancyState.EMPTY,
                "5": OccupancyState.EMPTY,
                "6": OccupancyState.OCCUPIED,
            },
        )
        self.assertEqual(
            MegaFrameParser.parse("0\n"),
            {str(slot): OccupancyState.EMPTY for slot in range(1, 7)},
        )
        self.assertEqual(
            MegaBitmaskParser.parse("63"),
            {str(slot): OccupancyState.OCCUPIED for slot in range(1, 7)},
        )

    def test_real_mega_bitmask_rejects_non_decimal_and_out_of_range(self) -> None:
        for frame in ("", "-1", "+1", "64", "0x01", " 1", b"\xff\n"):
            with self.subTest(frame=frame), self.assertRaises(MegaFrameError):
                MegaBitmaskParser.parse(frame)


class UnoAdapterTest(unittest.IsolatedAsyncioTestCase):
    def test_path_commands_match_hardware_contract(self) -> None:
        self.assertEqual(
            PATH_COMMANDS,
            {
                "1": "LCPSBWB",
                "2": "LWPSBCB",
                "3": "LLCPSBWB",
                "4": "LLWPSBCB",
                "5": "LLLCPSBWB",
                "6": "LLLWPSBCB",
            },
        )

    def test_codec_accepts_only_documented_statuses(self) -> None:
        for status in UnoStatus:
            self.assertIs(UnoStatusCodec.decode(f"{status.value}\r\n"), status)
            self.assertEqual(UnoStatusCodec.encode(status), status.value)
        with self.assertRaises(UnoProtocolError):
            UnoStatusCodec.decode("COMPLETE")

    def test_codec_maps_actual_snap_code_robot_frames(self) -> None:
        expected = {
            "COMMANDS:L,W,C,P,S,B,H": UnoStatus.READY,
            "ROUTE_ACCEPTED:8": UnoStatus.TRACING,
            "ACTION_START:L:FORWARD_TO_MARKER": UnoStatus.TRACING,
            "ACTION_DONE:C": UnoStatus.TRACING,
            "ACTION_START:P:PARK_FORWARD": UnoStatus.APPROACHING,
            "P_OBJECT_DETECTED:STOP_2_SECONDS": UnoStatus.APPROACHING,
            "ACTION_START:S:GRIPPER": UnoStatus.GRIPPING,
            "ACTION_START:B:REVERSE_TO_MARKER": UnoStatus.REVERSING,
            "B_MODE:AFTER_S_REVERSE_TO_MARKER": UnoStatus.REVERSING,
            "ACTION_START:H:H_REVERSE": UnoStatus.REVERSING,
            "H_MODE:REVERSE_FOR_12_SECONDS": UnoStatus.REVERSING,
            "STATUS:IDLE": UnoStatus.READY,
            "STATUS:RUNNING,INDEX=1/8,COMMAND=P": UnoStatus.APPROACHING,
            "PONG": UnoStatus.READY,
            "ROUTE_DONE": UnoStatus.DONE,
        }
        for frame, status in expected.items():
            with self.subTest(frame=frame):
                self.assertIs(UnoStatusCodec.decode(f"{frame}\r\n"), status)

    def test_codec_treats_err_and_stopped_as_failures_not_completion(self) -> None:
        with self.assertRaisesRegex(UnoCommandError, "BUSY"):
            UnoStatusCodec.decode("ERR:BUSY\r\n")
        with self.assertRaises(UnoStoppedError):
            UnoStatusCodec.decode("STOPPED\r\n")

    async def test_transport_adapter_writes_path_and_stops_at_done(self) -> None:
        transport = FakeRobotTransport(["READY", "TRACING", "DONE"])
        adapter = TransportRobotAdapter(transport)
        statuses = [status async for status in adapter.execute_path("5")]
        self.assertEqual(transport.commands, ["LLLCPSBWB"])
        self.assertEqual(statuses, [UnoStatus.READY, UnoStatus.TRACING, UnoStatus.DONE])

    async def test_simulator_uses_same_six_path_contract(self) -> None:
        adapter = SimulatorRobotAdapter(0)
        for slot_id, command in PATH_COMMANDS.items():
            statuses = [status async for status in adapter.execute_path(slot_id)]
            self.assertEqual(statuses[-1], UnoStatus.DONE)
            self.assertEqual(adapter.commands[-1], command)

    async def test_simulator_supports_parking_and_retrieval(self) -> None:
        adapter = SimulatorRobotAdapter(0)
        self.assertTrue(adapter.supports_operation("PARKING"))
        self.assertTrue(adapter.supports_operation("retrieval"))
        self.assertFalse(adapter.supports_operation("DELIVERY"))
        statuses = [
            status
            async for status in adapter.execute_path("1", operation="RETRIEVAL")
        ]
        self.assertIs(statuses[-1], UnoStatus.DONE)

    async def test_serial_robot_writes_newline_and_rejects_retrieval(self) -> None:
        command = PATH_COMMANDS["1"]
        frames = [f"ROUTE_ACCEPTED:{len(command)}\r\n".encode()]
        expected_statuses = [UnoStatus.TRACING]
        for action in command:
            frames.extend(
                [
                    f"ACTION_START:{action}:TEST\r\n".encode(),
                    f"ACTION_DONE:{action}\r\n".encode(),
                ],
            )
            expected_statuses.append(UnoStatusCodec.action_statuses[action])
        frames.append(b"ROUTE_DONE\r\n")
        expected_statuses.append(UnoStatus.DONE)
        port = FakeSerialPort(
            frames,
        )
        adapter = SerialRobotAdapter(serial_port=port)
        statuses = [status async for status in adapter.execute_path("1")]
        self.assertEqual(port.writes, [b"LCPSBWB\n"])
        self.assertEqual(port.flush_count, 1)
        self.assertEqual(statuses, expected_statuses)
        self.assertEqual(adapter.device, DEFAULT_ROBOT_DEVICE)
        self.assertEqual(adapter.baudrate, DEFAULT_ROBOT_BAUDRATE)
        self.assertTrue(adapter.is_open)

        with self.assertRaises(UnsupportedRobotOperationError):
            _ = [
                status
                async for status in adapter.execute_path(
                    "1",
                    operation="RETRIEVAL",
                )
            ]
        self.assertEqual(port.writes, [b"LCPSBWB\n"])
        await adapter.close()
        self.assertFalse(adapter.is_open)

    async def test_serial_robot_probe_ignores_boot_frames_until_pong(self) -> None:
        port = FakeSerialPort(
            [
                b"READY\r\n",
                b"COMMANDS:L,W,C,P,S,B,H\r\n",
                b"PONG\r\n",
                b"STATUS:IDLE\r\n",
            ],
        )
        adapter = SerialRobotAdapter(serial_port=port)

        await adapter.probe()

        self.assertEqual(port.writes, [b"PING\n", b"STATUS\n"])
        await adapter.close()

    async def test_serial_robot_probe_rejects_an_already_running_route(self) -> None:
        port = FakeSerialPort(
            [b"PONG\r\n", b"STATUS:RUNNING,INDEX=1/7,COMMAND=L\r\n"],
        )
        adapter = SerialRobotAdapter(serial_port=port)

        with self.assertRaisesRegex(UnoProtocolError, "already running"):
            await adapter.probe()

        self.assertEqual(port.writes, [b"PING\n", b"STATUS\n"])
        await adapter.close()

    async def test_serial_robot_rejects_stale_or_incomplete_completion(self) -> None:
        invalid_sequences = (
            [b"ROUTE_DONE\r\n"],
            [b"ROUTE_ACCEPTED:6\r\n"],
            [b"ROUTE_ACCEPTED:7\r\n", b"ROUTE_DONE\r\n"],
        )
        for frames in invalid_sequences:
            with self.subTest(frames=frames):
                port = FakeSerialPort(frames)
                adapter = SerialRobotAdapter(serial_port=port)
                with self.assertRaises(UnoProtocolError):
                    _ = [status async for status in adapter.execute_path("1")]
                self.assertEqual(port.writes, [b"LCPSBWB\n", b"STOP\n"])
                await adapter.close()

    async def test_serial_robot_sends_stop_after_protocol_failure(self) -> None:
        port = FakeSerialPort([b"ERR:BUSY\r\n"])
        adapter = SerialRobotAdapter(serial_port=port)

        with self.assertRaises(UnoCommandError):
            _ = [status async for status in adapter.execute_path("1")]

        self.assertEqual(port.writes, [b"LCPSBWB\n", b"STOP\n"])
        await adapter.close()


class SerialTransportTest(unittest.IsolatedAsyncioTestCase):
    async def test_mega_transport_defaults_and_timeout_are_observable(self) -> None:
        port = FakeSerialPort([b"33\n"])
        adapter = SerialOccupancyAdapter(serial_port=port)
        occupancy = await adapter.read_occupancy()
        self.assertIs(occupancy["1"], OccupancyState.OCCUPIED)
        self.assertIs(occupancy["6"], OccupancyState.OCCUPIED)
        self.assertEqual(adapter.device, DEFAULT_MEGA_DEVICE)
        self.assertEqual(adapter.baudrate, DEFAULT_MEGA_BAUDRATE)

        with self.assertRaises(SerialReadTimeout):
            await adapter.read_occupancy()
        await adapter.close()
        self.assertEqual(port.close_count, 1)

    async def test_serial_error_drops_handle_and_next_read_reopens(self) -> None:
        first = FailingReadSerialPort()
        second = FakeSerialPort([b"1\n"])
        ports = iter([first, second])
        options: list[dict[str, object]] = []

        def factory(**kwargs: object) -> FakeSerialPort:
            options.append(kwargs)
            return next(ports)

        transport = SerialLineTransport(
            device="/dev/test-mega",
            baudrate=115200,
            read_timeout_seconds=0.25,
            serial_factory=factory,
        )
        with self.assertRaisesRegex(SerialTransportError, "USB disconnected"):
            await transport.read_line()
        self.assertFalse(transport.is_open)
        self.assertEqual(await transport.read_line(), b"1\n")
        self.assertTrue(transport.is_open)
        self.assertEqual(len(options), 2)
        self.assertEqual(options[0]["port"], "/dev/test-mega")
        self.assertEqual(options[0]["timeout"], 0.25)
        await transport.close()

    async def test_cancelled_read_requests_driver_cancellation(self) -> None:
        port = BlockingSerialPort()
        transport = SerialLineTransport(
            device="/dev/test-robot",
            baudrate=9600,
            read_timeout_seconds=30,
            serial_port=port,
        )
        task = asyncio.create_task(transport.read_line())
        started = await asyncio.to_thread(port.read_started.wait, 1)
        self.assertTrue(started)
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.assertEqual(port.cancel_count, 1)
        await transport.close()


if __name__ == "__main__":
    unittest.main()
