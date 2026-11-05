import asyncio
import json
import subprocess
import sys
from dataclasses import asdict, replace
from datetime import date
from pathlib import Path
from typing import Any

import pytest
from librus_synergia.models import GradeCategoryData, GradeData, MeData, MessageData, PointGradeData

from librus_desktop.mapping import plain_text, point_grade_item, standard_grade_item
from librus_desktop.models import SchoolItem
from librus_desktop.snapshot import collect_snapshot, message_item


def point_grade(points: float | None, maximum: float | None, value: str = "") -> PointGradeData:
    return PointGradeData(
        1, 2, value, points, maximum, 3, "Sprawdzian", 1, True, 1, "2026-10-28", None
    )


def test_percentage_handles_zero_fraction_and_bonus_points() -> None:
    cases = [(0, 20, "0%"), (25, 30, "83,3%"), (110, 100, "110%")]
    for points, maximum, expected in cases:
        item = point_grade_item(point_grade(points, maximum), {2: "Matematyka"})
        assert item.value == expected
        assert item.title == "Matematyka"
        assert "pkt" in item.subtitle


def test_unknown_or_zero_maximum_does_not_invent_percentage() -> None:
    for maximum in [None, 0]:
        item = point_grade_item(point_grade(15, maximum), {})
        assert item.value == "15 pkt"
        assert "%" not in item.value


def test_point_grade_preserves_browsing_metadata() -> None:
    item = point_grade_item(point_grade(25, 30), {2: "Matematyka"})
    assert (item.semester, item.category, item.subject_id) == (1, "Sprawdzian", "2")
    assert item.subtitle == "Sprawdzian · 25 / 30 pkt"


def test_point_average_keeps_raw_points_weights_and_eligibility() -> None:
    grade = point_grade(25, 30)
    item = asdict(point_grade_item(grade, {}))
    assert item.get("grade_points") == 25
    assert item.get("grade_max_points") == 30
    assert item.get("grade_weight") == 1
    assert item.get("counts_to_average") is True
    excluded = asdict(point_grade_item(replace(grade, counts_to_average=False), {}))
    assert excluded.get("counts_to_average") is False


@pytest.mark.parametrize(("weight", "expected"), [(None, 1), (0.5, 0.5), (3, 3), (0, 0)])
def test_point_average_preserves_fractional_and_zero_weights(
    weight: float | None, expected: float
) -> None:
    item = asdict(point_grade_item(replace(point_grade(25, 30), weight=weight), {}))
    assert item.get("grade_weight") == expected


@pytest.mark.parametrize("weight", [float("nan"), float("inf"), -float("inf")])
def test_invalid_weight_does_not_break_json_transport(weight: float) -> None:
    item = asdict(point_grade_item(replace(point_grade(25, 30), weight=weight), {}))
    assert item.get("grade_weight") is None
    json.dumps(item, allow_nan=False)


@pytest.mark.parametrize(
    ("points", "maximum"),
    [
        (None, 20),
        (10, None),
        (10, 0),
        (10, -1),
        (-1, 20),
        (float("nan"), 20),
        (10, float("inf")),
        (float("inf"), 20),
        (1e308, 1e-308),
    ],
)
def test_invalid_points_cannot_contribute_to_percentage_average(
    points: float | None, maximum: float | None
) -> None:
    item = asdict(point_grade_item(point_grade(points, maximum, "80%"), {}))
    assert item.get("grade_points") is None
    assert item.get("grade_max_points") is None
    json.dumps(item, allow_nan=False)


def test_standard_grades_cannot_be_mixed_into_percentage_average() -> None:
    grade = GradeData(7, "5", 3, 2, 2, "2026-02-03", False, False)
    item = asdict(standard_grade_item(grade, {}, {}))
    assert item.get("grade_points") is None
    assert item.get("grade_max_points") is None


def test_standard_grade_resolves_category_and_keeps_comments() -> None:
    grade = GradeData(7, "5", 3, 2, 2, "2026-02-03", False, False, comments=["Opis"])
    item = standard_grade_item(
        grade, {2: "Matematyka"}, {3: GradeCategoryData(3, "Kartkówka", True, 1)}
    )
    assert (item.semester, item.category, item.subject_id) == (2, "Kartkówka", "2")
    assert item.subtitle == "Kartkówka"
    assert item.body == "Opis"


def test_missing_metadata_remains_unknown_without_date_inference() -> None:
    grade = GradeData(7, "5", 3, None, None, "2026-02-03", False, False)
    item = standard_grade_item(grade, {}, {})
    assert (item.semester, item.category, item.subject_id) == (None, None, None)
    assert SchoolItem("legacy", "Matematyka").semester is None


class FakeLibrus:
    async def me(self) -> MeData:
        return MeData(1, "Przykładowy", "Uczeń")

    async def subjects(self) -> dict[int, str]:
        return {2: "Matematyka"}

    async def teachers(self) -> dict[int, str]:
        return {}

    async def classrooms(self) -> dict[int, str]:
        return {}

    async def attendance_types(self) -> dict[int, Any]:
        return {}

    async def grade_categories(self) -> dict[int, GradeCategoryData]:
        return {3: GradeCategoryData(3, "Kartkówka", True, 1)}

    async def grades(self) -> list[GradeData]:
        return []

    async def point_grades(self) -> list[PointGradeData]:
        return [point_grade(25, 30)]

    async def timetable(self, week_of: date | None = None) -> dict[date, list[Any]]:
        return {date(2026, 10, 28): []}

    async def messages(self, mailbox: str = "inbox", *, limit: int = 10) -> list[MessageData]:
        return []

    async def agenda(self) -> list[Any]:
        from librus_synergia.exceptions import LibrusConnectionError

        raise LibrusConnectionError("private body / token")

    async def attendances(self) -> list[Any]:
        return []

    async def homework(self) -> list[Any]:
        return []

    async def announcements(self) -> list[Any]:
        return []


def test_snapshot_includes_point_grades_and_isolates_failed_sections() -> None:
    snapshot = asyncio.run(collect_snapshot(FakeLibrus()))
    assert snapshot.sections["grades"][0].value == "83,3%"
    assert snapshot.errors["agenda"] == "connection_error"
    assert "messages" in snapshot.sections
    assert "private" not in str(snapshot.errors)


def test_failed_category_reference_preserves_both_grade_sources() -> None:
    class FailedCategories(FakeLibrus):
        async def grade_categories(self) -> dict[int, GradeCategoryData]:
            from librus_synergia.exceptions import LibrusConnectionError

            raise LibrusConnectionError("private category failure")

        async def grades(self) -> list[GradeData]:
            return [GradeData(7, "5", 3, 2, 2, "2026-02-03", False, False)]

    snapshot = asyncio.run(collect_snapshot(FailedCategories()))
    grades = snapshot.sections["grades"]
    assert [item.id for item in grades] == ["point:1", "grade:7"]
    assert grades[1].category is None
    assert "grades" not in snapshot.errors
    assert snapshot.errors["grade_categories"] == "connection_error"
    assert "references" not in snapshot.errors
    assert "private" not in str(snapshot.errors)


def test_snapshot_resolves_standard_grade_categories() -> None:
    class WithStandardGrades(FakeLibrus):
        async def grades(self) -> list[GradeData]:
            return [GradeData(7, "5", 3, 2, 2, "2026-02-03", False, False)]

    snapshot = asyncio.run(collect_snapshot(WithStandardGrades()))
    assert snapshot.sections["grades"][1].category == "Kartkówka"


def test_full_message_keeps_attachment_filename() -> None:
    from librus_synergia.models import AttachmentData, FullMessageData

    message = FullMessageData(
        "1", "inbox", "Nauczyciel", "Temat", "Treść", None, None, [AttachmentData("2", "plan.pdf")]
    )
    item = message_item(message)
    assert item.attachments[0].name == "plan.pdf"
    assert item.attachments[0].id == "2"
    assert item.has_attachments is True


def test_message_preview_keeps_attachment_flag_without_fetching_files() -> None:
    for present in [False, True]:
        message = MessageData("1", "Nauczyciel", "Temat", "Podgląd", None, None, present)
        item = message_item(message)
        assert item.has_attachments is present
        assert item.attachments == []


def test_message_text_preserves_links_and_removes_script_content() -> None:
    value = plain_text(
        '<p>Plan <a href="https://example.org/plan">tutaj</a></p><script>private_script()</script>'
    )
    assert "https://example.org/plan" in value
    assert "private_script" not in value


def test_desktop_process_rejects_invalid_request_without_disclosing_password() -> None:
    entry = Path(__file__).parents[1] / "src/run_school.py"
    request = {"operation": "unsupported", "login": "1234567", "password": "PRIVATE-SECRET"}
    result = subprocess.run(
        [sys.executable, str(entry)],
        input=json.dumps(request).encode(),
        capture_output=True,
        timeout=5,
        check=False,
    )
    assert result.returncode == 1
    assert json.loads(result.stdout)["error_code"] == "invalid_input"
    assert b"PRIVATE-SECRET" not in result.stdout + result.stderr


def test_snapshot_never_opens_message_contents_during_sync() -> None:
    class ReadOnlyLibrus(FakeLibrus):
        async def message(self, *args: object) -> None:
            raise AssertionError("A sync must not mark a message read")

        async def download_attachment(self, *args: object) -> None:
            raise AssertionError("A sync must not fetch files")

    snapshot = asyncio.run(collect_snapshot(ReadOnlyLibrus()))
    assert snapshot.sections["messages"] == []
