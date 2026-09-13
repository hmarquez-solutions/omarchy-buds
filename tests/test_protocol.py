"""Protocol and decoder tests for the omarchy-buds daemon.

Run with:  python3 -m unittest discover -s tests
"""

import importlib.util
import os
import socket
import sys
import tempfile
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


class BoundaryTests(unittest.TestCase):
    def setUp(self):
        self.old_state = os.environ.get("XDG_STATE_HOME")
        self.old_runtime = os.environ.get("XDG_RUNTIME_DIR")
        self.temp = tempfile.TemporaryDirectory()
        os.environ["XDG_STATE_HOME"] = os.path.join(self.temp.name, "state")
        os.environ["XDG_RUNTIME_DIR"] = os.path.join(self.temp.name, "runtime")
        self.daemon = object.__new__(ob.Daemon)
        self.daemon.state = ob.BudsState()

    def tearDown(self):
        if self.old_state is None:
            os.environ.pop("XDG_STATE_HOME", None)
        else:
            os.environ["XDG_STATE_HOME"] = self.old_state
        if self.old_runtime is None:
            os.environ.pop("XDG_RUNTIME_DIR", None)
        else:
            os.environ["XDG_RUNTIME_DIR"] = self.old_runtime
        self.temp.cleanup()

    def test_runtime_socket_is_in_a_private_subdirectory(self):
        self.assertEqual(ob.socket_path(), os.path.join(self.temp.name, "runtime", "omarchy-buds", "omarchy-buds.sock"))

    def test_publish_replaces_status_symlink_without_following_it(self):
        os.makedirs(ob.state_dir(), mode=0o700)
        outside = os.path.join(self.temp.name, "outside")
        with open(outside, "w", encoding="utf-8") as fh:
            fh.write("must not be overwritten")
        os.symlink(outside, ob.status_path())
        self.daemon.publish()
        self.assertFalse(os.path.islink(ob.status_path()))
        with open(outside, encoding="utf-8") as fh:
            self.assertEqual(fh.read(), "must not be overwritten")
        self.assertEqual(ob.read_status_file()[-1:], b"\n")

    def test_read_status_rejects_symlink(self):
        os.makedirs(ob.state_dir(), mode=0o700)
        outside = os.path.join(self.temp.name, "outside")
        with open(outside, "w", encoding="utf-8") as fh:
            fh.write("{}")
        os.symlink(outside, ob.status_path())
        with self.assertRaises(OSError):
            ob.read_status_file()

    def test_validate_device_requires_pairing_trust_and_expected_uuid(self):
        path = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF"
        base = {
            "Alias": "Galaxy Buds4 Pro",
            "Connected": True,
            "Paired": True,
            "Trusted": True,
            "UUIDs": [ob.UUID_SPP_NEW],
        }
        name, model = self.daemon.validate_device(path, base)
        self.assertEqual((name, model["family"]), ("Galaxy Buds4 Pro", "buds3"))
        for key in ("Connected", "Paired", "Trusted"):
            props = dict(base)
            props[key] = False
            with self.assertRaises(ValueError):
                self.daemon.validate_device(path, props)

    def test_rejected_non_bluetooth_descriptor_is_not_consumed(self):
        left, right = socket.socketpair()
        try:
            with self.assertRaises(ValueError):
                self.daemon.validated_bluetooth_socket(left.fileno())
            left.send(b"x")
            self.assertEqual(right.recv(1), b"x")
        finally:
            left.close()
            right.close()

    def test_rejected_non_socket_descriptor_leaks_nothing(self):
        read_end, write_end = os.pipe()
        try:
            before = len(os.listdir("/proc/self/fd"))
            with self.assertRaises(ValueError):
                self.daemon.validated_bluetooth_socket(read_end)
            self.assertEqual(len(os.listdir("/proc/self/fd")), before)
            os.write(write_end, b"y")
            self.assertEqual(os.read(read_end, 1), b"y")
        finally:
            os.close(read_end)
            os.close(write_end)

    def test_profile_rejects_spoofed_sender_before_unpacking(self):
        class Params:
            def unpack(self):
                raise AssertionError("spoofed sender must not unpack parameters")

        class Invocation:
            def __init__(self):
                self.error = None

            def return_dbus_error(self, name, message):
                self.error = (name, message)

        self.daemon.bluez_owner = ":1.42"
        invocation = Invocation()
        self.daemon.on_profile_call(None, ":1.99", None, None, "NewConnection", Params(), invocation)
        self.assertEqual(invocation.error[0], "org.bluez.Error.Rejected")


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
        # Both buds worn, so the case byte (64) is not a live reading.
        self.assertEqual((s.left["level"], s.right["level"], s.case["level"]), (87, 91, None))
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

    def test_case_level_unknown_unless_a_bud_is_docked(self):
        s = self.state_for("Buds4 Pro")
        # Both buds worn: the case byte is whatever the buds last saw, or 0.
        s.apply_extended_status(buds3_extended_payload(**{"7": 0}))
        self.assertIsNone(s.case["level"])
        s.apply_extended_status(buds3_extended_payload(**{"7": 64}))
        self.assertIsNone(s.case["level"])
        # Left bud in the case: the reading is live.
        s.apply_extended_status(buds3_extended_payload(**{"6": 0x31, "7": 64}))
        self.assertEqual(s.case["level"], 64)
        # Closed case counts as docked; an out-of-range byte keeps the last live reading.
        s.apply_extended_status(buds3_extended_payload(**{"6": 0x14, "7": 100}))
        self.assertEqual(s.case["level"], 100)
        s.apply_extended_status(buds3_extended_payload(**{"6": 0x31, "7": 255}))
        self.assertEqual(s.case["level"], 100)
        # Undocked again: unknown, whatever the byte says.
        s.apply_extended_status(buds3_extended_payload(**{"6": 0x11, "7": 0}))
        self.assertIsNone(s.case["level"])

    def test_noise_update_carries_placement_on_buds3(self):
        # Payloads captured live from a Buds4 Pro while moving the left bud.
        s = self.state_for("Buds4 Pro")
        s.apply_extended_status(buds3_extended_payload())
        self.assertEqual(s.noise_mode, "anc")
        # Docking announced by this frame: no case byte, and none read yet -> unknown,
        # not the meaningless 0/64 seen while both buds were out.
        s.apply_noise_update(bytes.fromhex("02 31 01 00 09 09 02 02 02 02 02"))
        self.assertEqual((s.left["placement"], s.right["placement"]), ("case", "wearing"))
        self.assertIsNone(s.case["level"])
        # A status frame while docked is a live reading; a later 119 docking reuses it.
        s.apply_status(bytes([1, 100, 99, 1, 0, 0x31, 77, 0x00]))
        self.assertEqual(s.case["level"], 77)
        s.apply_noise_update(bytes.fromhex("02 11 01 00 09 09 02 02 02 02 02"))
        self.assertIsNone(s.case["level"])
        s.apply_noise_update(bytes.fromhex("02 13 01 00 09 09 02 02 02 02 02"))
        self.assertEqual(s.case["level"], 77)
        # Byte 0 is the buds' auto-off while nothing is worn, not the chosen mode.
        s.apply_noise_update(bytes.fromhex("00 22 01 00 09 09 02 02 02 02 02"))
        self.assertEqual(s.noise_mode, "anc")
        self.assertEqual((s.left["placement"], s.right["placement"]), ("idle", "idle"))
        self.assertIsNone(s.case["level"])
        # Leaving the case via this frame clears the charging flag it cannot carry.
        s.apply_extended_status(buds3_extended_payload(**{"6": 0x13, "7": 80, "42": 0x05}))
        self.assertTrue(s.right["charging"] and s.case["charging"])
        self.assertEqual((s.right["placement"], s.case["level"]), ("case", 80))
        s.apply_noise_update(bytes.fromhex("02 11 01 00 09 09 02 02 02 02 02"))
        self.assertEqual(s.right["placement"], "wearing")
        self.assertFalse(s.right["charging"])
        self.assertIsNone(s.case["level"])
        # A one-byte update (older models, on a pinch) is the mode.
        s.apply_noise_update(bytes([2]))
        self.assertEqual(s.noise_mode, "ambient")
        self.assertEqual(s.left["placement"], "wearing")
        # Garbage in the placement byte: treated as a mode-only frame, placement untouched.
        s.apply_noise_update(bytes([1, 0xF9]))
        self.assertEqual(s.noise_mode, "anc")
        self.assertEqual(s.left["placement"], "wearing")

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
        # Right reports idle with its charging bit set: it is in the case.
        self.assertEqual((s.left["placement"], s.right["placement"]), ("wearing", "case"))
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
