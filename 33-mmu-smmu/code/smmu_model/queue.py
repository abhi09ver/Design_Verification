"""SMMUv3-style circular queue with a wrap bit.

Index register layout: {WRAP, IDX[log2size-1:0]}.
  empty: PROD == CONS (index and wrap equal)
  full:  index equal, wrap bits differ
This lets all 2**log2size slots be used (no "one slot wasted" rule).
"""
from typing import Generic, List, Optional, TypeVar

T = TypeVar("T")


class SmmuQueue(Generic[T]):
    def __init__(self, log2size: int) -> None:
        self.log2size = log2size
        self.size = 1 << log2size
        self.slots: List[Optional[T]] = [None] * self.size
        self.prod = 0  # includes wrap bit at position log2size
        self.cons = 0
        self.overflow_flag = 0   # PROD.OVFLG (toggles on each new overflow episode)
        self.overflow_ack = 0    # CONS.OVACKFLG (software copies OVFLG here)

    def _idx(self, ptr: int) -> int:
        return ptr & (self.size - 1)

    def _wrap(self, ptr: int) -> int:
        return (ptr >> self.log2size) & 1

    def _inc(self, ptr: int) -> int:
        return (ptr + 1) & ((self.size << 1) - 1)

    def is_empty(self) -> bool:
        return self.prod == self.cons

    def is_full(self) -> bool:
        return (self._idx(self.prod) == self._idx(self.cons)
                and self._wrap(self.prod) != self._wrap(self.cons))

    def count(self) -> int:
        return (self.prod - self.cons) & ((self.size << 1) - 1)

    def push(self, item: T) -> bool:
        """Producer side. Returns False (and flags overflow) when full."""
        if self.is_full():
            if self.overflow_flag == self.overflow_ack:
                self.overflow_flag ^= 1  # first drop since last ack starts a new episode
            return False
        self.slots[self._idx(self.prod)] = item
        self.prod = self._inc(self.prod)
        return True

    def pop(self) -> Optional[T]:
        if self.is_empty():
            return None
        item = self.slots[self._idx(self.cons)]
        self.cons = self._inc(self.cons)
        return item

    def ack_overflow(self) -> None:
        self.overflow_ack = self.overflow_flag
