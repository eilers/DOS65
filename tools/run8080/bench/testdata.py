"""Locations of external test programs.  Nothing here is stored in git.

CPM2DOS65_TESTDATA   directory for downloaded CPU test programs
                     (default: tools/run8080/tests/data/external)
CPM2DOS65_CPM_DIR    directory with CP/M disk images, containing prod/
                     (default: ~/Downloads/cpm)
"""

from __future__ import annotations

import os
import urllib.request
from pathlib import Path

from .toolchain import PACKAGE_DIR

CPU_TESTS = {
    "TST8080.COM": "https://raw.githubusercontent.com/superzazu/8080/master/cpu_tests/TST8080.COM",
    "8080PRE.COM": "https://raw.githubusercontent.com/superzazu/8080/master/cpu_tests/8080PRE.COM",
    "CPUTEST.COM": "https://raw.githubusercontent.com/superzazu/8080/master/cpu_tests/CPUTEST.COM",
    "8080EXM.COM": "https://raw.githubusercontent.com/superzazu/8080/master/cpu_tests/8080EXM.COM",
    "ZEXDOC.COM": "https://raw.githubusercontent.com/anotherlin/z80emu/master/testfiles/zexdoc.com",
    "ZEXALL.COM": "https://raw.githubusercontent.com/anotherlin/z80emu/master/testfiles/zexall.com",
}


def testdata_dir() -> Path:
    env = os.environ.get("CPM2DOS65_TESTDATA")
    if env:
        return Path(env)
    return PACKAGE_DIR.parent / "tests" / "data" / "external"


def cpm_dir() -> Path:
    env = os.environ.get("CPM2DOS65_CPM_DIR")
    return Path(env) if env else Path.home() / "Downloads" / "cpm"


def cpu_test(name: str) -> Path | None:
    path = testdata_dir() / name
    return path if path.exists() else None


def fetch_cpu_tests() -> list[Path]:
    target = testdata_dir()
    target.mkdir(parents=True, exist_ok=True)
    fetched = []
    for name, url in CPU_TESTS.items():
        path = target / name
        if not path.exists():
            with urllib.request.urlopen(url, timeout=30) as response:
                path.write_bytes(response.read())
        fetched.append(path)
    return fetched
