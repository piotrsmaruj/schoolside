"""Private stdin/stdout JSON protocol for the native UI. No credentials in argv."""

import asyncio
import json
import logging
import math
import os
import sys
from typing import Any

from .gateway import LibrusGateway
from .models import Credentials, ProbeError, ProbeReport
from .service import run_probe

MAX_INPUT_BYTES = 64 * 1024
DEFAULT_REQUEST_TIMEOUT = 20.0
DEFAULT_OVERALL_TIMEOUT = 180.0
DEFAULT_MESSAGE_LIMIT = 5


def read_credentials() -> Credentials:
    raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
    if len(raw) > MAX_INPUT_BYTES:
        raise ProbeError("invalid_input")
    try:
        data: Any = json.loads(raw)
    except (ValueError, UnicodeError) as error:
        raise ProbeError("invalid_input") from error
    if not isinstance(data, dict) or set(data) != {"login", "password"}:
        raise ProbeError("invalid_input")
    if not isinstance(data["login"], str) or not isinstance(data["password"], str):
        raise ProbeError("invalid_input")
    return Credentials(data["login"], data["password"])


def positive_setting(name: str, default: float) -> float:
    try:
        value = float(os.environ.get(name, default))
    except ValueError as error:
        raise ProbeError("invalid_input") from error
    if not math.isfinite(value) or value <= 0:
        raise ProbeError("invalid_input")
    return value


async def execute(credentials: Credentials) -> ProbeReport:
    gateway = LibrusGateway(
        positive_setting("LIBRUS_PROBE_REQUEST_TIMEOUT", DEFAULT_REQUEST_TIMEOUT),
        DEFAULT_MESSAGE_LIMIT,
    )
    try:
        async with asyncio.timeout(
            positive_setting("LIBRUS_PROBE_OVERALL_TIMEOUT", DEFAULT_OVERALL_TIMEOUT)
        ):
            return await run_probe(gateway, credentials)
    except TimeoutError as error:
        raise ProbeError("timed_out") from error
    finally:
        await gateway.close()


def main() -> int:
    """Print only the safe report; upstream exception text never reaches either pipe."""
    logging.disable(logging.CRITICAL)
    try:
        report = asyncio.run(execute(read_credentials()))
    except ProbeError as error:
        report = ProbeReport(error_code=error.code)
    except Exception:
        # Last-resort process boundary: fail visibly, without leaking an upstream body.
        print("Connection check failed: internal_error", file=sys.stderr)
        report = ProbeReport(error_code="internal_error")
    print(json.dumps(report.to_dict(), ensure_ascii=False))
    return 0 if report.authenticated and not report.error_code else 1


if __name__ == "__main__":
    raise SystemExit(main())
