"""Fetch only the modules used by the UI, preserving independent failure states."""

import asyncio
from collections.abc import Awaitable
from datetime import datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from librus_synergia.exceptions import LibrusError
from librus_synergia.models import GradeCategoryData

from librus_probe.gateway import translate_error

from .mapping import plain_text, point_grade_item, standard_grade_item
from .models import Attachment, SchoolItem, SchoolSnapshot

MESSAGE_LIMIT = 50


async def optional(
    snapshot: SchoolSnapshot, section: str, call: Awaitable[Any], fallback: Any
) -> Any:
    try:
        return await call
    except LibrusError as error:
        snapshot.errors[section] = translate_error(error).code
        return fallback


async def collect_snapshot(librus: Any) -> SchoolSnapshot:
    """A list fetch never opens a full message or downloads an attachment."""
    me = await librus.me()
    now = datetime.now(ZoneInfo("Europe/Warsaw"))
    snapshot = SchoolSnapshot(me.display_name, now.isoformat())
    subjects, teachers, rooms, attendance_types, grade_categories = await asyncio.gather(
        optional(snapshot, "references", librus.subjects(), {}),
        optional(snapshot, "references", librus.teachers(), {}),
        optional(snapshot, "references", librus.classrooms(), {}),
        optional(snapshot, "references", librus.attendance_types(), {}),
        optional(snapshot, "grade_categories", librus.grade_categories(), {}),
    )
    monday = now.date() - timedelta(days=now.weekday())
    results = await asyncio.gather(
        optional(snapshot, "timetable", librus.timetable(monday), {}),
        optional(snapshot, "timetable", librus.timetable(monday + timedelta(days=7)), {}),
        optional(snapshot, "grades", librus.grades(), []),
        optional(snapshot, "grades", librus.point_grades(), []),
        optional(snapshot, "messages", librus.messages(limit=MESSAGE_LIMIT), []),
        optional(snapshot, "agenda", librus.agenda(), []),
        optional(snapshot, "attendance", librus.attendances(), []),
        optional(snapshot, "homework", librus.homework(), []),
        optional(snapshot, "announcements", librus.announcements(), []),
    )
    build_sections(snapshot, results, subjects, teachers, rooms, attendance_types, grade_categories)
    return snapshot


def build_sections(
    snapshot: SchoolSnapshot,
    results: list[Any],
    subjects: dict[int | str, str],
    teachers: dict[int | str, str],
    rooms: dict[int | str, str],
    attendance_types: dict[int | str, Any],
    grade_categories: dict[int, GradeCategoryData],
) -> None:
    week, next_week, grades, points, messages, agenda, attendance, homework, notices = results
    snapshot.sections["timetable"] = timetable_items(
        {**week, **next_week}, subjects, teachers, rooms
    )
    snapshot.sections["grades"] = sorted(
        [standard_grade_item(g, subjects, grade_categories) for g in grades]
        + [point_grade_item(g, subjects) for g in points],
        key=lambda item: item.date,
        reverse=True,
    )
    snapshot.sections["messages"] = [message_item(message) for message in messages]
    snapshot.sections["agenda"] = [
        SchoolItem(
            str(e.id),
            subjects.get(e.subject_id, "Wydarzenie"),
            body=plain_text(e.content),
            date=e.date or "",
            time=e.time_from or "",
        )
        for e in agenda
    ]
    snapshot.sections["attendance"] = [
        SchoolItem(
            str(a.id),
            getattr(attendance_types.get(a.type_id), "name", "Wpis frekwencji"),
            subtitle=f"Lekcja {a.lesson_no}" if a.lesson_no is not None else "",
            date=a.date or "",
        )
        for a in attendance
    ]
    snapshot.sections["homework"] = [
        SchoolItem(
            str(h.id),
            h.topic or "Zadanie domowe",
            subtitle=teachers.get(h.teacher_id, ""),
            body=plain_text(h.text),
            date=h.due_date or h.date or "",
            homework_due_date=h.due_date or None,
            attachments=[Attachment(str(a.id), a.filename or "Załącznik") for a in h.attachments],
        )
        for h in homework
    ]
    snapshot.sections["announcements"] = [
        SchoolItem(
            str(n.id),
            n.subject,
            body=plain_text(n.content),
            date=n.creation_date or n.start_date or "",
            unread=not n.was_read,
        )
        for n in notices
    ]


def timetable_items(
    timetable: dict[Any, list[Any]],
    subjects: dict[int | str, str],
    teachers: dict[int | str, str],
    rooms: dict[int | str, str],
) -> list[SchoolItem]:
    result = []
    for day, lessons in sorted(timetable.items()):
        for index, lesson in enumerate(lessons):
            room = rooms.get(lesson.classroom_id, "")
            subtitle = " · ".join(
                filter(None, [teachers.get(lesson.teacher_id, ""), f"Sala {room}" if room else ""])
            )
            status = (
                "Odwołana" if lesson.is_canceled else "Zastępstwo" if lesson.is_substitution else ""
            )
            result.append(
                SchoolItem(
                    f"{day}:{index}",
                    subjects.get(lesson.subject_id, "Lekcja"),
                    subtitle=subtitle,
                    body=lesson.substitution_note or "",
                    date=str(day),
                    time=f"{lesson.hour_from or ''}–{lesson.hour_to or ''}",
                    value=status,
                    canceled=lesson.is_canceled,
                )
            )
    return result


def message_item(message: Any) -> SchoolItem:
    return SchoolItem(
        str(message.id),
        message.topic or "Wiadomość",
        subtitle=message.sender_name,
        body=plain_text(message.content),
        date=message.send_date or "",
        unread=message.read_date is None,
        mailbox=message.mailbox,
        attachments=[
            Attachment(str(a.id), a.filename or "Załącznik")
            for a in getattr(message, "attachments", [])
        ],
        has_attachments=bool(getattr(message, "has_attachment", False))
        or bool(getattr(message, "attachments", [])),
    )
