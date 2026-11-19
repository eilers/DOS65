"""Devices shared by the CP/M and the DOS/65 emulator."""

from __future__ import annotations


class ProgramExit(Exception):
    """The program left through warm boot or returned to the system."""


class InputExhausted(Exception):
    """The scripted console input is used up and the program waits for more."""


class Console:
    """Scripted console.  Output is recorded byte by byte.

    pace: after every character read, the status reports "no key" for this
    many polls, so programs that discard typed-ahead keys see the script
    like a typist."""

    def __init__(self, script: bytes = b"", idle_polls: int = 2000, pace: int = 0):
        self.input = bytearray(script)
        self.pace = pace
        self._pace_left = 0
        self.output = bytearray()
        self.column = 0
        self.idle_polls = idle_polls
        self._empty_polls = 0
        self.printer = bytearray()
        self.punch = bytearray()
        self.reader = bytearray()

    def feed(self, data: bytes) -> None:
        self.input.extend(data)

    def status(self) -> bool:
        if self.input:
            self._empty_polls = 0
            if self._pace_left:
                self._pace_left -= 1
                return False
            return True
        self._empty_polls += 1
        if self._empty_polls > self.idle_polls:
            raise InputExhausted()
        return False

    def read(self) -> int:
        if not self.input:
            raise InputExhausted()
        self._empty_polls = 0
        self._pace_left = self.pace
        return self.input.pop(0)

    def write_raw(self, value: int) -> None:
        value &= 0xFF
        self.output.append(value)
        if value == 0x0D:
            self.column = 0
        elif value == 0x08:
            self.column = max(0, self.column - 1)
        elif value >= 0x20:
            self.column += 1

    def write_cooked(self, value: int) -> None:
        """BDOS/PEM console output: TAB expands to the next multiple of 8."""
        if value & 0xFF == 0x09:
            self.write_raw(0x20)
            while self.column % 8:
                self.write_raw(0x20)
        else:
            self.write_raw(value)

    @staticmethod
    def echoes(value: int) -> bool:
        return value >= 0x20 or value in (0x0D, 0x0A, 0x09, 0x08)

    def text(self) -> str:
        return self.output.decode("latin-1")


class RawDisk:
    """Sector addressed disk with 128 byte records for BIOS level tests."""

    def __init__(self, tracks: int = 77, sectors: int = 26):
        self.tracks = tracks
        self.sectors = sectors
        self.data = bytearray(tracks * sectors * 128)

    def offset(self, track: int, sector: int) -> int | None:
        if track >= self.tracks or sector >= self.sectors:
            return None
        return (track * self.sectors + sector) * 128

    def read(self, track: int, sector: int) -> bytes | None:
        offset = self.offset(track, sector)
        return None if offset is None else bytes(self.data[offset:offset + 128])

    def write(self, track: int, sector: int, data: bytes) -> bool:
        offset = self.offset(track, sector)
        if offset is None:
            return False
        self.data[offset:offset + 128] = data
        return True


def parse_command_tail(tail: str) -> tuple[bytes, bytes, bytes]:
    """Return (fcb1, fcb2, buffer) as a CCP builds them (upper case)."""
    tail = tail.upper()
    words = tail.split()

    def make_fcb(word: str | None) -> bytes:
        fcb = bytearray(16)
        fcb[1:12] = b" " * 11
        if not word:
            return bytes(fcb)
        if len(word) > 1 and word[1] == ":":
            fcb[0] = ord(word[0]) - ord("A") + 1
            word = word[2:]
        base, _, ext = word.partition(".")
        for target, text, size in ((1, base, 8), (9, ext, 3)):
            text = text[:size]
            if "*" in text:
                text = text[:text.index("*")].ljust(size, "?")
            fcb[target:target + len(text)] = text.encode("latin-1")
        return bytes(fcb)

    fcb1 = make_fcb(words[0] if words else None)
    fcb2 = make_fcb(words[1] if len(words) > 1 else None)
    text = (" " + tail.strip()) if tail.strip() else ""
    buffer = bytes([len(text)]) + text.encode("latin-1")
    return fcb1, fcb2, buffer
