import asyncio
import unittest
from unittest.mock import patch

from app.main import events


class FakeController:
    def __init__(self) -> None:
        self.queue: asyncio.Queue[dict[str, object]] = asyncio.Queue()
        self.unsubscribed = False

    def subscribe(self) -> asyncio.Queue[dict[str, object]]:
        return self.queue

    def unsubscribe(self, queue: asyncio.Queue[dict[str, object]]) -> None:
        self.unsubscribed = queue is self.queue

    def snapshot(self) -> dict[str, object]:
        return {"lotId": "demo-01"}


class DisconnectingWebSocket:
    def __init__(self) -> None:
        self.accepted = False
        self.sent: list[dict[str, object]] = []

    async def accept(self) -> None:
        self.accepted = True

    async def send_json(self, payload: dict[str, object]) -> None:
        self.sent.append(payload)

    async def receive(self) -> dict[str, object]:
        return {"type": "websocket.disconnect", "code": 1000}


class RejectedOriginWebSocket:
    def __init__(self) -> None:
        self.headers = {"origin": "https://untrusted.example"}
        self.closed_with: int | None = None

    async def close(self, code: int) -> None:
        self.closed_with = code


class EventsTest(unittest.IsolatedAsyncioTestCase):
    async def test_rejects_unlisted_browser_origin(self) -> None:
        websocket = RejectedOriginWebSocket()

        await events(websocket)

        self.assertEqual(websocket.closed_with, 1008)

    async def test_disconnect_unsubscribes_without_waiting_for_event(self) -> None:
        fake_controller = FakeController()
        websocket = DisconnectingWebSocket()

        with patch("app.main.controller", fake_controller):
            await asyncio.wait_for(events(websocket), timeout=0.2)

        self.assertTrue(websocket.accepted)
        self.assertEqual(websocket.sent[0]["type"], "SNAPSHOT")
        self.assertEqual(websocket.sent[0]["snapshot"], {"lotId": "demo-01"})
        self.assertTrue(fake_controller.unsubscribed)


if __name__ == "__main__":
    unittest.main()
