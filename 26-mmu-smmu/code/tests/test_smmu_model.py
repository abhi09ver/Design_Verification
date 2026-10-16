"""Self-checking tests for the teaching SMMU model.

Run from 26-mmu-smmu/code:   python3 -m unittest discover -s tests -v
Each test is written as an interview scenario: the docstring is the question,
the assertions are the answer.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from smmu_model import (Access, CD, STE, Memory, PageTableBuilder, Smmu, SmmuQueue,  # noqa: E402
                        Tlb, TlbEntry, nested_walk_cost, page_offset, slice_va, walk)
from smmu_model.smmu import ABORT, BYPASS, NESTED, S1_ONLY, S2_ONLY  # noqa: E402

KB, MB, GB = 1 << 10, 1 << 20, 1 << 30


class TestAddressing(unittest.TestCase):
    def test_4k_48bit_slices(self):
        """Which VA bits index each level for a 4KB granule, 48-bit VA?"""
        s = slice_va(0x0000_7F12_3456_7ABC, 12, 48)
        self.assertEqual([(x.level, x.hi, x.lo) for x in s],
                         [(0, 47, 39), (1, 38, 30), (2, 29, 21), (3, 20, 12)])
        self.assertEqual(page_offset(0x7ABC), 0xABC)

    def test_64k_48bit_has_three_levels(self):
        """64KB granule: how many levels for a 48-bit VA, and what does L1 use?"""
        s = slice_va(0x0000_7F12_3456_7ABC, 16, 48)
        self.assertEqual([(x.level, x.hi, x.lo) for x in s],
                         [(1, 47, 42), (2, 41, 29), (3, 28, 16)])

    def test_nested_walk_cost(self):
        """Cold nested walk, 4-level S1 and 4-level S2: how many memory reads?"""
        self.assertEqual(nested_walk_cost(4, 4), 24)
        self.assertEqual(nested_walk_cost(4, 0), 4)
        self.assertEqual(nested_walk_cost(3, 3), 15)


class TestPageTableWalk(unittest.TestCase):
    def setUp(self):
        self.mem = Memory()
        self.pt = PageTableBuilder(self.mem)

    def test_page_and_block(self):
        """A 4KB page resolves at L3; a 2MB block stops the walk at L2."""
        self.pt.map(0x4000_0000, 0x1_2345_6000)
        self.pt.map(0x8020_0000, 0x2_0000_0000, 2 * MB)
        t = walk(self.mem, self.pt.root, 0x4000_0ABC)
        self.assertEqual((t.out_addr, t.level), (0x1_2345_6ABC, 3))
        t = walk(self.mem, self.pt.root, 0x8021_2345)
        self.assertEqual((t.out_addr, t.level, t.size), (0x2_0001_2345, 2, 2 * MB))

    def test_faults(self):
        """Unmapped, read-only write, EL0 to kernel page, exec of XN, AF=0, bad output size."""
        self.pt.map(0x1000, 0x10_0000, writable=False)
        self.pt.map(0x2000, 0x20_0000, el0=False)
        self.pt.map(0x3000, 0x30_0000, xn=True)
        self.pt.map(0x4000, 0x40_0000, af=False)
        self.pt.map(0x5000, 0x0000_FF00_0000_0000)
        f = lambda va, **a: walk(self.mem, self.pt.root, va, Access(**a), oas_bits=40)
        self.assertEqual(f(0x9000).type.value, "F_TRANSLATION")
        self.assertEqual(f(0x1000, write=True).type.value, "F_PERMISSION")
        self.assertEqual(f(0x2000, priv=False).type.value, "F_PERMISSION")
        self.assertEqual(f(0x3000, exec=True).type.value, "F_PERMISSION")
        self.assertEqual(f(0x4000).type.value, "F_ACCESS")
        self.assertEqual(f(0x5000).type.value, "F_ADDR_SIZE")
        self.assertEqual(f(1 << 48).type.value, "F_TRANSLATION")

    def test_external_abort_on_walk(self):
        """A bus error while reading a descriptor is F_WALK_EABT, not a translation fault."""
        self.pt.map(0x1000, 0x10_0000)
        trace = []
        walk(self.mem, self.pt.root, 0x1000, trace=trace)
        self.mem.abort_addrs.add(trace[2])  # the L2 descriptor
        self.assertEqual(walk(self.mem, self.pt.root, 0x1000).type.value, "F_WALK_EABT")


class TestQueue(unittest.TestCase):
    def test_wrap_bit_full_empty(self):
        """With a wrap bit, all 2**N slots are usable and full/empty are distinguishable."""
        q = SmmuQueue(2)
        self.assertTrue(q.is_empty())
        for i in range(4):
            self.assertTrue(q.push(i))
        self.assertTrue(q.is_full())
        self.assertEqual(q._idx(q.prod), q._idx(q.cons))
        self.assertNotEqual(q._wrap(q.prod), q._wrap(q.cons))
        self.assertEqual([q.pop() for _ in range(4)], [0, 1, 2, 3])
        self.assertTrue(q.is_empty())

    def test_overflow_flag_episode(self):
        """Overflow toggles OVFLG once per episode until software acknowledges."""
        q = SmmuQueue(1)
        q.push(1), q.push(2)
        self.assertFalse(q.push(3))
        self.assertFalse(q.push(4))
        self.assertEqual(q.overflow_flag, 1)  # toggled once, not twice
        q.ack_overflow()
        q.pop()
        q.push(5)
        self.assertFalse(q.push(6))
        self.assertEqual(q.overflow_flag, 0)  # new episode toggles again


class TestTlb(unittest.TestCase):
    def test_asid_isolation_and_global(self):
        """Same VA, different ASIDs, must not share entries; global entries match any ASID."""
        t = Tlb(8)
        t.fill(TlbEntry("NS-EL1", 0, 1, 0x1000, 4 * KB, 0xA000, True))
        self.assertIsNone(t.lookup("NS-EL1", 0, 2, 0x1000))
        t.fill(TlbEntry("NS-EL1", 0, None, 0x2000, 4 * KB, 0xB000, True))
        self.assertIsNotNone(t.lookup("NS-EL1", 0, 99, 0x2000))
        self.assertIsNone(t.lookup("EL2", 0, 99, 0x2000))  # different StreamWorld

    def test_lru_eviction(self):
        t = Tlb(2)
        for va in (0x1000, 0x2000):
            t.fill(TlbEntry("NS-EL1", 0, 1, va, 4 * KB, va, True))
        t.lookup("NS-EL1", 0, 1, 0x1000)                         # 0x1000 now most recent
        t.fill(TlbEntry("NS-EL1", 0, 1, 0x3000, 4 * KB, 0x3000, True))
        self.assertIsNone(t.lookup("NS-EL1", 0, 1, 0x2000))      # 0x2000 was evicted


def make_s1_smmu(**ste_kw):
    mem = Memory()
    pt = PageTableBuilder(mem)
    smmu = Smmu(mem)
    smmu.stream_table[5] = STE(config=S1_ONLY, cds={0: CD(ttb0=pt.root, asid=7)}, **ste_kw)
    return mem, pt, smmu


class TestSmmuConfig(unittest.TestCase):
    def test_config_modes(self):
        """STE.Config abort is silent; bypass passes VA through; V=0 is C_BAD_STE."""
        smmu = Smmu(Memory())
        smmu.stream_table[1] = STE(config=ABORT)
        smmu.stream_table[2] = STE(config=BYPASS)
        smmu.stream_table[3] = STE(valid=False)
        r = smmu.translate(1, 0x1000)
        self.assertTrue(r.terminated)
        self.assertIsNone(r.event)
        self.assertTrue(smmu.evtq.is_empty())
        self.assertEqual(smmu.translate(2, 0x1234).pa, 0x1234)
        self.assertEqual(smmu.translate(3, 0x1000).event.type, "C_BAD_STE")
        self.assertEqual(smmu.translate(4, 0x1000).event.type, "C_BAD_STREAMID")
        self.assertEqual(smmu.translate(1 << 8, 0x1000).event.type, "C_BAD_STREAMID")

    def test_substreams(self):
        """SSID out of range, missing CD, and S1DSS behaviour for transactions without SSID."""
        mem = Memory()
        pt = PageTableBuilder(mem)
        pt.map(0x1000, 0x5000)
        smmu = Smmu(mem)
        smmu.stream_table[5] = STE(config=S1_ONLY, s1cdmax=2,
                                   cds={0: CD(pt.root, 1), 1: CD(pt.root, 2)})
        self.assertEqual(smmu.translate(5, 0x1000, ssid=1).pa, 0x5000)
        self.assertEqual(smmu.translate(5, 0x1000, ssid=4).event.type, "C_BAD_SUBSTREAMID")
        self.assertEqual(smmu.translate(5, 0x1000, ssid=3).event.type, "C_BAD_CD")
        self.assertEqual(smmu.translate(5, 0x1000).event.type, "F_STREAM_DISABLED")
        smmu.stream_table[5].s1dss = "ssid0"
        smmu.submit("CMD_CFGI_STE", sid=5); smmu.submit("CMD_SYNC"); smmu.process_commands()
        self.assertEqual(smmu.translate(5, 0x1000).pa, 0x5000)

    def test_ste_change_needs_cfgi(self):
        """Editing an STE in memory has no effect until CMD_CFGI_STE + CMD_SYNC."""
        smmu = Smmu(Memory())
        smmu.stream_table[1] = STE(config=BYPASS)
        self.assertEqual(smmu.translate(1, 0x1000).pa, 0x1000)
        smmu.stream_table[1] = STE(config=ABORT)
        self.assertEqual(smmu.translate(1, 0x1000).pa, 0x1000)       # stale config cache
        smmu.submit("CMD_CFGI_STE", sid=1); smmu.submit("CMD_SYNC"); smmu.process_commands()
        self.assertTrue(smmu.translate(1, 0x1000).terminated)


    def test_cd_change_needs_cfgi_cd(self):
        """Editing a CD needs CMD_CFGI_CD (+SYNC); CFGI_STE is not required."""
        mem, pt, smmu = make_s1_smmu()
        pt.map(0x1000, 0x9000)
        self.assertEqual(smmu.translate(5, 0x1000).pa, 0x9000)
        other = PageTableBuilder(mem, alloc_base=0x9000_0000)
        other.map(0x1000, 0xC000)
        smmu.stream_table[5].cds[0] = CD(ttb0=other.root, asid=8)
        self.assertEqual(smmu.translate(5, 0x1000).pa, 0x9000)      # stale CD still cached
        smmu.submit("CMD_CFGI_CD", sid=5, ssid=0); smmu.submit("CMD_SYNC"); smmu.process_commands()
        self.assertEqual(smmu.translate(5, 0x1000).pa, 0xC000)      # new ASID 8 -> new walk


class TestSmmuTranslation(unittest.TestCase):
    def test_tlb_hit_and_stale_entry(self):
        """Classic bug: unmap without TLBI keeps translating. TLBI + SYNC fixes it."""
        mem, pt, smmu = make_s1_smmu()
        pt.map(0x1000, 0x9000)
        self.assertEqual(smmu.translate(5, 0x1ABC).pa, 0x9ABC)
        self.assertTrue(smmu.translate(5, 0x1ABC).from_tlb)
        pt.unmap(0x1000)
        self.assertEqual(smmu.translate(5, 0x1ABC).pa, 0x9ABC)        # stale, but legal before TLBI
        smmu.submit("CMD_TLBI_NH_VA", asid=7, va=0x1000); smmu.submit("CMD_SYNC")
        smmu.process_commands()
        self.assertEqual(smmu.translate(5, 0x1ABC).event.type, "F_TRANSLATION")

    def test_tlb_hit_checks_all_permissions(self):
        """A TLB hit must apply the same permission checks as a walk."""
        mem, pt, smmu = make_s1_smmu()
        pt.map(0x1000, 0x9000, writable=False, el0=False, xn=True)
        self.assertIsNotNone(smmu.translate(5, 0x1000).pa)            # fill the TLB
        for acc in (Access(write=True), Access(priv=False), Access(exec=True)):
            self.assertEqual(smmu.translate(5, 0x1000, acc).event.type, "F_PERMISSION")

    def test_nested_walk(self):
        """Nested S1+S2: correct PA and exactly 24 reads for a cold walk."""
        mem = Memory()
        s1 = PageTableBuilder(mem, alloc_base=0x1000_0000)     # guest tables live at these IPAs
        s2 = PageTableBuilder(mem, alloc_base=0x7000_0000)
        s1.map(0x4000_0000, 0x2000_0000)                      # VA  -> IPA
        for t in range(0x1000_0000, s1.next_table, 0x1000):   # identity-map guest tables
            s2.map(t, t)
        s2.map(0x2000_0000, 0x3_0000_0000)                     # IPA -> PA
        smmu = Smmu(mem)
        smmu.stream_table[9] = STE(config=NESTED, vmid=3, s2_ttb=s2.root,
                                   cds={0: CD(s1.root, asid=1)})
        before = mem.reads
        self.assertEqual(smmu.translate(9, 0x4000_0123).pa, 0x3_0000_0123)
        self.assertEqual(mem.reads - before, nested_walk_cost(4, 4))

    def test_s2_fault_on_s1_table_fetch(self):
        """If an S1 table's IPA is unmapped at S2, the fault is stage 2 on a table fetch."""
        mem = Memory()
        s1 = PageTableBuilder(mem, alloc_base=0x1000_0000)
        s2 = PageTableBuilder(mem, alloc_base=0x7000_0000)
        s1.map(0x4000_0000, 0x2000_0000)
        smmu = Smmu(mem)
        smmu.stream_table[9] = STE(config=NESTED, s2_ttb=s2.root, cds={0: CD(s1.root, 1)})
        ev = smmu.translate(9, 0x4000_0000).event
        self.assertEqual((ev.type, ev.stage, ev.on_table_fetch), ("F_TRANSLATION", 2, True))
        self.assertEqual(ev.ipa, s1.root)

    def test_s2_only_vmid_invalidate(self):
        """S2-only stream: TLBI_S12_VMALL for the VMID removes its entries."""
        mem = Memory()
        s2 = PageTableBuilder(mem)
        s2.map(0x8000, 0x1_0000_8000)
        smmu = Smmu(mem)
        smmu.stream_table[2] = STE(config=S2_ONLY, vmid=4, s2_ttb=s2.root)
        self.assertEqual(smmu.translate(2, 0x8010).pa, 0x1_0000_8010)
        s2.unmap(0x8000)
        smmu.submit("CMD_TLBI_S12_VMALL", vmid=4); smmu.submit("CMD_SYNC"); smmu.process_commands()
        ev = smmu.translate(2, 0x8010).event
        self.assertEqual((ev.type, ev.stage), ("F_TRANSLATION", 2))


class TestFaultModel(unittest.TestCase):
    def test_stall_then_resume(self):
        """Stall: event recorded with STAG, software maps the page, CMD_RESUME retries."""
        mem, pt, smmu = make_s1_smmu()
        smmu.stream_table[5].cds[0].stall = True
        r = smmu.translate(5, 0x6000)
        self.assertTrue(r.stalled)
        ev = smmu.evtq.pop()
        self.assertTrue(ev.stall)
        pt.map(0x6000, 0xA000)
        smmu.submit("CMD_RESUME", stag=ev.stag, retry=True)
        self.assertEqual(smmu.process_commands()[0].pa, 0xA000)

    def test_terminate_record_bit(self):
        """CD.R=0: terminated faults are not recorded."""
        mem, pt, smmu = make_s1_smmu()
        smmu.stream_table[5].cds[0].record = False
        self.assertTrue(smmu.translate(5, 0x6000).terminated)
        self.assertTrue(smmu.evtq.is_empty())

    def test_event_queue_overflow(self):
        """More faults than queue slots: extra events dropped, overflow flagged."""
        mem, pt, smmu = make_s1_smmu()
        for i in range(smmu.evtq.size + 3):
            smmu.translate(5, 0x10_0000 + i * 0x1000)
        self.assertTrue(smmu.evtq.is_full())
        self.assertEqual(smmu.events_dropped, 3)
        self.assertEqual(smmu.evtq.overflow_flag, 1)

    def test_illegal_command_stops_queue(self):
        """CERROR_ILL: SMMU stops at the bad command; later commands wait for software."""
        smmu = Smmu(Memory())
        smmu.submit("CMD_SYNC"); smmu.submit("CMD_BOGUS"); smmu.submit("CMD_SYNC")
        smmu.process_commands()
        self.assertEqual((smmu.cmdq_error, smmu.sync_count), ("CERROR_ILL", 1))
        self.assertIn("CMDQ_ERR", smmu.gerror)
        smmu.clear_cmdq_error()
        smmu.process_commands()
        self.assertEqual(smmu.sync_count, 2)

    def test_smmuen_off_gbpa(self):
        """SMMUEN=0: GBPA decides bypass or abort, and stalls are terminated."""
        mem, pt, smmu = make_s1_smmu()
        smmu.stream_table[5].cds[0].stall = True
        smmu.translate(5, 0x6000)
        smmu.disable()
        self.assertEqual(smmu._stalls, {})
        self.assertEqual(smmu.translate(5, 0x1234).pa, 0x1234)
        smmu.gbpa_abort = True
        self.assertTrue(smmu.translate(5, 0x1234).terminated)


if __name__ == "__main__":
    unittest.main()
