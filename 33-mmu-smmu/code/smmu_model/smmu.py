"""A teaching reference model of an SMMUv3.

Covers the parts interviewers ask about:
  StreamID -> STE -> (SubstreamID) -> CD -> stage 1 walk -> stage 2 walk -> PA
  config cache + TLB that must be invalidated by commands
  Command queue (CFGI / TLBI / SYNC / RESUME), Event queue, stall vs terminate
  SMMUEN = 0 global bypass (GBPA)

It is deliberately small. Encodings are names, not bit-accurate formats.
"""
import copy
from dataclasses import dataclass, field
from typing import Dict, List, Optional

from .pagetable import Access, Fault, FaultType, Memory, Translation, walk
from .queue import SmmuQueue
from .tlb import Tlb, TlbEntry

# STE.Config values (spec encodings in comments)
ABORT, BYPASS, S1_ONLY, S2_ONLY, NESTED = "abort", "bypass", "s1", "s2", "s12"
CONFIG_ENCODING = {ABORT: 0b000, BYPASS: 0b100, S1_ONLY: 0b101, S2_ONLY: 0b110, NESTED: 0b111}


@dataclass
class CD:
    """Context Descriptor (stage-1 context, one per SubstreamID)."""
    ttb0: int
    asid: int
    valid: bool = True
    stall: bool = False   # CD.S : stall on fault instead of terminate
    record: bool = True   # CD.R : record terminated faults in the Event queue


@dataclass
class STE:
    """Stream Table Entry (one per StreamID)."""
    valid: bool = True
    config: str = BYPASS
    cds: Dict[int, CD] = field(default_factory=dict)  # stands in for the CD table
    s1cdmax: int = 0            # number of SSIDs = 2**s1cdmax
    s1dss: str = "terminate"    # non-substream txn when substreams on: terminate|bypass|ssid0
    s2_ttb: int = 0
    vmid: int = 0
    s2_stall: bool = False      # STE.S2S
    stream_world: str = "NS-EL1"

    @property
    def s1(self) -> bool:
        return self.config in (S1_ONLY, NESTED)

    @property
    def s2(self) -> bool:
        return self.config in (S2_ONLY, NESTED)


@dataclass
class Event:
    type: str
    sid: int
    ssid: Optional[int] = None
    va: Optional[int] = None
    ipa: Optional[int] = None
    stage: Optional[int] = None
    stall: bool = False
    stag: Optional[int] = None
    on_table_fetch: bool = False


@dataclass
class Result:
    pa: Optional[int] = None
    event: Optional[Event] = None
    terminated: bool = False
    stalled: bool = False
    from_tlb: bool = False


@dataclass
class _StalledTxn:
    sid: int
    va: int
    access: Access
    ssid: Optional[int]


class Smmu:
    def __init__(self, mem: Memory, *, sidsize: int = 8, tlb_entries: int = 64,
                 cmdq_log2: int = 4, evtq_log2: int = 4) -> None:
        self.mem = mem
        self.sidsize = sidsize
        self.stream_table: Dict[int, STE] = {}     # software-owned "memory"
        self._ste_cache: Dict[int, STE] = {}       # SMMU's private copies
        self._cd_cache: Dict[tuple, CD] = {}
        self.tlb = Tlb(tlb_entries)
        self.cmdq: SmmuQueue[dict] = SmmuQueue(cmdq_log2)
        self.evtq: SmmuQueue[Event] = SmmuQueue(evtq_log2)
        self.smmuen = True
        self.gbpa_abort = False
        self.cmdq_error: Optional[str] = None      # CMDQ_CONS.ERR
        self.gerror: set = set()
        self.sync_count = 0
        self._stalls: Dict[int, _StalledTxn] = {}
        self._next_stag = 0
        self.events_dropped = 0

    # ------------------------------------------------------------------ config
    def _get_ste(self, sid: int) -> Optional[STE]:
        if sid not in self._ste_cache:
            ste = self.stream_table.get(sid)
            if ste is None:
                return None
            self._ste_cache[sid] = copy.deepcopy(ste)
        return self._ste_cache[sid]

    def _get_cd(self, sid: int, ssid: int, ste: STE) -> Optional[CD]:
        key = (sid, ssid)
        if key not in self._cd_cache:
            # The CD lives in memory, pointed to by the STE: read the software copy,
            # not the cached STE, so CMD_CFGI_CD alone is enough after a CD edit.
            mem_ste = self.stream_table.get(sid, ste)
            cd = mem_ste.cds.get(ssid)
            if cd is None:
                return None
            self._cd_cache[key] = copy.deepcopy(cd)
        return self._cd_cache[key]

    # ------------------------------------------------------------- translation
    def _record(self, ev: Event) -> None:
        if not self.evtq.push(ev):
            self.events_dropped += 1

    def _fault(self, ev: Event, stall: bool, record: bool,
               sid: int, va: int, access: Access, ssid: Optional[int]) -> Result:
        if stall:
            stag = self._next_stag
            self._next_stag += 1
            self._stalls[stag] = _StalledTxn(sid, va, access, ssid)
            ev.stall, ev.stag = True, stag
            self._record(ev)  # stall events are always recorded
            return Result(event=ev, stalled=True)
        if record:
            self._record(ev)
        return Result(event=ev, terminated=True)

    def translate(self, sid: int, va: int, access: Access = Access(),
                  ssid: Optional[int] = None) -> Result:
        if not self.smmuen:
            return Result(terminated=True) if self.gbpa_abort else Result(pa=va)
        if sid >> self.sidsize:
            return self._cfg_err("C_BAD_STREAMID", sid, ssid, va)
        ste = self._get_ste(sid)
        if ste is None:
            return self._cfg_err("C_BAD_STREAMID", sid, ssid, va)
        if not ste.valid or ste.config not in CONFIG_ENCODING:
            return self._cfg_err("C_BAD_STE", sid, ssid, va)
        if ste.config == ABORT:
            return Result(terminated=True)  # silent: no event recorded
        if ste.config == BYPASS:
            return Result(pa=va)

        do_s1 = ste.s1
        cd = None
        if do_s1:
            if ssid is None and ste.s1cdmax > 0:
                if ste.s1dss == "terminate":
                    ev = Event("F_STREAM_DISABLED", sid, None, va)
                    self._record(ev)
                    return Result(event=ev, terminated=True)
                if ste.s1dss == "bypass":
                    do_s1 = False
                else:
                    ssid = 0
            elif ssid is None:
                ssid = 0
            elif ssid >> ste.s1cdmax:
                return self._cfg_err("C_BAD_SUBSTREAMID", sid, ssid, va)
        if do_s1:
            cd = self._get_cd(sid, ssid, ste)
            if cd is None or not cd.valid:
                return self._cfg_err("C_BAD_CD", sid, ssid, va)

        asid = cd.asid if do_s1 else -1
        vmid = ste.vmid if ste.s2 else 0
        hit = self.tlb.lookup(ste.stream_world, vmid, asid, va)
        if hit is not None:
            if ((access.write and not hit.writable) or (not access.priv and not hit.el0)
                    or (access.exec and hit.xn)):
                ev = Event("F_PERMISSION", sid, ssid, va, stage=1 if do_s1 else 2)
                stall = cd.stall if do_s1 else ste.s2_stall
                return self._fault(ev, stall, cd.record if cd else True, sid, va, access, ssid)
            return Result(pa=hit.pa_base | (va - hit.va_base), from_tlb=True)

        # ---- cold walk ----
        s2_xlate = None
        if ste.s2:
            def s2_xlate(ipa: int):
                r = walk(self.mem, ste.s2_ttb, ipa, Access(write=False), stage=2)
                if isinstance(r, Fault):
                    r.ipa = ipa
                return r.out_addr if isinstance(r, Translation) else r

        size = 1 << 12
        writable, el0, xn = True, True, False
        if do_s1:
            r1 = walk(self.mem, cd.ttb0, va, access, stage=1, table_addr_xlate=s2_xlate)
            if isinstance(r1, Fault):
                return self._walk_fault(r1, sid, ssid, va, access, ste, cd)
            ipa, size, writable = r1.out_addr, r1.size, r1.writable
            el0, xn = r1.el0, r1.xn
        else:
            ipa = va
        if ste.s2:
            r2 = walk(self.mem, ste.s2_ttb, ipa, access, stage=2)
            if isinstance(r2, Fault):
                r2.ipa = ipa
                return self._walk_fault(r2, sid, ssid, va, access, ste, cd)
            pa = r2.out_addr
            size = min(size, r2.size)
            writable = writable and r2.writable
            xn = xn or r2.xn
        else:
            pa = ipa
        base_va = va & ~(size - 1)
        self.tlb.fill(TlbEntry(ste.stream_world, vmid, asid, base_va, size,
                               pa & ~(size - 1), writable, el0, xn))
        return Result(pa=pa)

    def _walk_fault(self, f: Fault, sid, ssid, va, access, ste: STE, cd: Optional[CD]) -> Result:
        ev = Event(f.type.value, sid, ssid, va, ipa=f.ipa, stage=f.stage,
                   on_table_fetch=f.on_table_fetch)
        if f.stage == 1:
            stall, record = cd.stall, cd.record
        else:
            stall, record = ste.s2_stall, True
        return self._fault(ev, stall, record, sid, va, access, ssid)

    def _cfg_err(self, kind: str, sid, ssid, va) -> Result:
        ev = Event(kind, sid, ssid, va)
        self._record(ev)
        return Result(event=ev, terminated=True)

    # ---------------------------------------------------------------- commands
    def submit(self, opcode: str, **args) -> bool:
        return self.cmdq.push({"op": opcode, **args})

    def process_commands(self) -> List[Optional[Result]]:
        """Consume commands until empty or error. Returns results of any RESUMEs."""
        out = []
        while self.cmdq_error is None and not self.cmdq.is_empty():
            cmd = self.cmdq.slots[self.cmdq._idx(self.cmdq.cons)]
            op = cmd["op"]
            if op == "CMD_CFGI_STE":
                self._ste_cache.pop(cmd["sid"], None)
            elif op == "CMD_CFGI_CD":
                self._cd_cache.pop((cmd["sid"], cmd["ssid"]), None)
            elif op == "CMD_CFGI_CD_ALL":
                for k in [k for k in self._cd_cache if k[0] == cmd["sid"]]:
                    del self._cd_cache[k]
            elif op == "CMD_TLBI_NH_VA":
                self.tlb.inv_va(cmd.get("vmid", 0), cmd["asid"], cmd["va"])
            elif op == "CMD_TLBI_NH_ASID":
                self.tlb.inv_asid(cmd.get("vmid", 0), cmd["asid"])
            elif op == "CMD_TLBI_S12_VMALL":
                self.tlb.inv_vmid(cmd["vmid"])
            elif op == "CMD_TLBI_NSNH_ALL":
                self.tlb.inv_all()
            elif op == "CMD_RESUME":
                t = self._stalls.pop(cmd["stag"], None)
                if t is not None:
                    out.append(self.translate(t.sid, t.va, t.access, t.ssid)
                               if cmd.get("retry", True) else Result(terminated=True))
            elif op == "CMD_SYNC":
                # In this sequential model every earlier command is already complete.
                self.sync_count += 1
            else:
                self.cmdq_error = "CERROR_ILL"  # CONS stays pointing at the bad command
                self.gerror.add("CMDQ_ERR")
                break
            self.cmdq.pop()
        return out

    def clear_cmdq_error(self, skip: bool = True) -> None:
        """Software acknowledges GERROR.CMDQ_ERR and (here) skips the bad command."""
        if skip and not self.cmdq.is_empty():
            self.cmdq.pop()
        self.cmdq_error = None
        self.gerror.discard("CMDQ_ERR")

    def disable(self) -> None:
        """SMMUEN 1 -> 0: stalled transactions are terminated."""
        self.smmuen = False
        self._stalls.clear()
