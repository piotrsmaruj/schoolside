"""Librus transport adapter; deliberately uses reads that do not mark messages read."""

from collections.abc import Awaitable, Callable
from datetime import datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

import aiohttp
from librus_synergia.client import LibrusApiClient
from librus_synergia.exceptions import (
    LibrusAccountActionRequiredError,
    LibrusCaptchaRequiredError,
    LibrusConnectionError,
    LibrusError,
    LibrusInvalidCredentialsError,
    LibrusServerMaintenanceError,
    LibrusSessionExpiredError,
    LibrusUnexpectedResponseError,
)

from .models import Credentials, Module, ProbeError

PAYLOAD_KEYS = {
    Module.GRADES: "Grades",
    Module.MESSAGES: "data",
    Module.AGENDA: "HomeWorks",
    Module.ATTENDANCE: "Attendances",
    Module.ANNOUNCEMENTS: "SchoolNotices",
    Module.HOMEWORK: "HomeWorkAssignments",
}
COOKIE_MISSING_MESSAGE = "Login appeared to finish but no oauth_token session cookie was set."


def validate_identity(payload: object) -> None:
    if not isinstance(payload, dict) or not isinstance(payload.get("Me"), dict):
        raise ProbeError("invalid_response", diagnostic_code="identity.missing")
    for key, fields in (("Account", ("Id", "UserId")), ("User", ("Id", "FirstName", "LastName"))):
        identity = payload["Me"].get(key)
        if isinstance(identity, dict) and any(
            isinstance(identity.get(field), (str, int))
            and not isinstance(identity.get(field), bool)
            and bool(identity.get(field))
            for field in fields
        ):
            return
    raise ProbeError("invalid_response", diagnostic_code="identity.missing")


def count_records(module: Module, payload: object) -> int:
    """Validate response envelopes before reporting any successful empty result."""
    if not isinstance(payload, dict):
        raise ProbeError("invalid_response")
    if module == Module.TIMETABLE:
        return count_lessons(payload)
    items = payload.get(PAYLOAD_KEYS[module])
    if not isinstance(items, list) or any(not isinstance(item, dict) for item in items):
        raise ProbeError("invalid_response")
    return len(items)


def count_lessons(payload: dict[str, Any]) -> int:
    timetable = payload.get("Timetable")
    if not isinstance(timetable, dict):
        raise ProbeError("invalid_response")
    count = 0
    for day, slots in timetable.items():
        try:
            datetime.fromisoformat(day)
        except (TypeError, ValueError) as error:
            raise ProbeError("invalid_response") from error
        if not isinstance(slots, list):
            raise ProbeError("invalid_response")
        for slot in slots:
            if not isinstance(slot, list) or any(not isinstance(item, dict) for item in slot):
                raise ProbeError("invalid_response")
            count += len(slot)
    return count


def translate_error(error: LibrusError) -> ProbeError:
    """Discard upstream messages, which can contain account data or tokens."""
    if isinstance(error, LibrusCaptchaRequiredError):
        return ProbeError("captcha_required")
    if isinstance(error, LibrusInvalidCredentialsError):
        return ProbeError("auth_failed")
    if isinstance(error, LibrusAccountActionRequiredError):
        return ProbeError("account_action_required")
    if isinstance(error, LibrusServerMaintenanceError):
        return ProbeError("maintenance")
    if isinstance(error, LibrusConnectionError):
        return ProbeError("rate_limited" if error.status_code == 429 else "connection_error")
    if isinstance(error, LibrusSessionExpiredError):
        return ProbeError("access_denied" if error.status_code == 403 else "session_expired")
    if isinstance(error, LibrusUnexpectedResponseError) and error.status_code in (401, 403, 404):
        return ProbeError("access_denied")
    if isinstance(error, LibrusUnexpectedResponseError):
        known_messages = {
            "Login step 1 (portalRodzina) returned no redirect Location.": "login.redirect_missing",
            "Login response wasn't JSON:": "login.response_not_json",
            "OAuth redirect chain exceeded the hop limit.": "login.redirect_limit",
            COOKIE_MISSING_MESSAGE: "login.cookie_missing",
        }
        for prefix, diagnostic in known_messages.items():
            if str(error).startswith(prefix):
                return ProbeError("invalid_response", diagnostic_code=diagnostic)
    return ProbeError("invalid_response")


async def safe_call(operation: Callable[[], Awaitable[dict[str, Any]]]) -> dict[str, Any]:
    try:
        return await operation()
    except LibrusError as error:
        raise translate_error(error) from error


class LibrusGateway:
    def __init__(self, request_timeout: float, message_limit: int) -> None:
        self._timeout = aiohttp.ClientTimeout(total=request_timeout)
        self._message_limit = message_limit
        self._session: aiohttp.ClientSession | None = None
        self._client: LibrusApiClient | None = None

    @property
    def client(self) -> LibrusApiClient:
        if self._client is None:
            raise ProbeError("internal_error")
        return self._client

    async def close(self) -> None:
        if self._session is not None:
            await self._session.close()

    async def login(self, credentials: Credentials) -> None:
        self._session = aiohttp.ClientSession(cookie_jar=aiohttp.CookieJar())
        self._client = LibrusApiClient(
            self._session, credentials.login, request_timeout=self._timeout
        )
        try:
            await self.client.async_login(credentials.password)
        except LibrusError as error:
            raise translate_error(error) from error
        validate_identity(await safe_call(self.client.async_get_me))

    async def count(self, module: Module) -> int:
        if module == Module.MESSAGES:
            return await self._message_count()
        if module == Module.TIMETABLE:
            today = datetime.now(ZoneInfo("Europe/Warsaw")).date()
            monday = today - timedelta(days=today.weekday())
            payload = await safe_call(lambda: self.client.async_get_timetable(monday))
        else:
            operations = {
                Module.GRADES: self.client.async_get_grades,
                Module.AGENDA: self.client.async_get_homeworks,
                Module.ATTENDANCE: self.client.async_get_attendances,
                Module.ANNOUNCEMENTS: self.client.async_get_school_notices,
                Module.HOMEWORK: self.client.async_get_homework_assignments,
            }
            payload = await safe_call(operations[module])
        return count_records(module, payload)

    async def _message_count(self) -> int:
        try:
            if not await self.client.async_bootstrap_messages():
                raise ProbeError("access_denied")
        except LibrusError as error:
            raise translate_error(error) from error
        payload = await safe_call(lambda: self.client.async_get_messages(limit=self._message_limit))
        return count_records(Module.MESSAGES, payload)

    async def reuse_session(self) -> None:
        saved = self.client.export_session()
        async with aiohttp.ClientSession(cookie_jar=aiohttp.CookieJar()) as session:
            resumed = LibrusApiClient(session, self.client.username, request_timeout=self._timeout)
            resumed.import_session(saved)
            validate_identity(await safe_call(resumed.async_get_me))
            if resumed.login_count != 0:
                raise ProbeError("internal_error")
