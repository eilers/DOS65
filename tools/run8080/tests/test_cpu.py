"""The two short 8080 diagnostics under the Python bench.

CPUTEST and 8080EXM are the long suites.  8080EXM is about three billion
instructions, so it is recorded from an emulator session rather than this
bench.  TST8080 and 8080PRE print their result through BDOS function 9.
"""

import tempfile
from pathlib import Path

from tests.harness import run_loaded


def _run(program: bytes, name: str, limit: int):
    return run_loaded(Path(tempfile.mkdtemp()), program, tail=name, limit=limit)


def test_8080pre(cpu_test):
    machine = _run(cpu_test("8080PRE.COM"), "8080pre", 30_000_000)
    text = machine.console.text()
    assert machine.exit_reason == "exit", text[-200:]
    assert "8080 Preliminary tests complete" in text


def test_tst8080(cpu_test):
    machine = _run(cpu_test("TST8080.COM"), "tst8080", 80_000_000)
    text = machine.console.text()
    assert "CPU HAS FAILED" not in text
    assert "CPU IS OPERATIONAL" in text
