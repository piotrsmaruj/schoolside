"""Absolute-path entry point used by the macOS bundle."""

from librus_probe.__main__ import main

if __name__ == "__main__":
    raise SystemExit(main())
