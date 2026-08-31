from __future__ import annotations

import os

import uvicorn

from .main import app


def main() -> None:
    uvicorn.run(
        app,
        host=os.getenv("SNAP_GATEWAY_HOST", "127.0.0.1"),
        port=int(os.getenv("SNAP_GATEWAY_PORT", "8101")),
    )


if __name__ == "__main__":
    main()
