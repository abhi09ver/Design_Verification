"""Tagged, LRU translation cache (TLB) with architectural-style invalidation scopes.

Tag = (stream_world, vmid, asid-or-global, va page base, page size).
Entries are NOT tagged by StreamID: two streams sharing a CD/ASID share entries.
"""
from collections import OrderedDict
from dataclasses import dataclass
from typing import Optional, Tuple


@dataclass(frozen=True)
class TlbEntry:
    stream_world: str
    vmid: int
    asid: Optional[int]  # None = global (nG == 0)
    va_base: int
    size: int
    pa_base: int
    writable: bool
    el0: bool = True
    xn: bool = False


class Tlb:
    def __init__(self, capacity: int = 4) -> None:
        self.capacity = capacity
        self.entries: "OrderedDict[Tuple, TlbEntry]" = OrderedDict()
        self.hits = 0
        self.misses = 0

    @staticmethod
    def _key(e: TlbEntry) -> Tuple:
        return (e.stream_world, e.vmid, e.asid, e.va_base, e.size)

    def lookup(self, stream_world: str, vmid: int, asid: int, va: int) -> Optional[TlbEntry]:
        for key, e in self.entries.items():
            if (e.stream_world == stream_world and e.vmid == vmid
                    and (e.asid is None or e.asid == asid)
                    and e.va_base <= va < e.va_base + e.size):
                self.entries.move_to_end(key)  # LRU: most recently used at the end
                self.hits += 1
                return e
        self.misses += 1
        return None

    def fill(self, e: TlbEntry) -> None:
        k = self._key(e)
        if k in self.entries:
            self.entries.move_to_end(k)
        elif len(self.entries) >= self.capacity:
            self.entries.popitem(last=False)  # evict least recently used
        self.entries[k] = e

    # ---- invalidation scopes (mirroring CMD_TLBI_*) ----
    def _drop(self, pred) -> int:
        doomed = [k for k, e in self.entries.items() if pred(e)]
        for k in doomed:
            del self.entries[k]
        return len(doomed)

    def inv_all(self) -> int:
        return self._drop(lambda e: True)

    def inv_vmid(self, vmid: int) -> int:                       # ~ CMD_TLBI_S12_VMALL
        return self._drop(lambda e: e.vmid == vmid)

    def inv_asid(self, vmid: int, asid: int) -> int:            # ~ CMD_TLBI_NH_ASID
        return self._drop(lambda e: e.vmid == vmid and e.asid == asid)

    def inv_va(self, vmid: int, asid: Optional[int], va: int) -> int:  # ~ CMD_TLBI_NH_VA
        """Hits non-global entries for `asid` and global entries covering `va`."""
        return self._drop(lambda e: e.vmid == vmid
                          and (e.asid is None or asid is None or e.asid == asid)
                          and e.va_base <= va < e.va_base + e.size)
