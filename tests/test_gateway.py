"""Verify safety-sensitive boundaries with only the external client substituted."""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import aiohttp
import pytest
from librus_synergia.client import LibrusApiClient, LibrusSessionData

from librus_probe.gateway import LibrusGateway
from librus_probe.models import Module, ProbeError


def test_messages_only_fetch_preview_list() -> None:
    async def scenario() -> int:
        client = MagicMock(spec=LibrusApiClient)
        client.async_bootstrap_messages = AsyncMock(return_value=True)
        client.async_get_messages = AsyncMock(return_value={"data": [{"id": 1}]})
        gateway = LibrusGateway(20, 5)
        gateway._client = client
        count = await gateway.count(Module.MESSAGES)
        client.async_get_messages.assert_awaited_once_with(limit=5)
        client.async_get_message.assert_not_called()
        client.async_send_message.assert_not_called()
        client.async_mark_school_notice_read.assert_not_called()
        return count

    assert asyncio.run(scenario()) == 1


def test_denied_mailbox_is_not_reported_as_empty() -> None:
    async def scenario() -> None:
        client = MagicMock(spec=LibrusApiClient)
        client.async_bootstrap_messages = AsyncMock(return_value=False)
        gateway = LibrusGateway(20, 5)
        gateway._client = client
        with pytest.raises(ProbeError, match="access_denied"):
            await gateway.count(Module.MESSAGES)
        client.async_get_messages.assert_not_called()

    asyncio.run(scenario())


def test_reuse_imports_cookies_into_new_session_without_password_login() -> None:
    async def scenario() -> None:
        original = MagicMock(spec=LibrusApiClient)
        original.username = "1234567"
        original.export_session.return_value = LibrusSessionData(
            cookies=[{"name": "oauth_token", "value": "private", "domain": "synergia.librus.pl"}],
            logged_in_at=1,
        )
        resumed = MagicMock(spec=LibrusApiClient)
        resumed.login_count = 0
        resumed.async_get_me = AsyncMock(
            return_value={"Me": {"Account": {"Id": 1}, "User": {"Id": 2}}}
        )
        gateway = LibrusGateway(20, 5)
        gateway._client = original
        with patch("librus_probe.gateway.LibrusApiClient", return_value=resumed) as factory:
            await gateway.reuse_session()
        resumed.import_session.assert_called_once_with(original.export_session.return_value)
        resumed.async_get_me.assert_awaited_once()
        resumed.async_login.assert_not_called()
        session = factory.call_args.args[0]
        assert isinstance(session, aiohttp.ClientSession)
        assert session.closed

    asyncio.run(scenario())
