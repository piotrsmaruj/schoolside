"""Behavior at the service/API/process boundaries; no real school-account calls."""

import asyncio
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from librus_probe.gateway import count_records, translate_error, validate_identity
from librus_probe.models import Credentials, Module, ProbeError
from librus_probe.service import run_probe


class FakeGateway:
    def __init__(self, failures: dict[Module, str] | None = None) -> None:
        self.failures = failures or {}
        self.login_error: str | None = None
        self.session_error: str | None = None
        self.operations: list[str] = []

    async def login(self, credentials: Credentials) -> None:
        self.operations.append("login")
        if self.login_error:
            raise ProbeError(self.login_error)

    async def count(self, module: Module) -> int:
        self.operations.append(module.value)
        if module in self.failures:
            raise ProbeError(self.failures[module])
        return 0 if module == Module.AGENDA else 3

    async def reuse_session(self) -> None:
        self.operations.append("reuse_session")
        if self.session_error:
            raise ProbeError(self.session_error)


@pytest.mark.parametrize("login", ["", "   ", "123u", "a123", "１２３", "123 456"])
def test_rejects_non_parent_numeric_logins(login: str) -> None:
    with pytest.raises(ProbeError, match="invalid_input"):
        Credentials(login, "hasło")


def test_preserves_password_and_keeps_it_out_of_repr() -> None:
    credentials = Credentials(" 1234567 ", "  żółć'$`\\\n🙂  ")
    assert credentials.login == "1234567"
    assert credentials.password == "  żółć'$`\\\n🙂  "
    assert credentials.password not in repr(credentials)
    assert credentials.login not in repr(credentials)


def test_rejects_empty_password() -> None:
    with pytest.raises(ProbeError, match="invalid_input"):
        Credentials("1234567", "")


def test_partial_failure_preserves_other_modules_and_distinguishes_empty() -> None:
    gateway = FakeGateway({Module.TIMETABLE: "access_denied", Module.GRADES: "connection_error"})
    report = asyncio.run(run_probe(gateway, Credentials("1234567", "secret"))).to_dict()
    results = {item["id"]: item for item in report["modules"]}
    assert report["authenticated"] is True
    assert report["session_reused"] is True
    assert results["timetable"]["status"] == "unavailable"
    assert results["grades"]["status"] == "error"
    assert results["agenda"]["status"] == "empty"
    assert results["agenda"]["count"] == 0
    assert results["messages"]["status"] == "available"
    assert results["messages"]["count"] == 3


def test_login_failure_stops_queries_and_session_reuse() -> None:
    gateway = FakeGateway()
    gateway.login_error = "auth_failed"
    report = asyncio.run(run_probe(gateway, Credentials("1234567", "secret")))
    assert report.authenticated is False
    assert report.error_code == "auth_failed"
    assert gateway.operations == ["login"]
    assert all(item.status == "not_checked" for item in report.modules)


def test_expired_session_stops_queries_instead_of_silent_password_retry() -> None:
    gateway = FakeGateway({Module.TIMETABLE: "session_expired"})
    report = asyncio.run(run_probe(gateway, Credentials("1234567", "secret")))
    assert report.error_code == "session_expired"
    assert gateway.operations == ["login", "timetable"]
    assert report.session_reused is None


def test_session_reuse_failure_is_reported_separately() -> None:
    gateway = FakeGateway()
    gateway.session_error = "session_expired"
    report = asyncio.run(run_probe(gateway, Credentials("1234567", "secret")))
    assert report.authenticated is True
    assert report.session_reused is False
    assert report.session_error_code == "session_expired"
    assert any(item.status == "available" for item in report.modules)


@pytest.mark.parametrize("payload", [{}, {"Grades": None}, {"Grades": {}}, {"Grades": [7]}])
def test_malformed_payload_cannot_look_like_empty_data(payload: object) -> None:
    with pytest.raises(ProbeError, match="invalid_response"):
        count_records(Module.GRADES, payload)


def test_counts_grades_and_message_previews_without_interpreting_private_content() -> None:
    assert count_records(Module.GRADES, {"Grades": [{"Id": 1}, {"Id": 2}]}) == 2
    assert count_records(Module.MESSAGES, {"data": []}) == 0
    assert count_records(Module.MESSAGES, {"data": [{"id": 1, "content": "secret"}]}) == 1


def test_counts_nested_parallel_timetable_lessons() -> None:
    payload = {
        "Timetable": {
            "2026-10-26": [
                [{"Subject": {"Id": 1}}],
                [],
                [{"Subject": {"Id": 2}}, {"Subject": {"Id": 3}}],
            ]
        }
    }
    assert count_records(Module.TIMETABLE, payload) == 3


@pytest.mark.parametrize("payload", [{"Timetable": []}, {"Timetable": {"day": [None]}}])
def test_rejects_malformed_timetable(payload: object) -> None:
    with pytest.raises(ProbeError, match="invalid_response"):
        count_records(Module.TIMETABLE, payload)


def test_identity_requires_a_recognizable_profile() -> None:
    with pytest.raises(ProbeError, match="invalid_response"):
        validate_identity({"Me": {"Account": {}, "User": {}}})
    validate_identity({"Me": {"Account": {"Id": 1}, "User": {"Id": 2}}})


def test_login_error_reports_only_allowlisted_diagnostic() -> None:
    from librus_synergia.exceptions import LibrusUnexpectedResponseError

    error = translate_error(
        LibrusUnexpectedResponseError(
            "Login appeared to finish but no oauth_token session cookie was set. private secret"
        )
    )
    assert error.code == "invalid_response"
    assert error.diagnostic_code == "login.cookie_missing"
    assert "private" not in str(error)
    assert ProbeError("invalid_response", diagnostic_code="private secret").diagnostic_code is None


def test_identity_error_identifies_failed_stage_without_recording_values() -> None:
    with pytest.raises(ProbeError) as failure:
        validate_identity({"Me": {"Account": {"unknown": "PRIVATE"}}})
    assert failure.value.diagnostic_code == "identity.missing"
    assert "PRIVATE" not in str(failure.value)


@pytest.mark.parametrize(
    "payload",
    [
        {"Me": {"User": {"FirstName": "Example", "LastName": "Test"}}},
        {"Me": {"Account": {"UserId": 77}}},
        {"Me": {"Account": {"Id": 1}, "User": {"FirstName": None, "LastName": "Test"}}},
    ],
)
def test_identity_accepts_upstream_profiles_without_undocumented_required_ids(
    payload: object,
) -> None:
    validate_identity(payload)


def test_library_errors_are_classified_without_exposing_their_text() -> None:
    from librus_synergia.exceptions import (
        LibrusCaptchaRequiredError,
        LibrusConnectionError,
        LibrusSessionExpiredError,
        LibrusUnexpectedResponseError,
    )

    cases = [
        (LibrusCaptchaRequiredError("private password"), "captcha_required"),
        (LibrusConnectionError("private token", status_code=429), "rate_limited"),
        (LibrusSessionExpiredError("private", status_code=401), "session_expired"),
        (LibrusSessionExpiredError("private", status_code=403), "access_denied"),
        (LibrusUnexpectedResponseError("private", status_code=401), "access_denied"),
        (LibrusUnexpectedResponseError("private", status_code=404), "access_denied"),
    ]
    for error, expected in cases:
        translated = translate_error(error)
        assert translated.code == expected
        assert "private" not in str(translated)


@pytest.mark.parametrize(
    "raw",
    [
        b"not json",
        b"[]",
        b'{"login":123,"password":"secret"}',
        b'{"login":"123","password":""}',
        b"x" * 65537,
    ],
)
def test_process_rejects_bad_input_without_leaking_it(raw: bytes) -> None:
    environment = {**os.environ, "PYTHONPATH": str(Path(__file__).parents[1] / "src")}
    result = subprocess.run(
        [sys.executable, "-m", "librus_probe"],
        input=raw,
        capture_output=True,
        env=environment,
        timeout=5,
        check=False,
    )
    report = json.loads(result.stdout)
    assert result.returncode != 0
    assert report["error_code"] == "invalid_input"
    assert b"secret" not in result.stdout + result.stderr
    assert b"Traceback" not in result.stderr
