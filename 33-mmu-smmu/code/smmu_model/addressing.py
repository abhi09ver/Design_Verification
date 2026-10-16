"""Address slicing helpers for VMSAv8-64 style translation tables.

Interview use: "Given a VA, a granule and a VA size, which bits index each level?"
"""
from dataclasses import dataclass
from typing import List

GRANULE_BITS = {"4K": 12, "16K": 14, "64K": 16}


@dataclass(frozen=True)
class LevelSlice:
    level: int  # architectural level number (-1..3); the last level is always 3
    hi: int     # highest VA bit used by this level
    lo: int     # lowest VA bit used by this level
    index: int  # value of VA[hi:lo] = entry number in that level's table


def bits_per_level(granule_bits: int) -> int:
    """Each table is one granule of 8-byte descriptors: 2**(g-3) entries."""
    return granule_bits - 3


def num_levels(granule_bits: int, va_bits: int) -> int:
    per = bits_per_level(granule_bits)
    return -(-(va_bits - granule_bits) // per)  # ceil division


def start_level(granule_bits: int, va_bits: int) -> int:
    return 4 - num_levels(granule_bits, va_bits)


def slice_va(va: int, granule_bits: int = 12, va_bits: int = 48) -> List[LevelSlice]:
    """Split a VA into per-level table indices (top level first)."""
    per = bits_per_level(granule_bits)
    out = []
    hi = va_bits - 1
    for level in range(start_level(granule_bits, va_bits), 4):
        lo = granule_bits + per * (3 - level)
        width = hi - lo + 1
        out.append(LevelSlice(level, hi, lo, (va >> lo) & ((1 << width) - 1)))
        hi = lo - 1
    return out


def page_offset(va: int, granule_bits: int = 12) -> int:
    return va & ((1 << granule_bits) - 1)


def block_size_at_level(level: int, granule_bits: int = 12) -> int:
    """Bytes mapped by one entry at `level` (e.g. 4K granule: L1=1GB, L2=2MB, L3=4KB)."""
    return 1 << (granule_bits + bits_per_level(granule_bits) * (3 - level))


def nested_walk_cost(s1_levels: int, s2_levels: int) -> int:
    """Memory reads for a cold two-stage walk: (n+1)(m+1) - 1.

    Each of the n stage-1 descriptor addresses, and the final output IPA, is an IPA
    that needs an m-level stage-2 walk. Adds the n stage-1 reads themselves.
    With stage 2 bypassed (m=0) this collapses to n.
    """
    return (s1_levels + 1) * (s2_levels + 1) - 1


if __name__ == "__main__":
    va = 0x0000_7F12_3456_7ABC
    for g in ("4K", "16K", "64K"):
        gb = GRANULE_BITS[g]
        parts = ", ".join(f"L{s.level}[{s.hi}:{s.lo}]={s.index}" for s in slice_va(va, gb))
        print(f"{g:>3}: {parts}, offset=0x{page_offset(va, gb):x}")
    print("nested 4x4 walk cost =", nested_walk_cost(4, 4))
