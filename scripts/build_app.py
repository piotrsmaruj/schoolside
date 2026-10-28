"""Build the local SwiftUI connection-check bundle, without a global installation."""

import os
import plistlib
import subprocess
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
BUILD = PROJECT / "build"
BUNDLE = BUILD / "Schoolside Connection Check.app"
EXECUTABLE = "SchoolsideConnectionCheck"


def main() -> None:
    contents = BUNDLE / "Contents"
    binaries = contents / "MacOS"
    binaries.mkdir(parents=True, exist_ok=True)
    command = [
        "swiftc",
        "-swift-version",
        "6",
        "-parse-as-library",
        "-O",
        "-target",
        "arm64-apple-macosx14.0",
        "-module-cache-path",
        str(BUILD / "ModuleCache"),
        *[
            str(PROJECT / "native" / name)
            for name in (
                "AppIdentity.swift",
                "ProbeModels.swift",
                "ProbeRunner.swift",
                "ConnectionCheckApp.swift",
            )
        ],
        "-o",
        str(binaries / EXECUTABLE),
    ]
    subprocess.run(command, check=True, env=os.environ.copy())
    info = {
        "CFBundleExecutable": EXECUTABLE,
        "CFBundleIdentifier": "local.librus.connection-check",
        "CFBundleName": "Schoolside Connection Check",
        "CFBundleDisplayName": "Schoolside — test połączenia",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "14.0",
        "NSHighResolutionCapable": True,
        "ProbeProjectRoot": str(PROJECT),
    }
    with (contents / "Info.plist").open("wb") as output:
        plistlib.dump(info, output)
    print(BUNDLE)


if __name__ == "__main__":
    main()
