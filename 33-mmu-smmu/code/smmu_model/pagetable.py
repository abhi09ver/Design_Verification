"""A small VMSAv8-64 (4KB granule, 48-bit) page-table builder and walker.

Simplified but structurally faithful:
  * 4 levels (L0..L3), 512 entries x 8 bytes per table.
  * Descriptor bit 0 = valid, bit 1 = table (L0-L2) / page (L3). Bit 1 == 0 at L1/L2 = block.
  * AP[2] (bit 7) = read-only, AP[1] (bit 6) = unprivileged (EL0) access allowed.
  * AF (bit 10) = access flag, UXN/XN (bit 54) = execute-never.
  * Output address = bits [47:12].

Faults are returned (not raised) so a scoreboard can compare them like any other result.
"""
from dataclasses import dataclass, field
from enum import Enum
from typing import Callable, Dict, List, Optional

from .addressing import block_size_at_level, slice_va

GRANULE = 12
ENTRY_BYTES = 8
OA_MASK = ((1 << 48) - 1) & ~((1 << GRANULE) - 1)

VALID = 1 << 0
TABLE_OR_PAGE = 1 << 1
AP_EL0 = 1 << 6
AP_RO = 1 << 7
AF = 1 << 10
XN = 1 << 54


class FaultType(Enum):
    TRANSLATION = "F_TRANSLATION"
    ADDR_SIZE = "F_ADDR_SIZE"
    ACCESS = "F_ACCESS"
    PERMISSION = "F_PERMISSION"
    WALK_EABT = "F_WALK_EABT"


@dataclass(frozen=True)
class Access:
    write: bool = False
    exec: bool = False
    priv: bool = True  # privileged (EL1) vs unprivileged (EL0)


@dataclass
class Fault:
    type: FaultType
    level: int
    stage: int = 1
    ipa: Optional[int] = None  # for stage-2 faults
    on_table_fetch: bool = False  # S2 fault while fetching an S1 table (CLASS = TT)


@dataclass
class Translation:
    out_addr: int
    level: int
    size: int
    writable: bool
    el0: bool
    xn: bool


class Memory:
    """Sparse 64-bit word memory. `reads` counts accesses so tests can check walk cost."""

    def __init__(self) -> None:
        self.words: Dict[int, int] = {}
        self.reads = 0
        self.abort_addrs = set()  # addresses that return an external abort

    def read64(self, addr: int) -> Optional[int]:
        self.reads += 1
        if addr in self.abort_addrs:
            return None
        return self.words.get(addr, 0)

    def write64(self, addr: int, value: int) -> None:
        self.words[addr] = value


class PageTableBuilder:
    """Allocates tables from a simple bump allocator and writes descriptors."""

    def __init__(self, mem: Memory, alloc_base: int = 0x8000_0000) -> None:
        self.mem = mem
        self.next_table = alloc_base
        self.root = self._new_table()

    def _new_table(self) -> int:
        base = self.next_table
        self.next_table += 1 << GRANULE
        return base

    def map(self, va: int, pa: int, size: int = 4096, *, writable: bool = True,
            el0: bool = True, xn: bool = False, af: bool = True) -> None:
        level = {4096: 3, 2 << 20: 2, 1 << 30: 1}[size]
        assert va % size == 0 and pa % size == 0, "VA and PA must be size-aligned"
        table = self.root
        for s in slice_va(va, GRANULE, 48):
            entry_addr = table + s.index * ENTRY_BYTES
            if s.level == level:
                desc = VALID | (pa & OA_MASK)
                if level == 3:
                    desc |= TABLE_OR_PAGE
                desc |= (0 if writable else AP_RO) | (AP_EL0 if el0 else 0)
                desc |= (AF if af else 0) | (XN if xn else 0)
                self.mem.write64(entry_addr, desc)
                return
            desc = self.mem.words.get(entry_addr, 0)
            if not desc & VALID:
                nxt = self._new_table()
                self.mem.write64(entry_addr, VALID | TABLE_OR_PAGE | nxt)
                table = nxt
            else:
                assert desc & TABLE_OR_PAGE, "cannot split an existing block in this model"
                table = desc & OA_MASK

    def unmap(self, va: int) -> None:
        """Clear the leaf descriptor that maps `va` (does NOT touch any TLB)."""
        table = self.root
        for s in slice_va(va, GRANULE, 48):
            entry_addr = table + s.index * ENTRY_BYTES
            desc = self.mem.words.get(entry_addr, 0)
            if not desc & VALID:
                return
            if s.level == 3 or not desc & TABLE_OR_PAGE:
                self.mem.write64(entry_addr, 0)
                return
            table = desc & OA_MASK


def walk(mem: Memory, ttb: int, va: int, access: Access = Access(), *,
         stage: int = 1, oas_bits: int = 48,
         table_addr_xlate: Optional[Callable[[int], object]] = None,
         trace: Optional[List[int]] = None):
    """Walk one stage. Returns Translation or Fault.

    `table_addr_xlate`, if given, maps each table address (an IPA in a nested walk)
    to a PA, or returns a Fault (that becomes a stage-2 fault on table fetch).
    """
    if va >> 48:
        return Fault(FaultType.TRANSLATION, level=0, stage=stage)
    table = ttb
    for s in slice_va(va, GRANULE, 48):
        entry_addr = table + s.index * ENTRY_BYTES
        if table_addr_xlate is not None:
            r = table_addr_xlate(entry_addr)
            if isinstance(r, Fault):
                r.on_table_fetch = True
                return r
            entry_addr = r
        if trace is not None:
            trace.append(entry_addr)
        desc = mem.read64(entry_addr)
        if desc is None:
            return Fault(FaultType.WALK_EABT, s.level, stage)
        if not desc & VALID:
            return Fault(FaultType.TRANSLATION, s.level, stage)
        is_leaf = s.level == 3 or not desc & TABLE_OR_PAGE
        if s.level == 3 and not desc & TABLE_OR_PAGE:
            return Fault(FaultType.TRANSLATION, s.level, stage)  # reserved encoding
        if s.level == 0 and not desc & TABLE_OR_PAGE:
            return Fault(FaultType.TRANSLATION, s.level, stage)  # no L0 blocks for 4K
        if not is_leaf:
            table = desc & OA_MASK
            continue
        size = block_size_at_level(s.level, GRANULE)
        out = (desc & OA_MASK & ~(size - 1)) | (va & (size - 1))
        if out >> oas_bits:
            return Fault(FaultType.ADDR_SIZE, s.level, stage)
        if not desc & AF:
            return Fault(FaultType.ACCESS, s.level, stage)
        t = Translation(out, s.level, size, writable=not desc & AP_RO,
                        el0=bool(desc & AP_EL0), xn=bool(desc & XN))
        if access.write and not t.writable:
            return Fault(FaultType.PERMISSION, s.level, stage)
        if not access.priv and not t.el0:
            return Fault(FaultType.PERMISSION, s.level, stage)
        if access.exec and t.xn:
            return Fault(FaultType.PERMISSION, s.level, stage)
        return t
    raise AssertionError("unreachable")
