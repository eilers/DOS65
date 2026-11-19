"""Wrappers for the external assemblers: bsa (6502) and z80asm (8080/Z80)."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

PACKAGE_DIR = Path(__file__).resolve().parent
REPO_ROOT = PACKAGE_DIR.parents[2]


class ToolError(RuntimeError):
    pass


def bsa_path() -> Path:
    override = os.environ.get("CPM2DOS65_BSA")
    if override:
        return Path(override)
    path = REPO_ROOT / "bsa" / "bsa"
    if not path.exists():
        source = REPO_ROOT / "bsa" / "bsa.c"
        if not source.exists():
            raise ToolError(f"bsa not found: {path} (checkout submodules)")
        subprocess.run(["make", "-C", str(source.parent)], check=True,
                       capture_output=True)
    return path


def z80asm_path() -> Path:
    override = os.environ.get("CPM2DOS65_Z80ASM")
    found = override or shutil.which("z80asm")
    if not found:
        raise ToolError("z80asm not found in PATH")
    return Path(found)


@dataclass
class BsaResult:
    binary: bytes
    symbols: dict[str, int]
    listing: str


_SYMBOL_LINE = re.compile(r"^(\S+)\s+\$([0-9a-fA-F]{4,8})\s")


def parse_bsa_symbols(listing: str) -> dict[str, int]:
    symbols: dict[str, int] = {}
    in_table = False
    for line in listing.splitlines():
        if re.match(r"^\s*\d+ Symbols", line):
            in_table = True
            continue
        if in_table:
            match = _SYMBOL_LINE.match(line)
            if match:
                # "LOW/HIGH": symbol used as a zero page pointer (pair)
                value = int(match.group(2), 16)
                for index, name in enumerate(match.group(1).split("/")):
                    symbols.setdefault(name, value + index)
    return symbols


def assemble_6502(source: str, output_name: str = "OUT.COM",
                  workdir: Path | None = None) -> BsaResult:
    """Assemble bsa source text.  The source must contain a .STORE directive
    that writes `output_name`."""
    own_dir = workdir is None
    work = Path(tempfile.mkdtemp(prefix="cpm2dos65_bsa_")) if own_dir else workdir
    work.mkdir(parents=True, exist_ok=True)
    try:
        asm = work / "prog.asm"
        asm.write_text(source)
        out = work / output_name
        if out.exists():
            out.unlink()
        proc = subprocess.run([str(bsa_path()), "prog.asm"], cwd=work,
                              capture_output=True, text=True)
        listing_path = work / "prog.lst"
        listing = listing_path.read_text(errors="replace") if listing_path.exists() else ""
        if proc.returncode != 0 or not out.exists():
            errors = [l for l in (proc.stdout + proc.stderr).splitlines()
                      if l.strip() and not l.startswith("*")]
            raise ToolError("bsa failed:\n" + "\n".join(errors[-30:]))
        return BsaResult(out.read_bytes(), parse_bsa_symbols(listing), listing)
    finally:
        if own_dir:
            shutil.rmtree(work, ignore_errors=True)


def assemble_z80_with_labels(source: str) -> tuple[bytes, dict[str, int]]:
    with tempfile.TemporaryDirectory(prefix="cpm2dos65_z80_") as tmp:
        asm = Path(tmp) / "prog.asm"
        out = Path(tmp) / "prog.bin"
        asm.write_text(source)
        proc = subprocess.run([str(z80asm_path()), "-L", "-o", str(out), str(asm)],
                              capture_output=True, text=True)
        if proc.returncode != 0:
            raise ToolError("z80asm failed:\n" + proc.stderr)
        labels = {m.group(1): int(m.group(2), 16) for m in
                  re.finditer(r"^(\w+):\s+equ \$([0-9a-fA-F]+)", proc.stdout + proc.stderr,
                              re.MULTILINE)}
        return (out.read_bytes() if out.exists() else b""), labels


def assemble_z80(source: str) -> bytes:
    return assemble_z80_with_labels(source)[0]
