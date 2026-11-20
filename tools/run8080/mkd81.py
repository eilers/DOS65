#!/usr/bin/env python3
"""Make a DOS/65 1581 disk (.d81) from CP/M files.

    mkd81.py OUT.d81 --name SUPERCALC --from SuperCalc_v2.d81
    mkd81.py OUT.d81 --name TOOLS FILE.COM OTHER.DAT

--from copies every user 0 file of a CP/M disk image that bench.diskimage
reads (C128 CP/M .d64/.d71, raw CP/M .d81, DOS/65 .d81, also gzip
compressed). Further arguments are host files to add.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from bench import d81  # noqa: E402
from bench.diskimage import CpmImage  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("output", type=Path)
    parser.add_argument("files", nargs="*", type=Path, help="host files to add")
    parser.add_argument("--from", dest="source", type=Path, help="CP/M disk image to copy")
    parser.add_argument("--name", default="DOS65", help="CBM disk name (16 characters)")
    parser.add_argument("--id", default="65", help="CBM disk id (2 characters)")
    args = parser.parse_args(argv)

    files: dict[str, bytes] = {}
    if args.source:
        image = CpmImage.open(args.source)
        for name in image.files():
            files[name] = image.read(name)
    for path in args.files:
        files[path.name.upper()] = path.read_bytes()
    if not files:
        parser.error("no files given")

    args.output.write_bytes(d81.build(files, args.name, args.id))
    used = sum((len(data) + d81.BLOCK - 1) // d81.BLOCK for data in files.values())
    free = (d81.BLOCKS - d81.DIR_BLOCKS - used) * d81.BLOCK // 1024
    print(f"{args.output}: {len(files)} files, {free} KB free")
    return 0


if __name__ == "__main__":
    sys.exit(main())
