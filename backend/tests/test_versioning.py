"""Version metadata tests."""

import tomllib
from pathlib import Path


def test_backend_version_file_matches_project_metadata() -> None:
    """Checks the backend version file and package metadata stay in sync."""
    backend_root = Path(__file__).resolve().parents[1]
    version = (backend_root / "VERSION").read_text(encoding="utf-8").strip()
    pyproject = tomllib.loads(
        (backend_root / "pyproject.toml").read_text(encoding="utf-8"),
    )

    assert pyproject["project"]["version"] == version
