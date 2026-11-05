"""Translate library models into readable records, preserving percentages and points."""

import math
from html.parser import HTMLParser

from librus_synergia.models import GradeCategoryData, GradeData, PointGradeData

from .models import SchoolItem


class PlainText(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.hidden = 0
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in {"script", "style"}:
            self.hidden += 1
        if tag in {"br", "p", "div", "li"}:
            self.parts.append("\n")
        if tag == "a":
            href = dict(attrs).get("href") or ""
            self.links.append(href if href.startswith(("https://", "http://", "mailto:")) else "")

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style"}:
            self.hidden = max(0, self.hidden - 1)
        if tag in {"p", "div", "li"}:
            self.parts.append("\n")
        if tag == "a" and self.links:
            link = self.links.pop()
            if link:
                self.parts.append(f" ({link})")

    def handle_data(self, data: str) -> None:
        if not self.hidden:
            self.parts.append(data)


def plain_text(value: str) -> str:
    parser = PlainText()
    parser.feed(value)
    return "".join(parser.parts).strip()


def number(value: float) -> str:
    return f"{value:g}".replace(".", ",")


def point_grade_percentage(grade: PointGradeData) -> float | None:
    """Validate point data before displaying a percentage; never infer it from text."""
    points, maximum = grade.points, grade.max_points
    if (
        points is None
        or maximum is None
        or not math.isfinite(points)
        or not math.isfinite(maximum)
        or points < 0
        or maximum <= 0
    ):
        return None
    percentage = (points / maximum) * 100
    return percentage if math.isfinite(percentage) else None


def point_grade_item(grade: PointGradeData, subjects: dict[int | str, str]) -> SchoolItem:
    points, maximum = grade.points, grade.max_points
    percentage = point_grade_percentage(grade)
    weight = grade.weight if grade.weight is not None else 1.0
    valid_points = points is not None and math.isfinite(points)
    if percentage is not None and points is not None and maximum is not None:
        value = f"{number(round(percentage, 1))}%"
        result = f"{number(points)} / {number(maximum)} pkt"
    elif valid_points and points is not None:
        value, result = f"{number(points)} pkt", "Nie podano maksymalnej liczby punktów"
    else:
        value, result = grade.value, ""
    return SchoolItem(
        id=f"point:{grade.id}",
        title=subjects.get(grade.subject_id or "", "Przedmiot"),
        subtitle=" · ".join(filter(None, [grade.category, result])),
        date=grade.add_date or "",
        value=value,
        semester=grade.semester,
        category=grade.category,
        subject_id=str(grade.subject_id) if grade.subject_id is not None else None,
        grade_points=points if percentage is not None else None,
        grade_max_points=maximum if percentage is not None else None,
        grade_weight=weight if math.isfinite(weight) else None,
        counts_to_average=grade.counts_to_average,
    )


def standard_grade_item(
    grade: GradeData,
    subjects: dict[int | str, str],
    categories: dict[int, GradeCategoryData],
) -> SchoolItem:
    category = categories.get(grade.category_id) if grade.category_id is not None else None
    return SchoolItem(
        id=f"grade:{grade.id}",
        title=subjects.get(grade.subject_id if grade.subject_id is not None else "", "Przedmiot"),
        subtitle=category.name if category else "",
        value=grade.value,
        date=grade.add_date or "",
        body="\n".join(grade.comments),
        semester=grade.semester,
        category=category.name if category else None,
        subject_id=str(grade.subject_id) if grade.subject_id is not None else None,
    )
