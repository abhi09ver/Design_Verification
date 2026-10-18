"""
gic_ref_model.py - a small, readable GICv3 reference model for learning and interviews.

What it models (enough to reason about the interview questions):
  * Per-interrupt state machine: inactive / pending / active / active_pending
  * Edge vs level triggering, including "level still high at acknowledge"
  * LPIs: no active state (acknowledge clears pending)
  * CPU interface: PMR, binary point (group priority), active-priority stack,
    running priority, IAR / EOIR / DIR, EOImode split, spurious 1023
  * Group enables and the IRQ/FIQ signalling rule (groups vs Security state)
  * SPI routing: direct target or 1-of-N (IRM=1) over participating PEs
  * Redistributor sleep (GICR_WAKER) -> wake request instead of IRQ
  * A tiny ITS: MAPD / MAPC / MAPTI / MAPI / MOVI / INT / CLEAR / DISCARD / SYNC,
    plus MSI translation (DeviceID, EventID) -> LPI on the right PE

What it deliberately leaves out: real register encodings, Non-secure priority
shifting, virtualization (list registers / GICv4), caching behaviour, timing.
It applies every change instantly, so it predicts ONE legal outcome. A real
scoreboard must allow the set of outcomes the spec permits (see the cheat sheet).

Reference: Arm IHI 0069H.b, GIC Architecture Specification (GICv3.3 / GICv4.2).
Pure Python 3, no dependencies. Run the tests with:  python3 -m unittest -v
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, List, Optional, Tuple

SPURIOUS = 1023


class State(str, Enum):
    INACTIVE = "inactive"
    PENDING = "pending"
    ACTIVE = "active"
    ACTIVE_PENDING = "active_pending"


class Group(str, Enum):
    G0 = "G0"        # always FIQ, owned by EL3
    G1S = "G1S"      # Secure Group 1
    G1NS = "G1NS"    # Non-secure Group 1


def intid_type(intid: int) -> str:
    """Classify an INTID using the ranges from the spec (Table 2-1)."""
    if 0 <= intid <= 15:
        return "SGI"
    if 16 <= intid <= 31 or 1056 <= intid <= 1119:
        return "PPI"
    if 32 <= intid <= 1019 or 4096 <= intid <= 5119:
        return "SPI"
    if 1020 <= intid <= 1023:
        return "SPECIAL"
    if intid >= 8192:
        return "LPI"
    return "RESERVED"


def signal_kind(group: Group, pe_secure: bool, at_el3: bool) -> str:
    """IRQ or FIQ? An interrupt for the world the PE is in now is IRQ;
    Group 0, anything at EL3, or another world's Group 1 is FIQ."""
    if group == Group.G0 or at_el3:
        return "FIQ"
    if group == Group.G1S:
        return "IRQ" if pe_secure else "FIQ"
    return "FIQ" if pe_secure else "IRQ"


@dataclass
class Interrupt:
    intid: int
    priority: int = 0xA0
    group: Group = Group.G1NS
    enabled: bool = True
    edge: bool = True               # False = level-sensitive
    state: State = State.INACTIVE
    line_high: bool = False         # level-sensitive input level

    @property
    def is_lpi(self) -> bool:
        return intid_type(self.intid) == "LPI"

    # ---- inputs -------------------------------------------------------
    def edge_pulse(self) -> None:
        if self.state == State.INACTIVE:
            self.state = State.PENDING
        elif self.state == State.ACTIVE and not self.is_lpi:
            self.state = State.ACTIVE_PENDING
        # PENDING or ACTIVE_PENDING: a second edge merges into the first

    def set_level(self, high: bool) -> None:
        self.line_high = high
        if high:
            if self.state == State.INACTIVE:
                self.state = State.PENDING
            elif self.state == State.ACTIVE:
                self.state = State.ACTIVE_PENDING
        else:
            if self.state == State.PENDING:
                self.state = State.INACTIVE
            elif self.state == State.ACTIVE_PENDING:
                self.state = State.ACTIVE


@dataclass
class CpuInterface:
    """One PE's CPU interface plus the Redistributor-side ranking for that PE."""
    pe: int
    pmr: int = 0xFF
    bpr: int = 2                    # BPR0-style: group priority = prio[7:bpr+1]
    eoimode: int = 0
    igrpen: Dict[Group, bool] = field(default_factory=lambda: {g: True for g in Group})
    secure: bool = False
    at_el3: bool = False
    asleep: bool = False            # GICR_WAKER.ProcessorSleep handshake done
    private: Dict[int, Interrupt] = field(default_factory=dict)   # SGI, PPI, LPI
    active_stack: List[Tuple[int, int]] = field(default_factory=list)  # (group_prio, intid)
    wake_request: bool = False
    errors: List[str] = field(default_factory=list)

    def group_priority(self, prio: int) -> int:
        mask = (0xFF << (self.bpr + 1)) & 0xFF
        return prio & mask

    @property
    def running_priority(self) -> int:
        return min((gp for gp, _ in self.active_stack), default=0xFF)


class Gic:
    """Distributor + Redistributors + CPU interfaces + a tiny ITS."""

    def __init__(self, num_pes: int = 2, enable_grp: Optional[Dict[Group, bool]] = None):
        self.pes = [CpuInterface(pe=i) for i in range(num_pes)]
        self.spis: Dict[int, Interrupt] = {}
        self.route: Dict[int, Tuple[int, int]] = {}      # intid -> (irm, target_pe)
        self.spi_owner: Dict[int, int] = {}              # PE that acknowledged an SPI
        self.dist_grp_en = enable_grp or {g: True for g in Group}
        self.its = Its(self)
        self._rr = 0                                      # round-robin for 1-of-N

    # ---- configuration -------------------------------------------------
    def add_spi(self, intid: int, target_pe: int = 0, irm: int = 0, **kw) -> Interrupt:
        assert intid_type(intid) == "SPI", intid
        irq = Interrupt(intid, **kw)
        self.spis[intid] = irq
        self.route[intid] = (irm, target_pe)
        return irq

    def add_private(self, pe: int, intid: int, **kw) -> Interrupt:
        assert intid_type(intid) in ("SGI", "PPI", "LPI"), intid
        irq = Interrupt(intid, **kw)
        self.pes[pe].private[intid] = irq
        return irq

    def lookup(self, pe: int, intid: int) -> Optional[Interrupt]:
        return self.pes[pe].private.get(intid) or self.spis.get(intid)

    # ---- routing --------------------------------------------------------
    def _participates(self, cpu: CpuInterface, grp: Group) -> bool:
        return cpu.igrpen[grp] and not cpu.asleep

    def spi_target(self, intid: int) -> Optional[int]:
        """Return the PE an SPI is currently offered to, or None."""
        if intid in self.spi_owner:
            return self.spi_owner[intid]
        irm, tgt = self.route[intid]
        if irm == 0:
            return tgt
        grp = self.spis[intid].group
        cands = [c.pe for c in self.pes if self._participates(c, grp)]
        if not cands:
            return None
        return cands[self._rr % len(cands)]   # IMPLEMENTATION DEFINED choice

    def send_sgi(self, sender: int, intid: int, targets: Optional[List[int]] = None,
                 irm: int = 0) -> None:
        """ICC_SGI1R_EL1-style SGI. irm=1 -> everyone except the sender."""
        assert intid_type(intid) == "SGI"
        dests = [p.pe for p in self.pes if p.pe != sender] if irm else (targets or [])
        for d in dests:
            irq = self.pes[d].private.get(intid) or self.add_private(d, intid)
            irq.edge_pulse()

    # ---- ranking + signalling --------------------------------------------
    def _candidates(self, cpu: CpuInterface) -> List[Interrupt]:
        out = [i for i in cpu.private.values()]
        out += [i for n, i in self.spis.items() if self.spi_target(n) == cpu.pe]
        return [i for i in out
                if i.state == State.PENDING and i.enabled
                and self.dist_grp_en[i.group] and cpu.igrpen[i.group]]

    def hppi(self, pe: int) -> Optional[Interrupt]:
        cands = self._candidates(self.pes[pe])
        # lowest priority value wins; tie -> lowest INTID (IMPLEMENTATION DEFINED)
        return min(cands, key=lambda i: (i.priority, i.intid), default=None)

    def can_signal(self, pe: int) -> Optional[Interrupt]:
        cpu, best = self.pes[pe], self.hppi(pe)
        if best is None:
            return None
        if not (best.priority < cpu.pmr):
            return None
        if not (cpu.group_priority(best.priority) < cpu.running_priority):
            return None
        return best

    def irq_lines(self, pe: int) -> Dict[str, bool]:
        """What the PE sees: IRQ/FIQ, or a wake request if the RD is asleep."""
        cpu, best = self.pes[pe], self.can_signal(pe)
        lines = {"IRQ": False, "FIQ": False}
        if best is None:
            return lines
        if cpu.asleep:
            cpu.wake_request = True
            return lines
        lines[signal_kind(best.group, cpu.secure, cpu.at_el3)] = True
        return lines

    # ---- software interface ----------------------------------------------
    def read_iar(self, pe: int, grp1: bool = True) -> int:
        """ICC_IAR1_EL1 (grp1=True) or ICC_IAR0_EL1. Returns INTID or 1023."""
        cpu, best = self.pes[pe], self.can_signal(pe)
        if best is None or (best.group == Group.G0) == grp1:
            return SPURIOUS
        if best.is_lpi:
            best.state = State.INACTIVE              # LPIs have no active state
        elif not best.edge and best.line_high:
            best.state = State.ACTIVE_PENDING        # level still asserted
        else:
            best.state = State.ACTIVE
        if best.intid in self.spis:
            self.spi_owner[best.intid] = pe
            self._rr += 1
        cpu.active_stack.append((cpu.group_priority(best.priority), best.intid))
        return best.intid

    def write_eoir(self, pe: int, intid: int) -> None:
        """Priority drop (+ deactivate when EOImode == 0)."""
        cpu = self.pes[pe]
        if not cpu.active_stack:
            cpu.errors.append(f"EOIR {intid} with no active priority")
            return
        top = cpu.active_stack[-1][1]
        if top != intid:
            # Spec: UNPREDICTABLE. The model records it and drops nothing.
            cpu.errors.append(f"EOIR {intid} out of order (expected {top})")
            return
        cpu.active_stack.pop()
        if cpu.eoimode == 0:
            self._deactivate(pe, intid)

    def write_dir(self, pe: int, intid: int) -> None:
        """ICC_DIR_EL1: deactivate only, any order. No effect for LPIs."""
        if self.pes[pe].eoimode == 1 and intid_type(intid) != "LPI":
            self._deactivate(pe, intid)

    def _deactivate(self, pe: int, intid: int) -> None:
        irq = self.lookup(pe, intid)
        if irq is None or irq.is_lpi:
            return
        if irq.state == State.ACTIVE:
            irq.state = State.INACTIVE
        elif irq.state == State.ACTIVE_PENDING:
            irq.state = State.PENDING
        self.spi_owner.pop(intid, None)

    # ---- power -----------------------------------------------------------
    def set_processor_sleep(self, pe: int, sleep: bool) -> None:
        """GICR_WAKER.ProcessorSleep; the model sets ChildrenAsleep instantly."""
        cpu = self.pes[pe]
        cpu.asleep = sleep
        if not sleep:
            cpu.wake_request = False


class Its:
    """Minimal ITS: tables as dicts, commands executed in order."""

    def __init__(self, gic: Gic):
        self.gic = gic
        self.device_table: Dict[int, int] = {}                     # DeviceID -> ITT size (events)
        self.itt: Dict[Tuple[int, int], Tuple[int, int]] = {}      # (Dev, Ev) -> (pINTID, ICID)
        self.collections: Dict[int, int] = {}                      # ICID -> PE
        self.errors: List[str] = []

    def _err(self, msg: str) -> bool:
        self.errors.append(msg)
        return False

    # commands --------------------------------------------------------------
    def mapd(self, dev: int, size: int, valid: bool = True) -> None:
        if valid:
            self.device_table[dev] = size
        else:
            self.device_table.pop(dev, None)
            for key in [k for k in self.itt if k[0] == dev]:
                del self.itt[key]

    def mapc(self, icid: int, pe: int, valid: bool = True) -> None:
        if valid:
            self.collections[icid] = pe
        else:
            self.collections.pop(icid, None)

    def mapti(self, dev: int, ev: int, intid: int, icid: int, priority: int = 0xA0) -> bool:
        if dev not in self.device_table:
            return self._err(f"MAPTI: DeviceID {dev} not mapped")
        if ev >= self.device_table[dev]:
            return self._err(f"MAPTI: EventID {ev} out of range")
        if intid_type(intid) != "LPI":
            return self._err(f"MAPTI: {intid} is not an LPI")
        self.itt[(dev, ev)] = (intid, icid)
        # configuration lives in the LPI Configuration table; the model keeps it per PE
        for cpu in self.gic.pes:
            if intid not in cpu.private:
                cpu.private[intid] = Interrupt(intid, priority=priority, edge=True)
        return True

    def mapi(self, dev: int, ev: int, icid: int, **kw) -> bool:
        return self.mapti(dev, ev, ev, icid, **kw)    # pINTID = EventID

    def _resolve(self, dev: int, ev: int) -> Optional[Tuple[int, int]]:
        if dev not in self.device_table:
            self._err(f"DeviceID {dev} not mapped")
            return None
        entry = self.itt.get((dev, ev))
        if entry is None:
            self._err(f"EventID {ev} not mapped for DeviceID {dev}")
            return None
        intid, icid = entry
        if icid not in self.collections:
            self._err(f"ICID {icid} not mapped")
            return None
        return intid, self.collections[icid]

    def translate(self, dev: int, ev: int) -> bool:
        """A device write to GITS_TRANSLATER (or the INT command)."""
        hit = self._resolve(dev, ev)
        if hit is None:
            return False
        intid, pe = hit
        self.gic.pes[pe].private[intid].edge_pulse()
        return True

    int_cmd = translate

    def clear(self, dev: int, ev: int) -> None:
        hit = self._resolve(dev, ev)
        if hit:
            intid, pe = hit
            self.gic.pes[pe].private[intid].state = State.INACTIVE

    def discard(self, dev: int, ev: int) -> None:
        self.clear(dev, ev)
        self.itt.pop((dev, ev), None)

    def movi(self, dev: int, ev: int, new_icid: int) -> bool:
        """Retarget one LPI. A pending instance moves with it: never lost, never doubled."""
        hit = self._resolve(dev, ev)
        if hit is None or new_icid not in self.collections:
            return self._err("MOVI: bad mapping")
        intid, old_pe = hit
        new_pe = self.collections[new_icid]
        old = self.gic.pes[old_pe].private[intid]
        new = self.gic.pes[new_pe].private[intid]
        if old.state == State.PENDING and old_pe != new_pe:
            old.state, new.state = State.INACTIVE, State.PENDING
        self.itt[(dev, ev)] = (intid, new_icid)
        return True

    def sync(self, pe: int) -> None:
        """Effects are applied immediately in this model, so SYNC is a no-op."""
        return None
