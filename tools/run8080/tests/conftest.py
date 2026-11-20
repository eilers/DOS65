"""Paths for the CPU suites.  Nothing in this file imports the old translator."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from bench import testdata  # noqa: E402


@pytest.fixture
def cpu_test():
    def get(name: str) -> bytes:
        path = testdata.cpu_test(name)
        if path is None:
            pytest.skip(f"{name} missing (set CPM2DOS65_TESTDATA)")
        return path.read_bytes()
    return get


@pytest.fixture
def cpm_image():
    def get(relative: str):
        path = testdata.cpm_dir() / relative
        if not path.exists():
            pytest.skip(f"{path} missing (set CPM2DOS65_CPM_DIR)")
        return path
    return get
