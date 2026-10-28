"""Build the native local desktop app; the connection-check app remains separate."""

import plistlib
import subprocess
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
BUILD = PROJECT / "build"
BUNDLE = BUILD / "Schoolside.app"


def main() -> None:
    binaries = BUNDLE / "Contents" / "MacOS"
    binaries.mkdir(parents=True, exist_ok=True)
    sources = [
        "AppIdentity.swift",
        "ProbeModels.swift",
        "SchoolModels.swift",
        "SchoolDates.swift",
        "SchoolNews.swift",
        "SchoolDayOverview.swift",
        "SecureVault.swift",
        "SchoolBackend.swift",
        "SchoolNotifications.swift",
        "SchoolAppearance.swift",
        "SchoolPalette.swift",
        "TimetableWeek.swift",
        "SchoolTimetableView.swift",
        "SchoolTimetablePresentation.swift",
        "SchoolGradeList.swift",
        "SchoolGradesView.swift",
        "SchoolMessageList.swift",
        "SchoolMessagesView.swift",
        "SchoolViewModel.swift",
        "SchoolViews.swift",
        "SchoolTodayView.swift",
        "SchoolNewsView.swift",
        "SchoolSettingsView.swift",
        "SchoolsideApp.swift",
    ]
    subprocess.run(
        [
            "swiftc",
            "-swift-version",
            "6",
            "-parse-as-library",
            "-O",
            "-target",
            "arm64-apple-macosx14.0",
            "-module-cache-path",
            str(BUILD / "ModuleCache"),
            *[str(PROJECT / "native" / name) for name in sources],
            "-o",
            str(binaries / "Schoolside"),
        ],
        check=True,
    )
    info = {
        "CFBundleExecutable": "Schoolside",
        # Keep the existing identity to preserve Keychain access and user preferences.
        "CFBundleIdentifier": "local.librus.desktop",
        "CFBundleName": "Schoolside",
        "CFBundleDisplayName": "Schoolside",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "14.0",
        "NSHighResolutionCapable": True,
        "SchoolProjectRoot": str(PROJECT),
    }
    with (BUNDLE / "Contents" / "Info.plist").open("wb") as output:
        plistlib.dump(info, output)
    subprocess.run(["codesign", "--force", "--sign", "-", str(BUNDLE)], check=True)
    print(BUNDLE)


if __name__ == "__main__":
    main()
