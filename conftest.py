"""pytest fixtures for temp sqlite state."""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path
from typing import Iterator

import pytest

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import database


@pytest.fixture(autouse=True)
def isolated_database(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    """reset database per test."""
    db_path = tmp_path / "test_library.db"
    monkeypatch.setattr(database, "DATABASE", str(db_path))
    database.init_database()
    yield
    try:
        db_path.unlink()
    except FileNotFoundError:
        pass


@pytest.fixture
def raw_connection() -> Iterator[sqlite3.Connection]:
    """yield raw sqlite connection."""
    conn = database.get_db_connection()
    try:
        yield conn
    finally:
        conn.close()
