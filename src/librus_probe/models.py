"""Input validation and secret-free results shared by the application layers."""

from dataclasses import asdict, dataclass, field
from enum import StrEnum
from typing import Any, Literal


class Module(StrEnum):
    TIMETABLE = "timetable"
    GRADES = "grades"
    MESSAGES = "messages"
    AGENDA = "agenda"
    ATTENDANCE = "attendance"
    ANNOUNCEMENTS = "announcements"
    HOMEWORK = "homework"


ERROR_CODES = frozenset(
    {
        "invalid_input",
        "auth_failed",
        "captcha_required",
        "account_action_required",
        "session_expired",
        "connection_error",
        "rate_limited",
        "maintenance",
        "invalid_response",
        "access_denied",
        "internal_error",
        "timed_out",
    }
)

DIAGNOSTIC_CODES = frozenset(
    {
        "login.redirect_missing",
        "login.response_not_json",
        "login.redirect_limit",
        "login.cookie_missing",
        "identity.missing",
    }
)


class ProbeError(Exception):
    """A safe machine-readable code, never the upstream error body or credentials."""

    def __init__(self, code: str, *, diagnostic_code: str | None = None) -> None:
        self.code = code if code in ERROR_CODES else "internal_error"
        self.diagnostic_code = diagnostic_code if diagnostic_code in DIAGNOSTIC_CODES else None
        super().__init__(self.code)


@dataclass(frozen=True, repr=False)
class Credentials:
    login: str
    password: str

    def __post_init__(self) -> None:
        login = self.login.strip()
        if not login or not login.isascii() or not login.isdecimal() or not self.password:
            raise ProbeError("invalid_input")
        object.__setattr__(self, "login", login)


Status = Literal["available", "empty", "unavailable", "error", "not_checked"]


@dataclass(frozen=True)
class ModuleResult:
    id: str
    status: Status
    count: int | None = None
    error_code: str | None = None


@dataclass
class ProbeReport:
    authenticated: bool = False
    session_reused: bool | None = None
    session_error_code: str | None = None
    error_code: str | None = None
    diagnostic_code: str | None = None
    modules: list[ModuleResult] = field(default_factory=list)
    protocol_version: int = 1

    def to_dict(self) -> dict[str, Any]:
        """Return only the explicitly defined, non-personal report fields."""
        return asdict(self)
