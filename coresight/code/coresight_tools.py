#!/usr/bin/env python3
"""
CoreSight v3.0 helper models for interview prep and testbench reference checks.

Every function here is a small "golden model" of one rule in
ARM IHI 0029E (CoreSight Architecture Specification v3.0):

  decode_ids()         CIDR/PIDR/DEVARCH/DEVTYPE identification   (spec B2.2, B2.3)
  decode_romentry()    Class 0x1 and Class 0x9 ROM table entries  (spec D6.4, D7.5)
  auth_permissions()   Authentication equations and AUTHSTATUS    (spec C5.4, B2.3.1)
  decode_frame()       16-byte trace formatter frames             (spec D4.2)
  encode_frames()      Inverse of decode_frame, for stimulus      (spec D4.2)

Run `python3 coresight_tools.py` to execute the self-tests, which include the
worked formatter example from spec Table D4-2.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# 1. Identification registers (spec B2.2 / B2.3)
# ---------------------------------------------------------------------------

CLASS_NAMES = {
    0x0: "Generic verification component",
    0x1: "ROM table",
    0x9: "CoreSight component",
    0xB: "Peripheral test block",
    0xE: "Generic IP component",
    0xF: "CoreLink / PrimeCell / system component",
}

# Table B2-8 (subset)
ARCHID_NAMES = {
    0x0A00: "RAS", 0x1A01: "ITM", 0x1A02: "DWT", 0x1A03: "FPB",
    0x2A04: "Processor debug v8-M", 0x6A05: "Processor debug v8-R",
    0x0A10: "PC sample-based profiling", 0x4A13: "ETM", 0x1A14: "CTI",
    0x6A15: "Processor debug v8.0-A", 0x7A15: "Processor debug v8.1-A",
    0x8A15: "Processor debug v8.2-A", 0x2A16: "PMU", 0x0A17: "MEM-AP v2",
    0x0A27: "JTAG-AP v2", 0x0A31: "Basic trace router", 0x0A37: "Power requestor",
    0x0A47: "Unknown AP v2", 0x0A50: "HSSTP", 0x0A63: "STM",
    0x0A75: "CoreSight ELA", 0x0AF7: "CoreSight ROM table",
}

# Table B2-9: MAJOR -> (name, {SUB: name})
DEVTYPE_NAMES = {
    0x0: ("Miscellaneous", {0x0: "Other", 0x4: "Validation component"}),
    0x1: ("Trace sink", {0x0: "Other", 0x1: "Trace port (TPIU)", 0x2: "Buffer (ETB)", 0x3: "Basic trace router"}),
    0x2: ("Trace link", {0x0: "Other", 0x1: "Funnel / router", 0x2: "Filter", 0x3: "FIFO / large buffer"}),
    0x3: ("Trace source", {0x0: "Other", 0x1: "Processor core", 0x2: "DSP", 0x3: "Data engine",
                           0x4: "Bus", 0x6: "Software"}),
    0x4: ("Debug control", {0x0: "Other", 0x1: "Trigger matrix (ECT)", 0x2: "Debug authentication module",
                            0x3: "Power requestor"}),
    0x5: ("Debug logic", {0x0: "Other", 0x1: "Processor core", 0x2: "DSP", 0x3: "Data engine",
                          0x4: "Bus", 0x5: "Memory (BIST)"}),
    0x6: ("Performance monitor", {0x0: "Other", 0x1: "Processor", 0x2: "DSP", 0x3: "Data engine",
                                  0x4: "Bus", 0x5: "SMMU"}),
}


@dataclass
class ComponentId:
    preamble_ok: bool
    cls: int
    class_name: str
    part: int
    jep106_cont: int
    jep106_id: int
    is_arm: bool
    revision: int
    revand: int
    cmod: int
    size_log2_4kb: int
    devarch: Optional[Dict] = None
    devtype: Optional[Tuple[str, str]] = None
    errors: List[str] = field(default_factory=list)


def decode_ids(cidr: List[int], pidr: List[int], devarch: Optional[int] = None,
               devtype: Optional[int] = None) -> ComponentId:
    """cidr = [CIDR0..CIDR3], pidr = [PIDR0..PIDR4] (low byte of each register)."""
    c0, c1, c2, c3 = (x & 0xFF for x in cidr)
    p0, p1, p2, p3, p4 = (x & 0xFF for x in pidr[:5])
    errors = []
    preamble_ok = c0 == 0x0D and (c1 & 0xF) == 0x0 and c2 == 0x05 and c3 == 0xB1
    if not preamble_ok:
        errors.append("CIDR preamble must be 0x0D, 0x?0, 0x05, 0xB1")
    cls = (c1 >> 4) & 0xF
    part = p0 | ((p1 & 0xF) << 8)
    jid = ((p1 >> 4) & 0xF) | ((p2 & 0x7) << 4)
    cont = p4 & 0xF
    if not (p2 >> 3) & 1:
        errors.append("PIDR2.JEDEC must be 1")
    size = (p4 >> 4) & 0xF
    if size:
        errors.append("PIDR4.SIZE is deprecated in v3.0; recommended value is 0")
    out = ComponentId(preamble_ok, cls, CLASS_NAMES.get(cls, "reserved"), part, cont, jid,
                      cont == 0x4 and jid == 0x3B, (p2 >> 4) & 0xF, (p3 >> 4) & 0xF, p3 & 0xF,
                      size, errors=errors)
    if devarch is not None:
        present = (devarch >> 20) & 1
        if not present:
            if devarch:
                errors.append("DEVARCH.PRESENT=0 but register is non-zero (must be RAZ)")
            out.devarch = {"present": False}
        else:
            arc = (devarch >> 21) & 0x7FF
            aid = devarch & 0xFFFF
            out.devarch = {"present": True, "architect": arc, "architect_is_arm": arc == 0x23B,
                           "revision": (devarch >> 16) & 0xF, "archid": aid,
                           "arch_name": ARCHID_NAMES.get(aid, "not in Table B2-8")}
    if devtype is not None:
        major, sub = devtype & 0xF, (devtype >> 4) & 0xF
        m = DEVTYPE_NAMES.get(major)
        out.devtype = (m[0], m[1].get(sub, "reserved")) if m else ("reserved", "reserved")
    return out


# ---------------------------------------------------------------------------
# 2. ROM table entries (spec D5.4, D6.4, D7.5)
# ---------------------------------------------------------------------------

@dataclass
class RomEntry:
    kind: str                 # "present" | "skip" | "end" | "reserved"
    address: Optional[int]
    offset_4kb: Optional[int]
    power_id: Optional[int]
    errors: List[str]


def decode_romentry(entry: int, rom_base: int, rom_class: int = 0x1, width: int = 32) -> RomEntry:
    """Decode one ROMENTRY. rom_class 0x1 or 0x9; width 32 or 64 (class 0x9 DEVID.FORMAT)."""
    errors: List[str] = []
    if rom_class == 0x1:
        if entry == 0:
            return RomEntry("end", None, None, None, errors)
        present = entry & 1
        if not (entry >> 1) & 1:
            errors.append("Class 0x1 FORMAT bit must read as 1")
        kind = "present" if present else "skip"
    elif rom_class == 0x9:
        pr = entry & 0x3
        if pr == 0b00:
            if entry:
                errors.append("PRESENT=0b00 requires all other fields zero")
            return RomEntry("end", None, None, None, errors)
        kind = {0b01: "reserved", 0b10: "skip", 0b11: "present"}[pr]
    else:
        raise ValueError("rom_class must be 0x1 or 0x9")

    pid_valid = (entry >> 2) & 1
    pid = (entry >> 4) & 0x1F
    if not pid_valid and pid:
        errors.append("POWERID must be zero when POWERIDVALID=0")
    off_bits = width - 12
    raw = (entry >> 12) & ((1 << off_bits) - 1)
    off = raw - (1 << off_bits) if raw >> (off_bits - 1) else raw   # two's complement
    addr = None
    if kind == "present":
        if off == 0:
            errors.append("OFFSET=0 points back to this ROM table (illegal)")
        addr = (rom_base + (off << 12)) & ((1 << 64) - 1)
    return RomEntry(kind, addr, off, pid if pid_valid else None, errors)


def walk_rom(read32, base: int, rom_class: int = 0x1, max_entries: int = 960) -> List[RomEntry]:
    """Walk one ROM table using a read32(addr) callback. Stops at the end marker."""
    out = []
    step = 4
    limit = {0x1: 0xEFC, 0x9: 0x7FC}[rom_class]
    for n in range(max_entries):
        off = n * step
        if off > limit:
            break
        e = decode_romentry(read32(base + off), base, rom_class)
        out.append(e)
        if e.kind == "end":
            break
    return out


# ---------------------------------------------------------------------------
# 3. Authentication (spec C5.4, B2.3.1)
# ---------------------------------------------------------------------------

def auth_permissions(dbgen: int, niden: int, spiden: int = 0, spniden: int = 0,
                     hiden: int = 0, hniden: int = 0) -> Dict:
    """Tables C5-2..C5-4 plus the AUTHSTATUS encoding for a component that supports all levels."""
    D, N, S, SN, H, HN = (int(bool(x)) for x in (dbgen, niden, spiden, spniden, hiden, hniden))
    perm = {
        "NS_invasive": D,
        "NS_noninvasive": D | N,
        "S_invasive": D & S,
        "S_noninvasive": (S | SN) & (D | N),
        "H_invasive": D & H,
        "H_noninvasive": (H | HN) & (D | N),
    }
    # AUTHSTATUS field: 0b10 = supported and disabled, 0b11 = supported and enabled
    shifts = {"NS_invasive": 0, "NS_noninvasive": 2, "S_invasive": 4, "S_noninvasive": 6,
              "H_invasive": 8, "H_noninvasive": 10}
    authstatus = 0
    for k, sh in shifts.items():
        authstatus |= (0b11 if perm[k] else 0b10) << sh

    warnings = []
    if D and not N:   warnings.append("rule 4: NIDEN low with DBGEN high (not recommended)")
    if S and not SN:  warnings.append("rule 7: SPNIDEN low with SPIDEN high (not recommended)")
    if S and not D:   warnings.append("rule 8: SPIDEN high with DBGEN low (not recommended)")
    if SN and not N:  warnings.append("rule 9: SPNIDEN high with NIDEN low (not recommended)")
    if H and not HN:  warnings.append("rule 12: HNIDEN low with HIDEN high (not recommended)")
    if H and not D:   warnings.append("rule 15: HIDEN high with DBGEN low (not recommended)")
    if HN and not N:  warnings.append("rule 16: HNIDEN high with NIDEN low (not recommended)")
    return {"perm": perm, "authstatus": authstatus, "warnings": warnings}


# ---------------------------------------------------------------------------
# 4. Trace formatter (spec D4.2)
# ---------------------------------------------------------------------------

SPECIAL_IDS = {0x00: "null", 0x7B: "flush response", 0x7D: "trigger", 0x7F: "illegal (sync clash)"}
FRAME_SYNC = bytes([0xFF, 0xFF, 0xFF, 0x7F])     # 0x7FFFFFFF, LSB first
HALFWORD_SYNC = bytes([0xFF, 0x7F])              # 0x7FFF


def id_kind(i: int) -> str:
    if i in SPECIAL_IDS:
        return SPECIAL_IDS[i]
    if 0x70 <= i <= 0x7E:
        return "reserved"
    return "source"


def decode_frame(frame: bytes, current_id: Optional[int] = None):
    """
    Decode one 16-byte formatter frame.
    Returns (list of (id, byte) data pairs, id at end of frame, id_for_next_frame).
    """
    if len(frame) != 16:
        raise ValueError("a formatter frame is exactly 16 bytes")
    aux = frame[15]
    out: List[Tuple[Optional[int], int]] = []
    cur = current_id
    pending: Optional[int] = None
    next_frame_id: Optional[int] = None
    for i in range(15):
        b = frame[i]
        if i % 2 == 0:                       # mixed byte: ID or data
            auxbit = (aux >> (i // 2)) & 1
            if b & 1:                        # F = 1 -> new ID in bits[7:1]
                nid = b >> 1
                if i == 14:
                    next_frame_id = nid      # takes effect from next frame
                elif auxbit == 0:
                    cur = nid                # next byte uses the new ID
                else:
                    pending = nid            # next byte still belongs to old ID
            else:
                out.append((cur, (b & 0xFE) | auxbit))
        else:                                # odd byte: always data
            out.append((cur, b))
            if pending is not None:
                cur, pending = pending, None
    return out, cur, next_frame_id


def decode_stream(data: bytes, start_id: Optional[int] = None) -> Dict[int, bytes]:
    """Decode back-to-back frames (sync already stripped) into per-source byte streams."""
    streams: Dict[int, bytearray] = {}
    cur = start_id
    for k in range(0, len(data) - len(data) % 16, 16):
        pairs, cur, nxt = decode_frame(data[k:k + 16], cur)
        for sid, byte in pairs:
            if sid is not None and id_kind(sid) == "source":
                streams.setdefault(sid, bytearray()).append(byte)
        if nxt is not None:
            cur = nxt
    return {k: bytes(v) for k, v in streams.items()}


def encode_frames(items: List[Tuple[int, int]], current_id: Optional[int] = None) -> bytes:
    """
    Reference formatter: items is a list of (source_id, byte) in ATB arrival order.
    Uses immediate ID changes (aux=0) where possible and the delayed form (aux=1)
    when a switch would otherwise land on an odd (data-only) byte. The last frame
    is padded with the null ID 0x00 (spec D4.4.2). Use it to generate stimulus or
    to predict what a sink should contain.
    """
    q = list(items)
    cur = current_id
    out = bytearray()
    while q:
        frame = [0] * 16
        aux = 0
        pending = None
        for i in range(15):
            even = i % 2 == 0
            if not q:                                   # padding
                if even and i < 14 and cur != 0x00:
                    frame[i] = 0x01                     # ID 0x00, immediate
                    cur = 0x00
                continue
            sid, byte = q[0]
            if even:
                if sid != cur:
                    frame[i] = (sid << 1) | 1           # new ID
                    if i == 14:
                        cur = sid                       # effective from next frame
                    else:
                        cur = sid                       # aux=0: immediate
                elif i < 14 and (q[1][0] if len(q) > 1 else 0x00) != cur:
                    nxt = q[1][0] if len(q) > 1 else 0x00   # end of data -> null ID
                    frame[i] = (nxt << 1) | 1           # delayed switch, aux=1
                    aux |= 1 << (i // 2)
                    pending = nxt
                else:
                    q.pop(0)
                    frame[i] = byte & 0xFE
                    aux |= (byte & 1) << (i // 2)
            else:
                q.pop(0)                                # odd slot: data for cur
                frame[i] = byte
                if pending is not None:
                    cur, pending = pending, None
        frame[15] = aux
        out += bytes(frame)
    return bytes(out)


# ---------------------------------------------------------------------------
# Self tests
# ---------------------------------------------------------------------------

def _selftest() -> None:
    # Spec Table D4-2 worked example (IDs 0x03 and 0x15)
    ex = bytes([0x07, 0xAA, 0xA6, 0xA7, 0x2B, 0xA8, 0x54, 0x52,
                0x52, 0x54, 0x07, 0xCA, 0xC6, 0xC7, 0xC8, 0x1C])
    pairs, end_id, _ = decode_frame(ex)
    s3 = [b for i, b in pairs if i == 0x03]
    s15 = [b for i, b in pairs if i == 0x15]
    assert s3 == [0xAA, 0xA6, 0xA7, 0xA8, 0xCA, 0xC6, 0xC7, 0xC8], s3
    assert s15 == [0x55, 0x52, 0x53, 0x54], s15
    assert end_id == 0x03

    # Round trip: encoder -> decoder
    import random
    rnd = random.Random(1)
    items = [(rnd.choice([0x10, 0x11, 0x22]), rnd.randrange(256)) for _ in range(500)]
    enc = encode_frames(items)
    got = decode_stream(enc)
    for sid in {s for s, _ in items}:
        assert got[sid] == bytes(b for s, b in items if s == sid), f"round-trip mismatch on ID {sid:#x}"

    # ROM entry: spec Figure D6-1 example 0x00003017
    e = decode_romentry(0x00003017, 0x8000_0000, 0x1)
    assert e.kind == "present" and e.address == 0x8000_3000 and e.power_id == 1
    e = decode_romentry(0xFFFF0003, 0x8000_0000, 0x9)
    assert e.offset_4kb == -16 and e.address == 0x7FFF_0000
    assert decode_romentry(0, 0, 0x9).kind == "end"
    assert decode_romentry(0x00000002, 0, 0x9).kind == "skip"
    assert decode_romentry(0x00000003, 0, 0x9).errors  # offset 0 while present

    # Auth: example -> AUTHSTATUS 0xAEF
    a = auth_permissions(dbgen=1, niden=1, spiden=0, spniden=1)
    assert a["authstatus"] == 0xAEF and a["perm"]["S_noninvasive"] == 1 and a["perm"]["S_invasive"] == 0
    assert auth_permissions(0, 0, 1, 1)["perm"]["S_noninvasive"] == 0   # secure needs NS enable

    # IDs: illustrative ARM CTI
    c = decode_ids([0x0D, 0x90, 0x05, 0xB1], [0x06, 0xB9, 0x4B, 0x00, 0x04], 0x47701A14, 0x14)
    assert c.preamble_ok and c.cls == 0x9 and c.part == 0x906 and c.is_arm
    assert c.devarch["arch_name"] == "CTI" and c.devtype == ("Debug control", "Trigger matrix (ECT)")
    print("All CoreSight self-tests passed.")


if __name__ == "__main__":
    _selftest()
