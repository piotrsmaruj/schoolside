"""Native-app entry point. Requests and responses stay in private process pipes."""

from librus_desktop.main import main

if __name__ == "__main__":
    raise SystemExit(main())
