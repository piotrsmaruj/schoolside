"""Single-request process protocol. Its pipes contain private data; never log them."""

import asyncio
import base64
import json
import logging
import re
import sys
from dataclasses import asdict
from typing import Any

import aiohttp
from librus_synergia import Librus
from librus_synergia.client import LibrusSessionData
from librus_synergia.exceptions import LibrusError
from librus_synergia.models import AttachmentFileData

from librus_probe.gateway import translate_error
from librus_probe.models import Credentials, ProbeError

from .snapshot import collect_snapshot, message_item

MAX_REQUEST_BYTES = 256 * 1024
MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024
VALID_OPERATIONS = {"sync", "message", "attachment", "homework_attachment"}


def read_request() -> dict[str, Any]:
    raw = sys.stdin.buffer.read(MAX_REQUEST_BYTES + 1)
    try:
        request: Any = json.loads(raw)
    except (ValueError, UnicodeError) as error:
        raise ProbeError("invalid_input") from error
    if len(raw) > MAX_REQUEST_BYTES or not isinstance(request, dict):
        raise ProbeError("invalid_input")
    if request.get("operation") not in VALID_OPERATIONS:
        raise ProbeError("invalid_input")
    if not isinstance(request.get("login"), str) or not isinstance(request.get("password"), str):
        raise ProbeError("invalid_input")
    return request


def identifier(request: dict[str, Any], key: str) -> str:
    value = request.get(key)
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9:_-]{1,128}", value):
        raise ProbeError("invalid_input")
    return value


def session_data(request: dict[str, Any]) -> LibrusSessionData | None:
    raw = request.get("session")
    if raw is None:
        return None
    if not isinstance(raw, dict) or not isinstance(raw.get("cookies"), list):
        raise ProbeError("invalid_input")
    try:
        return LibrusSessionData(cookies=raw["cookies"], logged_in_at=float(raw["logged_in_at"]))
    except (KeyError, TypeError, ValueError) as error:
        raise ProbeError("invalid_input") from error


async def perform(librus: Librus, request: dict[str, Any]) -> dict[str, Any]:
    operation = request["operation"]
    if operation == "sync":
        return {"snapshot": asdict(await collect_snapshot(librus))}
    if operation == "message":
        message = await librus.message(identifier(request, "message_id"))
        if message is None:
            raise ProbeError("invalid_response")
        return {"message": asdict(message_item(message))}
    attachment: AttachmentFileData | None
    if operation == "homework_attachment":
        attachment = await librus.download_homework_attachment(identifier(request, "attachment_id"))
    else:
        attachment = await librus.download_attachment(
            identifier(request, "attachment_id"), identifier(request, "message_id")
        )
    if attachment is None:
        raise ProbeError("access_denied")
    if len(attachment.content) > MAX_ATTACHMENT_BYTES:
        return {"ok": False, "error_code": "attachment_too_large"}
    return {
        "attachment": {
            "name": attachment.filename,
            "data": base64.b64encode(attachment.content).decode("ascii"),
        }
    }


async def execute(request: dict[str, Any]) -> dict[str, Any]:
    credentials = Credentials(request["login"], request["password"])
    async with asyncio.timeout(180):
        async with Librus(
            credentials.login,
            credentials.password,
            session_data=session_data(request),
            request_timeout=aiohttp.ClientTimeout(total=20),
            max_concurrent_requests=3,
            cache_reference_data=True,
        ) as librus:
            result = await perform(librus, request)
            return {"ok": True, **result, "session": asdict(librus.session_data)}


def main() -> int:
    logging.disable(logging.CRITICAL)
    try:
        response = asyncio.run(execute(read_request()))
    except LibrusError as error:
        response = {"ok": False, "error_code": translate_error(error).code}
    except ProbeError as error:
        response = {"ok": False, "error_code": error.code}
    except TimeoutError:
        response = {"ok": False, "error_code": "timed_out"}
    except Exception:
        response = {"ok": False, "error_code": "internal_error"}
    print(json.dumps(response, ensure_ascii=False, allow_nan=False))
    return 0 if response.get("ok") else 1
