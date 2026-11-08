"""Compile and run the native unit/integration tests with synthetic input only."""

import subprocess
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
BUILD = PROJECT / "build"
TARGETS = {
    "ProbeModelsTests": ["ProbeModels.swift"],
    "ProbeRunnerTests": ["ProbeModels.swift", "ProbeRunner.swift"],
    "DesktopTests": ["ProbeModels.swift", "SchoolModels.swift", "SecureVault.swift"],
    "SchoolBackendTests": ["ProbeModels.swift", "SchoolModels.swift", "SchoolBackend.swift"],
    "NotificationTests": ["ProbeModels.swift", "SchoolModels.swift", "SchoolNotifications.swift"],
    "AppearanceTests": ["SchoolAppearance.swift"],
    "AgendaListTests": ["ProbeModels.swift", "SchoolModels.swift", "SchoolAgendaList.swift"],
    "PaletteTests": ["SchoolPalette.swift"],
    "GradeListTests": ["ProbeModels.swift", "SchoolModels.swift", "SchoolGradeList.swift"],
    "OrganizerTests": ["ProbeModels.swift", "SchoolModels.swift", "SchoolWeekOverview.swift"],
    "OrganizerModelTests": [
        "ProbeModels.swift",
        "SchoolModels.swift",
        "SecureVault.swift",
        "SchoolBackend.swift",
        "SchoolNotifications.swift",
        "SchoolViewModel.swift",
    ],
    "MessageListTests": ["ProbeModels.swift", "SchoolModels.swift", "SchoolMessageList.swift"],
    "TimetablePresentationTests": [
        "ProbeModels.swift",
        "SchoolModels.swift",
        "TimetableWeek.swift",
        "SchoolTimetablePresentation.swift",
    ],
    "TimetableTests": ["ProbeModels.swift", "SchoolModels.swift", "TimetableWeek.swift"],
    "NewsTests": [
        "ProbeModels.swift",
        "SchoolModels.swift",
        "SchoolDates.swift",
        "SchoolNews.swift",
    ],
    "DayOverviewTests": [
        "ProbeModels.swift",
        "SchoolModels.swift",
        "SchoolDates.swift",
        "SchoolDayOverview.swift",
    ],
    "RefreshTests": [
        "ProbeModels.swift",
        "SchoolModels.swift",
        "SchoolDates.swift",
        "SchoolNews.swift",
        "SecureVault.swift",
        "SchoolBackend.swift",
        "SchoolNotifications.swift",
        "SchoolViewModel.swift",
    ],
    "NewsModelTests": [
        "ProbeModels.swift",
        "SchoolModels.swift",
        "SchoolDates.swift",
        "SchoolNews.swift",
        "SecureVault.swift",
        "SchoolBackend.swift",
        "SchoolNotifications.swift",
        "SchoolViewModel.swift",
    ],
}


def main() -> None:
    BUILD.mkdir(exist_ok=True)
    for name, sources in TARGETS.items():
        sources = ["AppIdentity.swift", *sources]
        if "SchoolModels.swift" in sources:
            for dependency in ["SchoolDates.swift", "SchoolNews.swift", "SchoolOrganizer.swift"]:
                if dependency not in sources:
                    sources.append(dependency)
        if "SchoolNotifications.swift" in sources:
            sources.append("SchoolTaskReminders.swift")
        if "SchoolViewModel.swift" in sources:
            sources.append("SchoolOrganizerActions.swift")
        executable = BUILD / name
        subprocess.run(
            [
                "swiftc",
                "-swift-version",
                "6",
                "-parse-as-library",
                *[str(PROJECT / "native" / source) for source in sources],
                str(PROJECT / "native-tests" / f"{name}.swift"),
                "-module-cache-path",
                str(BUILD / "ModuleCache"),
                "-o",
                str(executable),
            ],
            check=True,
        )
        args = [str(executable)]
        if name in {"ProbeRunnerTests", "SchoolBackendTests"}:
            args.append(str(PROJECT / ".venv/bin/python"))
        subprocess.run(args, check=True)


if __name__ == "__main__":
    main()
