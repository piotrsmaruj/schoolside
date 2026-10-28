"""Run independent module checks without reading or modifying message contents."""

from typing import Protocol

from .models import Credentials, Module, ModuleResult, ProbeError, ProbeReport, Status


class ProbeGateway(Protocol):
    async def login(self, credentials: Credentials) -> None: ...
    async def count(self, module: Module) -> int: ...
    async def reuse_session(self) -> None: ...


async def check_module(gateway: ProbeGateway, module: Module) -> ModuleResult:
    try:
        count = await gateway.count(module)
        return ModuleResult(module.value, "available" if count else "empty", count)
    except ProbeError as error:
        status: Status = "unavailable" if error.code == "access_denied" else "error"
        return ModuleResult(module.value, status, error_code=error.code)


async def run_probe(gateway: ProbeGateway, credentials: Credentials) -> ProbeReport:
    """Authenticate once, isolate module failures, then verify session-only access."""
    report = ProbeReport()
    try:
        await gateway.login(credentials)
    except ProbeError as error:
        report.error_code = error.code
        report.diagnostic_code = error.diagnostic_code
    else:
        report.authenticated = True
    for module in Module:
        if report.error_code:
            report.modules.append(ModuleResult(module.value, "not_checked"))
            continue
        result = await check_module(gateway, module)
        report.modules.append(result)
        if result.error_code in {"session_expired", "auth_failed", "captcha_required"}:
            report.error_code = result.error_code
    if report.authenticated and not report.error_code:
        await check_reuse(gateway, report)
    return report


async def check_reuse(gateway: ProbeGateway, report: ProbeReport) -> None:
    try:
        await gateway.reuse_session()
        report.session_reused = True
    except ProbeError as error:
        report.session_reused = False
        report.session_error_code = error.code
