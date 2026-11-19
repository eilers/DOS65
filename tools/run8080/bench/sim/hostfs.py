"""CP/M style file system on a host directory.

Both the CP/M emulator and the DOS/65 emulator use this class, so a CP/M
program and its translation work on the same kind of files.  FCB layout
(shared by CP/M and DOS/65): 0 drive, 1-8 name, 9-11 type, 12 extent,
15 record count, 16-31 allocation, 32 next record, 33-35 random record
(CP/M only).  Drive 0 means the current drive, 1..16 drive A..P; drive A is
the root directory, drive B is subdirectory "B" and so on.
"""

from __future__ import annotations

from pathlib import Path

RECORD = 128
EXTENT_RECORDS = 128
EOF_BYTE = 0x1A


def _match(pattern: bytes, name: bytes) -> bool:
    return all(p == ord("?") or (p & 0x7F) == (n & 0x7F)
               for p, n in zip(pattern, name))


class HostFS:
    def __init__(self, root: Path, max_extents: int = 32 * 2048):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True)
        self.current_drive = 0
        self.max_extents = max_extents
        self._search: list[tuple[bytes, int, int]] = []
        self.log: list[tuple] = []

    # ----- helpers ----------------------------------------------------------
    def drive_dir(self, drive: int) -> Path:
        index = self.current_drive if drive == 0 else drive - 1
        path = self.root if index == 0 else self.root / chr(ord("A") + index)
        path.mkdir(exist_ok=True)
        return path

    @staticmethod
    def fcb_name(mem, fcb: int) -> bytes:
        return bytes(mem[fcb + 1 + i] & 0x7F for i in range(11))

    @staticmethod
    def host_name(name11: bytes) -> str:
        base = name11[:8].decode("latin-1").rstrip()
        ext = name11[8:].decode("latin-1").rstrip()
        return f"{base}.{ext}" if ext else base

    @staticmethod
    def name11(host: str) -> bytes | None:
        if "." in host:
            base, ext = host.rsplit(".", 1)
        else:
            base, ext = host, ""
        if not base or len(base) > 8 or len(ext) > 3 or host.upper() != host:
            return None
        return (base.ljust(8) + ext.ljust(3)).encode("latin-1")

    def path_for(self, mem, fcb: int) -> Path:
        return self.drive_dir(mem[fcb]) / self.host_name(self.fcb_name(mem, fcb))

    def _records(self, path: Path) -> int:
        size = path.stat().st_size if path.exists() else 0
        return (size + RECORD - 1) // RECORD

    def _set_extent_count(self, mem, fcb: int, total: int) -> None:
        extent = mem[fcb + 12] & 0x1F | (mem[fcb + 14] & 0x3F) << 5
        remaining = total - extent * EXTENT_RECORDS
        mem[fcb + 15] = max(0, min(EXTENT_RECORDS, remaining))

    def _record_index(self, mem, fcb: int) -> int:
        extent = mem[fcb + 12] & 0x1F | (mem[fcb + 14] & 0x3F) << 5
        return extent * EXTENT_RECORDS + mem[fcb + 32]

    def _set_position(self, mem, fcb: int, index: int) -> None:
        extent, record = divmod(index, EXTENT_RECORDS)
        mem[fcb + 12] = extent & 0x1F
        mem[fcb + 14] = extent >> 5
        mem[fcb + 32] = record

    def _read_record(self, path: Path, index: int) -> bytes | None:
        with path.open("rb") as handle:
            handle.seek(index * RECORD)
            data = handle.read(RECORD)
        if not data:
            return None
        return data + bytes([EOF_BYTE]) * (RECORD - len(data))

    def _write_record(self, path: Path, index: int, data: bytes) -> None:
        if not path.exists():
            path.write_bytes(b"")
        size = path.stat().st_size
        with path.open("r+b") as handle:
            if size < index * RECORD:
                handle.seek(size)
                handle.write(bytes(index * RECORD - size))
            handle.seek(index * RECORD)
            handle.write(data)

    # ----- BDOS functions (return value in A) -------------------------------
    def open(self, mem, fcb: int) -> int:
        # CP/M 2.2 function 15 clears the module number (byte 14) before it
        # searches.  The macro assembler leaves that byte uninitialized, and
        # a non-zero module would seek hundreds of kilobytes into the file.
        mem[fcb + 14] = 0
        path = self.path_for(mem, fcb)
        self.log.append(("open", self.host_name(self.fcb_name(mem, fcb))))
        if not path.exists():
            return 0xFF
        total = self._records(path)
        extent = mem[fcb + 12] & 0x1F
        if extent and extent * EXTENT_RECORDS >= total:
            return 0xFF
        self._set_extent_count(mem, fcb, total)
        for i in range(16, 32):
            mem[fcb + i] = 0
        mem[fcb + 16] = 1      # non zero allocation, like a used block
        mem[fcb + 13] = 0
        mem[fcb + 14] = 0x80   # file write flag: nothing written since open
        return 0

    def close(self, mem, fcb: int) -> int:
        return 0 if self.path_for(mem, fcb).exists() else 0xFF

    def make(self, mem, fcb: int) -> int:
        path = self.path_for(mem, fcb)
        if not path.exists():
            path.write_bytes(b"")
        # Function 22 clears the module number, then sets the file write flag.
        mem[fcb + 13] = 0
        mem[fcb + 14] = 0x80
        mem[fcb + 15] = 0
        mem[fcb + 32] = 0
        for i in range(16, 32):
            mem[fcb + i] = 0
        return 0

    def delete(self, mem, fcb: int) -> int:
        pattern = self.fcb_name(mem, fcb)
        found = 0xFF
        for path in sorted(self.drive_dir(mem[fcb]).iterdir()):
            name = self.name11(path.name)
            if path.is_file() and name and _match(pattern, name):
                path.unlink()
                found = 0
        return found

    def rename(self, mem, fcb: int) -> int:
        old = self.path_for(mem, fcb)
        new_name = bytes(mem[fcb + 17 + i] & 0x7F for i in range(11))
        if not old.exists():
            return 0xFF
        old.rename(old.parent / self.host_name(new_name))
        return 0

    def search_first(self, mem, fcb: int, dma: int) -> int:
        pattern = self.fcb_name(mem, fcb)
        wanted = mem[fcb + 12]
        all_extents = wanted == ord("?")
        entries = []
        directory = self.drive_dir(mem[fcb])
        for path in sorted(directory.iterdir()):
            name = self.name11(path.name)
            if not (path.is_file() and name and _match(pattern, name)):
                continue
            total = self._records(path)
            extents = max(1, (total + EXTENT_RECORDS - 1) // EXTENT_RECORDS)
            # A question mark lists every 16 KB extent. A number selects that
            # extent, so a random read past the first 16 KB can find its entry.
            if all_extents:
                chosen = range(extents)
            elif wanted < extents:
                chosen = (wanted,)
            else:
                chosen = ()
            for extent in chosen:
                count = min(EXTENT_RECORDS, total - extent * EXTENT_RECORDS)
                entries.append((name, extent, max(0, count)))
        self._search = entries
        return self.search_next(mem, dma)

    def search_next(self, mem, dma: int) -> int:
        if not self._search:
            return 0xFF
        name, extent, count = self._search.pop(0)
        for i in range(128):
            mem[dma + i] = 0xE5
        entry = bytes([0]) + name + bytes([extent & 0x1F, 0, extent >> 5, count]) + bytes(16)
        for i, value in enumerate(entry):
            mem[dma + i] = value
        return 0

    def read_seq(self, mem, fcb: int, dma: int) -> int:
        path = self.path_for(mem, fcb)
        if not path.exists():
            return 1
        index = self._record_index(mem, fcb)
        self.log.append(("read", self.host_name(self.fcb_name(mem, fcb)), index, dma))
        data = self._read_record(path, index)
        if data is None:
            return 1
        for i, value in enumerate(data):
            mem[dma + i] = value
        self._set_position(mem, fcb, index + 1)
        self._set_extent_count(mem, fcb, self._records(path))
        return 0

    def write_seq(self, mem, fcb: int, dma: int) -> int:
        path = self.path_for(mem, fcb)
        index = self._record_index(mem, fcb)
        self.log.append(("write", self.host_name(self.fcb_name(mem, fcb)), index, dma))
        self._write_record(path, index, bytes(mem[dma + i] for i in range(RECORD)))
        self._set_position(mem, fcb, index + 1)
        self._set_extent_count(mem, fcb, self._records(path))
        return 0

    @staticmethod
    def random_record(mem, fcb: int) -> int:
        return mem[fcb + 33] | mem[fcb + 34] << 8 | mem[fcb + 35] << 16

    def read_random(self, mem, fcb: int, dma: int) -> int:
        index = self.random_record(mem, fcb)
        if mem[fcb + 35]:
            return 6
        path = self.path_for(mem, fcb)
        self.log.append(("read_random", self.host_name(self.fcb_name(mem, fcb)), index, dma))
        data = self._read_record(path, index) if path.exists() else None
        total = self._records(path) if path.exists() else 0
        self._set_position(mem, fcb, index)
        self._set_extent_count(mem, fcb, total)
        if data is None:
            last_extent = (total - 1) // EXTENT_RECORDS if total else 0
            return 4 if index // EXTENT_RECORDS > last_extent else 1
        for i, value in enumerate(data):
            mem[dma + i] = value
        return 0

    def write_random(self, mem, fcb: int, dma: int) -> int:
        index = self.random_record(mem, fcb)
        if mem[fcb + 35]:
            return 6
        path = self.path_for(mem, fcb)
        self.log.append(("write_random", self.host_name(self.fcb_name(mem, fcb)), index, dma))
        self._write_record(path, index, bytes(mem[dma + i] for i in range(RECORD)))
        self._set_position(mem, fcb, index)
        self._set_extent_count(mem, fcb, self._records(path))
        return 0

    def file_size(self, mem, fcb: int) -> int:
        path = self.path_for(mem, fcb)
        total = self._records(path) if path.exists() else 0
        mem[fcb + 33] = total & 0xFF
        mem[fcb + 34] = total >> 8 & 0xFF
        mem[fcb + 35] = total >> 16 & 0xFF
        return 0

    def set_random(self, mem, fcb: int) -> None:
        index = self._record_index(mem, fcb)
        mem[fcb + 33] = index & 0xFF
        mem[fcb + 34] = index >> 8 & 0xFF
        mem[fcb + 35] = index >> 16 & 0xFF

    def files(self) -> dict[str, bytes]:
        return {p.name: p.read_bytes() for p in sorted(self.root.iterdir()) if p.is_file()}
