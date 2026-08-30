"""Protocol and decoder tests for the omarchy-buds daemon.

Run with:  python3 -m unittest discover -s tests
"""

import importlib.util
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
DAEMON = os.path.join(HERE, "..", "daemon", "omarchy-buds")


def load_daemon():
    loader = importlib.machinery.SourceFileLoader("omarchy_buds", DAEMON)
    spec = importlib.util.spec_from_loader("omarchy_buds", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


importlib.machinery = __import__("importlib.machinery").machinery
ob = load_daemon()


class Crc16Tests(unittest.TestCase):
    def test_known_frame_from_galaxybudsclient_checks_to_zero(self):
        # Sample documented in GalaxyBudsClient's Crc16.cs: id 0x61, payload, then CRC bytes 0x0F 0xF3.
        body = bytes([0x61, 0x02, 0x00, 0x4B, 0x5F, 0x01, 0x00, 0x00, 0x00, 0x01, 0x05, 0x00, 0x02, 0x00, 0x13])
        # The buds send the CRC little-endian; appended big-endian it leaves a zero remainder.
        self.assertEqual(ob.crc16(body + bytes([0xF3, 0x0F])), 0)
        self.assertEqual(ob.crc16(body), 0xF30F)
        self.assertEqual(list(ob.FrameParser().feed(bytes([0xFD, 0x11, 0x00]) + body + bytes([0x0F, 0xF3, 0xDD]))),
                         [(0x61, body[1:], False)])

    def test_encode_roundtrips_through_parser(self):
        frame = ob.encode(ob.Msg.NOISE_CONTROLS, bytes([1]))
        self.assertEqual(frame[0], ob.SOM)
        self.assertEqual(frame[-1], ob.EOM)
        self.assertEqual(int.from_bytes(frame[1:3], "little"), 4)
        parsed = list(ob.FrameParser().feed(frame))
        self.assertEqual(parsed, [(ob.Msg.NOISE_CONTROLS, bytes([1]), False)])

    def test_manager_info_frame_bytes(self):
        frame = ob.encode(ob.Msg.MANAGER_INFO, bytes([1, 1, 34]))
        self.assertEqual(frame[:4], bytes([0xFD, 0x06, 0x00, 136]))
        self.assertEqual(len(frame), 1 + 2 + 1 + 3 + 2 + 1)


class FrameParserTests(unittest.TestCase):
    def test_split_across_reads_and_junk_before_som(self):
        frame = ob.encode(ob.Msg.STATUS_UPDATED, bytes(range(8)))
        parser = ob.FrameParser()
        first = list(parser.feed(b"\x00\x11" + frame[:5]))
        second = list(parser.feed(frame[5:]))
        self.assertEqual(first, [])
        self.assertEqual(second, [(ob.Msg.STATUS_UPDATED, bytes(range(8)), False)])

    def test_two_frames_in_one_read(self):
        a = ob.encode(ob.Msg.STATUS_UPDATED, b"\x01")
        b = ob.encode(ob.Msg.AMBIENT_VOLUME, b"\x02")
        parsed = list(ob.FrameParser().feed(a + b))
        self.assertEqual([p[0] for p in parsed], [ob.Msg.STATUS_UPDATED, ob.Msg.AMBIENT_VOLUME])

    def test_bad_crc_is_skipped_not_raised(self):
        frame = bytearray(ob.encode(ob.Msg.STATUS_UPDATED, b"\x01\x02"))
        frame[5] ^= 0xFF
        good = ob.encode(ob.Msg.AMBIENT_VOLUME, b"\x02")
        parsed = list(ob.FrameParser().feed(bytes(frame) + good))
        self.assertEqual(parsed, [(ob.Msg.AMBIENT_VOLUME, b"\x02", False)])

    def test_response_bit_is_reported(self):
        frame = bytearray(ob.encode(ob.Msg.ACK, b"\x78\x01"))
        frame[2] |= 0x10
        parsed = list(ob.FrameParser().feed(bytes(frame)))
        self.assertEqual(parsed, [(ob.Msg.ACK, b"\x78\x01", True)])


class IdentifyTests(unittest.TestCase):
    def test_pro_beats_base_model(self):
        self.assertEqual(ob.identify("Hector's Buds4 Pro")["label"], "Galaxy Buds4 Pro")
        self.assertEqual(ob.identify("Galaxy Buds3")["label"], "Galaxy Buds3")
        self.assertEqual(ob.identify("Galaxy Buds3 FE")["label"], "Galaxy Buds3 FE")
        self.assertEqual(ob.identify("Galaxy Buds FE")["label"], "Galaxy Buds FE")
        self.assertEqual(ob.identify("Galaxy Buds2 Pro")["family"], "buds2pro")
        self.assertEqual(ob.identify("Galaxy Buds Pro")["uuid"], ob.UUID_SPP_STANDARD)

    def test_unknown_buds_fall_back_to_generic(self):
        self.assertEqual(ob.identify("Galaxy Buds9 Ultra")["family"], "generic")
        self.assertIsNone(ob.identify("Sony WH-1000XM5"))


def buds3_extended_payload(**overrides):
    """A plausible EXTENDED_STATUS_UPDATED payload for the Buds3 family."""
    p = bytearray(57)
    p[0] = 1            # revision
    p[2], p[3] = 87, 91  # battery L, R
    p[4] = 1            # coupled
    p[6] = 0x11         # both wearing
    p[7] = 64           # case
    p[9] = 2            # eq: soft
    p[10] = 0x8F        # touch unlocked, single/double/triple/hold on
    p[12] = 1           # anc
    p[23] = 1           # ambient volume
    p[26] = 1           # detect conversations
    p[28] = 1           # noise controls with one earbud
    p[42] = 0x00        # nothing charging
    for k, v in overrides.items():
        p[int(k)] = v
    return bytes(p)


class DecoderTests(unittest.TestCase):
    def state_for(self, name):
        s = ob.BudsState()
        s.model = ob.identify(name)
        return s

    def test_buds3_family_extended_status(self):
        s = self.state_for("Buds4 Pro")
        s.apply_extended_status(buds3_extended_payload())
        self.assertEqual((s.left["level"], s.right["level"], s.case["level"]), (87, 91, 64))
        self.assertEqual(s.left["placement"], "wearing")
        self.assertEqual(s.noise_mode, "anc")
        self.assertEqual(s.ambient_volume, 1)
        self.assertEqual(s.eq_preset, "soft")
        self.assertFalse(s.touch_locked)
        self.assertTrue(s.conversation_detect)
        self.assertTrue(s.one_bud_anc)
        self.assertEqual(s.available_noise_modes(), ["off", "anc", "ambient", "adaptive"])

    def test_charging_bits_and_case_placement(self):
        s = self.state_for("Buds4 Pro")
        s.apply_extended_status(buds3_extended_payload(**{"6": 0x33, "42": 0x15}))
        self.assertTrue(s.left["charging"] and s.right["charging"] and s.case["charging"])
        self.assertEqual(s.left["placement"], "case")

    def test_disconnected_bud_has_no_level(self):
        s = self.state_for("Buds4 Pro")
        s.apply_extended_status(buds3_extended_payload(**{"6": 0x01, "2": 0}))
        self.assertIsNone(s.left["level"])
        self.assertEqual(s.right["level"], 91)

    def test_touch_lock_bit(self):
        s = self.state_for("Buds4 Pro")
        s.apply_extended_status(buds3_extended_payload(**{"10": 0x0F}))
        self.assertTrue(s.touch_locked)
        self.assertEqual(s.touch_flags, 0x0F)

    def test_short_status_heartbeat(self):
        s = self.state_for("Buds4 Pro")
        s.apply_status(bytes([1, 50, 60, 1, 0, 0x12, 70, 0x04]))
        self.assertEqual((s.left["level"], s.right["level"], s.case["level"]), (50, 60, 70))
        self.assertEqual((s.left["placement"], s.right["placement"]), ("wearing", "idle"))
        self.assertTrue(s.right["charging"])

    def test_ack_updates_eq_but_is_only_a_receipt_for_noise(self):
        s = self.state_for("Buds4 Pro")
        s.noise_mode = "ambient"
        # Seen live: the Buds4 Pro acks NOISE_CONTROLS with 0, which is not "Off".
        s.apply_ack(bytes([ob.Msg.NOISE_CONTROLS, 0]))
        self.assertEqual(s.noise_mode, "ambient")
        s.apply_ack(bytes([ob.Msg.EQUALIZER, 0]))
        self.assertEqual(s.eq_preset, "off")
        s.apply_ack(bytes([ob.Msg.EQUALIZER, 5]))
        self.assertEqual(s.eq_preset, "treble")

    def test_adaptive_reported_by_non_pro_becomes_available(self):
        s = self.state_for("Galaxy Buds3")
        self.assertNotIn("adaptive", s.available_noise_modes())
        s.apply_extended_status(buds3_extended_payload(**{"12": 3}))
        self.assertIn("adaptive", s.available_noise_modes())

    def test_legacy_family_reports_battery_only(self):
        s = self.state_for("Galaxy Buds Live")
        s.apply_extended_status(buds3_extended_payload())
        self.assertEqual(s.left["level"], 87)
        self.assertIsNone(s.noise_mode)
        self.assertEqual(s.available_noise_modes(), [])

    def test_status_json_shape(self):
        s = self.state_for("Buds4 Pro")
        s.connected = True
        s.apply_extended_status(buds3_extended_payload())
        j = s.to_json()
        self.assertEqual(j["schema_version"], ob.SCHEMA_VERSION)
        self.assertEqual(j["device"]["model"], "Galaxy Buds4 Pro")
        self.assertEqual(j["battery"]["left"]["level"], 87)
        self.assertEqual(j["noise"]["ambient_volume_max"], 4)
        self.assertTrue(j["supports"]["touch_lock"])
        self.assertEqual(j["equalizer"]["presets"][0], "off")


if __name__ == "__main__":
    unittest.main()
