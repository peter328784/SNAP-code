from __future__ import annotations

import asyncio
import os
from contextlib import asynccontextmanager
from typing import Literal

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, Field, model_validator

from .controller import (
    ControllerError,
    InvalidParkingDuration,
    JobNotFound,
    ParkingController,
    VehicleNotFound,
)
from .runtime import GatewayRuntime


class ParkingRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    customerId: str | None = Field(default=None, min_length=1, max_length=64)
    vehicleId: str | None = Field(default=None, min_length=1, max_length=32)
    vehicleNumber: str | None = Field(default=None, min_length=1, max_length=32)
    expectedMinutes: Literal[60, 120, 180, 240] = 120

    @model_validator(mode="before")
    @classmethod
    def ignore_legacy_preference(cls, value: object) -> object:
        if isinstance(value, dict) and "preference" in value:
            without_preference = dict(value)
            without_preference.pop("preference")
            return without_preference
        return value

    @model_validator(mode="after")
    def exactly_one_vehicle_identifier(self) -> ParkingRequest:
        if (self.vehicleId is None) == (self.vehicleNumber is None):
            raise ValueError("vehicleId와 vehicleNumber 중 하나만 보내 주세요.")
        return self


class RetrievalRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    customerId: str | None = Field(default=None, min_length=1, max_length=64)
    vehicleId: str | None = Field(default=None, min_length=1, max_length=32)
    vehicleNumber: str | None = Field(default=None, min_length=1, max_length=32)

    @model_validator(mode="after")
    def exactly_one_vehicle_identifier(self) -> RetrievalRequest:
        if (self.vehicleId is None) == (self.vehicleNumber is None):
            raise ValueError("vehicleId와 vehicleNumber 중 하나만 보내 주세요.")
        return self


class VehicleRegistrationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    vehicleNumber: str = Field(min_length=1, max_length=32)


gateway_runtime = GatewayRuntime.from_environment()
controller: ParkingController = gateway_runtime.controller


@asynccontextmanager
async def lifespan(_: FastAPI):
    await gateway_runtime.start()
    try:
        yield
    finally:
        await gateway_runtime.close()


app = FastAPI(title="S.N.A.P Pi Gateway", version="0.3.0", lifespan=lifespan)

default_allowed_origins = "http://localhost:3101,http://127.0.0.1:3101"
allowed_origins = [
    origin.strip()
    for origin in os.getenv("SNAP_CORS_ORIGINS", default_allowed_origins).split(",")
    if origin.strip()
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type", "Accept"],
)


def api_error(error: ControllerError) -> HTTPException:
    if isinstance(error, (VehicleNotFound, JobNotFound)):
        status = 404
    elif isinstance(error, InvalidParkingDuration):
        status = 422
    else:
        status = 409
    return HTTPException(status_code=status, detail=str(error))


@app.get("/health")
async def health() -> dict[str, object]:
    return gateway_runtime.health()


@app.get("/v1/customers/{customer_id}/vehicles")
async def customer_vehicles(customer_id: str) -> dict[str, object]:
    try:
        return controller.list_vehicles(customer_id)
    except ControllerError as error:
        raise api_error(error) from error


@app.post("/v1/customers/{customer_id}/vehicles", status_code=201)
async def register_customer_vehicle(
    customer_id: str,
    body: VehicleRegistrationRequest,
) -> dict[str, object]:
    try:
        return {"vehicle": controller.register_vehicle(customer_id, body.vehicleNumber)}
    except ControllerError as error:
        raise api_error(error) from error


@app.get("/v1/parking-lots/{lot_id}/snapshot")
async def parking_snapshot(lot_id: str) -> dict[str, object]:
    if lot_id != "demo-01":
        raise HTTPException(status_code=404, detail="해당 주차장을 찾을 수 없습니다.")
    return controller.snapshot()


@app.post("/v1/parking-requests")
async def create_parking_request(body: ParkingRequest) -> dict[str, object]:
    try:
        return await controller.request_parking(
            vehicle_id=body.vehicleId,
            vehicle_number=body.vehicleNumber,
            customer_id=body.customerId,
            expected_minutes=body.expectedMinutes,
        )
    except ControllerError as error:
        raise api_error(error) from error


@app.post("/v1/parking-requests/{request_id}/confirm")
async def confirm_parking_request(request_id: str) -> dict[str, object]:
    try:
        return await controller.confirm_parking(request_id)
    except ControllerError as error:
        raise api_error(error) from error


@app.get("/v1/jobs/{job_id}")
async def get_job(job_id: str) -> dict[str, object]:
    try:
        return controller.get_job(job_id)
    except ControllerError as error:
        raise api_error(error) from error


@app.post("/v1/retrieval-requests")
async def create_retrieval_request(body: RetrievalRequest) -> dict[str, object]:
    try:
        return await controller.request_retrieval(
            vehicle_id=body.vehicleId,
            vehicle_number=body.vehicleNumber,
            customer_id=body.customerId,
        )
    except ControllerError as error:
        raise api_error(error) from error


@app.websocket("/v1/events")
async def events(websocket: WebSocket) -> None:
    headers = getattr(websocket, "headers", {})
    origin = headers.get("origin") if hasattr(headers, "get") else None
    if origin and "*" not in allowed_origins and origin not in allowed_origins:
        await websocket.close(code=1008)
        return

    await websocket.accept()
    queue = controller.subscribe()
    disconnect_task: asyncio.Task[None] | None = None
    event_task: asyncio.Task[dict[str, object]] | None = None
    try:
        await websocket.send_json({
            "type": "SNAPSHOT",
            "message": "Pi 이벤트 채널이 연결됐습니다.",
            "snapshot": controller.snapshot(),
        })

        async def wait_for_disconnect() -> None:
            while True:
                message = await websocket.receive()
                if message["type"] == "websocket.disconnect":
                    return

        disconnect_task = asyncio.create_task(wait_for_disconnect())
        while True:
            event_task = asyncio.create_task(queue.get())
            done, _ = await asyncio.wait(
                {disconnect_task, event_task},
                return_when=asyncio.FIRST_COMPLETED,
            )
            if disconnect_task in done:
                disconnect_task.result()
                break

            await websocket.send_json(event_task.result())
            event_task = None
    except WebSocketDisconnect:
        pass
    finally:
        tasks = [
            task
            for task in (disconnect_task, event_task)
            if task is not None
        ]
        for task in tasks:
            if not task.done():
                task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        controller.unsubscribe(queue)
