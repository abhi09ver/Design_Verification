"""
Directed tests for gic_ref_model.py. Each test is one interview corner case.
Run from this folder:  python3 -m unittest -v
"""
import unittest

from gic_ref_model import SPURIOUS, Gic, Group, State, intid_type, signal_kind


class IntidMap(unittest.TestCase):
    def test_ranges(self):
        self.assertEqual(intid_type(0), "SGI")
        self.assertEqual(intid_type(27), "PPI")
        self.assertEqual(intid_type(1060), "PPI")      # extended PPI (GICv3.1)
        self.assertEqual(intid_type(100), "SPI")
        self.assertEqual(intid_type(4100), "SPI")      # extended SPI (GICv3.1)
        self.assertEqual(intid_type(1023), "SPECIAL")
        self.assertEqual(intid_type(8192), "LPI")
        self.assertEqual(intid_type(2000), "RESERVED")


class Signalling(unittest.TestCase):
    def test_irq_fiq_matrix(self):
        self.assertEqual(signal_kind(Group.G0, pe_secure=False, at_el3=False), "FIQ")
        self.assertEqual(signal_kind(Group.G1NS, pe_secure=False, at_el3=False), "IRQ")
        self.assertEqual(signal_kind(Group.G1NS, pe_secure=True, at_el3=False), "FIQ")
        self.assertEqual(signal_kind(Group.G1S, pe_secure=True, at_el3=False), "IRQ")
        self.assertEqual(signal_kind(Group.G1S, pe_secure=False, at_el3=False), "FIQ")
        self.assertEqual(signal_kind(Group.G1NS, pe_secure=True, at_el3=True), "FIQ")

    def test_group_disable_blocks_signal(self):
        g = Gic(1)
        g.add_spi(40, priority=0x40).edge_pulse()
        g.pes[0].igrpen[Group.G1NS] = False
        self.assertFalse(g.irq_lines(0)["IRQ"])
        self.assertEqual(g.read_iar(0), SPURIOUS)


class Lifecycle(unittest.TestCase):
    def test_edge_basic(self):
        g = Gic(1)
        s = g.add_spi(40)
        s.edge_pulse()
        self.assertTrue(g.irq_lines(0)["IRQ"])
        self.assertEqual(g.read_iar(0), 40)
        self.assertEqual(s.state, State.ACTIVE)
        g.write_eoir(0, 40)
        self.assertEqual(s.state, State.INACTIVE)

    def test_edge_while_active_is_not_lost(self):
        g = Gic(1)
        s = g.add_spi(40)
        s.edge_pulse()
        g.read_iar(0)
        s.edge_pulse()                                  # arrives while active
        self.assertEqual(s.state, State.ACTIVE_PENDING)
        self.assertEqual(g.read_iar(0), SPURIOUS)       # same INTID cannot nest
        g.write_eoir(0, 40)
        self.assertEqual(s.state, State.PENDING)
        self.assertEqual(g.read_iar(0), 40)             # taken once more

    def test_level_still_high_at_ack(self):
        g = Gic(1)
        s = g.add_spi(41, edge=False)
        s.set_level(True)
        g.read_iar(0)
        self.assertEqual(s.state, State.ACTIVE_PENDING)

    def test_level_deasserted_before_eoi(self):
        g = Gic(1)
        s = g.add_spi(41, edge=False)
        s.set_level(True)
        g.read_iar(0)
        s.set_level(False)                              # handler cleared the device
        self.assertEqual(s.state, State.ACTIVE)
        g.write_eoir(0, 41)
        self.assertEqual(s.state, State.INACTIVE)       # no false re-fire


class Priority(unittest.TestCase):
    def test_highest_priority_wins(self):
        g = Gic(1)
        g.add_spi(50, priority=0xC0).edge_pulse()
        g.add_spi(51, priority=0x10).edge_pulse()
        self.assertEqual(g.read_iar(0), 51)

    def test_pmr_masks_strictly_less(self):
        g = Gic(1)
        g.add_spi(50, priority=0xA0).edge_pulse()
        g.pes[0].pmr = 0xA0                              # equal is NOT enough
        self.assertEqual(g.read_iar(0), SPURIOUS)
        g.pes[0].pmr = 0xA8
        self.assertEqual(g.read_iar(0), 50)

    def test_preemption_uses_group_priority(self):
        g = Gic(1)
        g.pes[0].bpr = 2                                 # group priority = bits [7:3]
        g.add_spi(60, priority=0x40).edge_pulse()
        self.assertEqual(g.read_iar(0), 60)
        g.add_spi(61, priority=0x44).edge_pulse()        # same group priority 0x40
        self.assertEqual(g.read_iar(0), SPURIOUS)
        g.add_spi(62, priority=0x38).edge_pulse()        # 0x38 < 0x40 -> preempts
        self.assertEqual(g.read_iar(0), 62)
        g.write_eoir(0, 62)
        g.write_eoir(0, 60)
        self.assertEqual(g.read_iar(0), 61)

    def test_eoi_out_of_order_is_flagged(self):
        g = Gic(1)
        g.add_spi(60, priority=0x40).edge_pulse()
        g.read_iar(0)
        g.add_spi(62, priority=0x20).edge_pulse()
        g.read_iar(0)
        g.write_eoir(0, 60)                              # should EOI 62 first
        self.assertTrue(g.pes[0].errors)

    def test_eoimode1_split_drop_and_deactivate(self):
        g = Gic(1)
        g.pes[0].eoimode = 1
        s = g.add_spi(70, priority=0x40)
        s.edge_pulse()
        g.read_iar(0)
        g.write_eoir(0, 70)
        self.assertEqual(g.pes[0].running_priority, 0xFF)   # priority dropped
        self.assertEqual(s.state, State.ACTIVE)             # still active
        s.edge_pulse()
        self.assertEqual(g.read_iar(0), SPURIOUS)           # cannot re-fire yet
        g.write_dir(0, 70)
        self.assertEqual(g.read_iar(0), 70)


class Routing(unittest.TestCase):
    def test_sgi_broadcast_excludes_sender(self):
        g = Gic(3)
        g.send_sgi(sender=0, intid=1, irm=1)
        self.assertEqual(g.read_iar(0), SPURIOUS)
        self.assertEqual(g.read_iar(1), 1)
        self.assertEqual(g.read_iar(2), 1)

    def test_one_of_n_skips_sleeping_and_disabled(self):
        g = Gic(3)
        g.set_processor_sleep(0, True)
        g.pes[1].igrpen[Group.G1NS] = False
        g.add_spi(80, irm=1).edge_pulse()
        self.assertEqual(g.spi_target(80), 2)
        self.assertEqual(g.read_iar(2), 80)

    def test_one_of_n_taken_exactly_once(self):
        g = Gic(2)
        g.add_spi(81, irm=1).edge_pulse()
        taken = [g.read_iar(0), g.read_iar(1)]
        self.assertEqual(sorted(taken), [81, SPURIOUS])


class Power(unittest.TestCase):
    def test_sleeping_pe_gets_wake_request(self):
        g = Gic(1)
        g.set_processor_sleep(0, True)
        g.add_spi(90).edge_pulse()
        self.assertEqual(g.irq_lines(0), {"IRQ": False, "FIQ": False})
        self.assertTrue(g.pes[0].wake_request)
        g.set_processor_sleep(0, False)
        self.assertTrue(g.irq_lines(0)["IRQ"])


class ItsAndLpi(unittest.TestCase):
    def setUp(self):
        self.g = Gic(2)
        its = self.g.its
        its.mapd(dev=7, size=32)
        its.mapc(icid=0, pe=0)
        its.mapc(icid=1, pe=1)
        its.mapti(dev=7, ev=3, intid=8200, icid=0)

    def test_translate_and_no_active_state(self):
        self.assertTrue(self.g.its.translate(7, 3))
        self.assertEqual(self.g.read_iar(0), 8200)
        self.assertEqual(self.g.pes[0].private[8200].state, State.INACTIVE)
        self.g.write_eoir(0, 8200)                       # priority drop only
        self.assertEqual(self.g.pes[0].running_priority, 0xFF)

    def test_unmapped_device_is_error(self):
        self.assertFalse(self.g.its.translate(9, 0))
        self.assertTrue(self.g.its.errors)

    def test_movi_moves_pending_exactly_once(self):
        self.g.its.translate(7, 3)
        self.g.its.movi(7, 3, new_icid=1)
        self.g.its.sync(1)
        self.assertEqual(self.g.read_iar(0), SPURIOUS)
        self.assertEqual(self.g.read_iar(1), 8200)

    def test_discard_removes_mapping_and_pending(self):
        self.g.its.translate(7, 3)
        self.g.its.discard(7, 3)
        self.assertEqual(self.g.read_iar(0), SPURIOUS)
        self.assertFalse(self.g.its.translate(7, 3))

    def test_mapd_unmap_drops_translations(self):
        self.g.its.mapd(7, 0, valid=False)
        self.assertFalse(self.g.its.translate(7, 3))


if __name__ == "__main__":
    unittest.main(verbosity=2)
