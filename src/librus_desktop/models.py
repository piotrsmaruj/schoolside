"""Small presentation-independent records passed to the local native app."""

from dataclasses import dataclass, field


@dataclass
class Attachment:
    id: str
    name: str


@dataclass
class SchoolItem:
    id: str
    title: str
    subtitle: str = ""
    body: str = ""
    date: str = ""
    time: str = ""
    value: str = ""
    unread: bool = False
    canceled: bool = False
    mailbox: str = "inbox"
    attachments: list[Attachment] = field(default_factory=list)
    semester: int | None = None
    category: str | None = None
    subject_id: str | None = None
    has_attachments: bool | None = None


@dataclass
class SchoolSnapshot:
    student_name: str
    fetched_at: str
    sections: dict[str, list[SchoolItem]] = field(default_factory=dict)
    errors: dict[str, str] = field(default_factory=dict)
