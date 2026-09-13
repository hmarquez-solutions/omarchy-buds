"""Replay real frame captures through the decoder.

tests/fixtures/*.log are `omarchy-buds daemon --debug` logs from a device,
with the device name and address removed. Every received frame is fed through
Daemon.handle exactly as the daemon would, and after each one the state must
hold the invariants below. Checkpoint tests then pin the behaviour that was
fixed from these very captures, so a refinement that regresses one of them
fails here first.

To add a capture: run `omarchy-buds daemon --debug` in the foreground, move
the buds around, then keep the `<<`, `>>` and link lines (see the fixture
headers for the format).
"""

import glob
import json
import os
import random
import re
import unittest

from test_protocol import ob

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = sorted(glob.glob(os.path.join(HERE, "fixtures", "*.log")))
FRAME = re.compile(r"^(?:\d\d:\d\d:\d\d\.\d+ )?(<<|>>) id=(\d+) (?:resp=(\d)|flags=\S+) payload=(.*)$")
LINK = re.compile(r"^(?:\d\d:\d\d:\d\d\.\d+ )?link (up|closed)$")
DOCKED = ("case", "case_closed")
PUBLISHING_IDS = {ob.Msg.STATUS_UPDATED, ob.Msg.EXTENDED_STATUS_UPDATED, ob.Msg.NOISE_CONTROLS_UPDATE}


def events(path):
    """Yield ("rx"|"tx", id, payload, is_response) and ("link", "up"|"closed")."""
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            m = LINK.match(line)
            if m:
                yield ("link", m.group(1))
                continue
            m = FRAME.match(line)
            if not m:
                raise ValueError(f"{path}: unparsable line {line!r}")
            direction, msg_id, resp, hexes = m.groups()
            payload = bytes.fromhex(hexes.replace(" ", "")) if hexes.strip() else b""
            yield ("rx" if direction == "<<" else "tx", int(msg_id), payload, resp == "1")


class Replay:
    """A Daemon with no bus, no socket and no GLib: just the decoding path."""

    def __init__(self, model="Buds4 Pro"):
        self.model = ob.identify(model)
        self.daemon = object.__new__(ob.Daemon)
        self.daemon.debug = False
        self.daemon.sock = None
        self.daemon.log = lambda msg: None
        self.daemon.request_status = lambda *a, **k: None
        self.daemon.state = ob.BudsState()
        self.link("up")
        self.published = 0

    def link(self, what):
        s = self.daemon.state
        if what == "up":
            s.model = self.model
            s.connected = True
        else:
            s.connected = False
            s.finding = False

    @property
    def state(self):
        return self.daemon.state

    def feed(self, event):
        kind = event[0]
        if kind == "link":
            self.link(event[1])
            return None
        if kind == "tx":
            return None
        _, msg_id, payload, _resp = event
        changed = self.daemon.handle(msg_id, payload)
        if changed:
            self.published += 1
        return changed


def docked(state):
    return any(b["placement"] in DOCKED or b["charging"] for b in (state.left, state.right))


class ReplayInvariantTests(unittest.TestCase):
    def check_invariants(self, state, where):
        for side in ("left", "right"):
            bud = getattr(state, side)
            self.assertIn(bud["placement"], ob.PLACEMENTS.values(), where)
            if bud["level"] is not None:
                self.assertTrue(0 <= bud["level"] <= 100, where)
            if bud["placement"] == "disconnected":
                self.assertIsNone(bud["level"], where)
            # A bud out of the case is not charging, whatever a stale flag said.
            if bud["charging"]:
                self.assertIn(bud["placement"], DOCKED, f"{where}: charging {side} bud not in case")
        if docked(state):
            if state.case["level"] is not None:
                self.assertTrue(0 <= state.case["level"] <= 100, where)
        else:
            self.assertIsNone(state.case["level"], f"{where}: case level with nothing docked")
        self.assertIn(state.noise_mode, list(ob.NOISE_MODES.values()) + [None], where)
        doc = json.dumps(state.to_json())
        self.assertLessEqual(len(doc), ob.MAX_STATUS_BYTES, where)
        self.assertEqual(json.loads(doc)["schema_version"], ob.SCHEMA_VERSION, where)

    def test_fixtures_exist(self):
        self.assertGreaterEqual(len(FIXTURES), 3)

    def test_every_capture_holds_invariants_after_every_frame(self):
        for path in FIXTURES:
            replay = Replay()
            frames = 0
            for n, ev in enumerate(events(path)):
                changed = replay.feed(ev)
                if ev[0] != "rx":
                    continue
                frames += 1
                where = f"{os.path.basename(path)} event {n} id={ev[1]}"
                self.check_invariants(replay.state, where)
                if ev[1] in PUBLISHING_IDS:
                    self.assertTrue(changed, f"{where}: status frame did not publish")
            self.assertGreater(frames, 10, path)
            self.assertGreater(replay.published, 0, path)

    def test_captured_frames_survive_encoding_and_fragmented_parsing(self):
        rng = random.Random(1)
        for path in FIXTURES:
            frames = [(ev[1], ev[2], 0x1000 if ev[3] else 0) for ev in events(path) if ev[0] == "rx"]
            stream = b"".join(ob.encode(msg_id, payload, flags) for msg_id, payload, flags in frames)
            parser = ob.FrameParser()
            out = []
            i = 0
            while i < len(stream):
                n = rng.randint(1, 40)
                out.extend(parser.feed(stream[i:i + n]))
                i += n
            self.assertEqual([(m, p, bool(f)) for m, p, f in frames], out, path)
            self.assertEqual(parser.take_skipped(), 0, path)


def state_after(path, prefix_hex, occurrence=1, model="Buds4 Pro"):
    """Replay `path` up to and including the n-th received frame whose payload
    starts with `prefix_hex`; return the state then."""
    prefix = bytes.fromhex(prefix_hex.replace(" ", ""))
    replay = Replay(model)
    seen = 0
    for ev in events(path):
        replay.feed(ev)
        if ev[0] == "rx" and ev[2].startswith(prefix):
            seen += 1
            if seen == occurrence:
                return replay.state
    raise AssertionError(f"{path}: no frame #{occurrence} starting with {prefix_hex}")


def fixture(n):
    return os.path.join(HERE, "fixtures", f"buds4pro-capture-{n}.log")


class ReplayCheckpointTests(unittest.TestCase):
    """Behaviour pinned from the captures. Each one was a bug seen on the device."""

    def placements(self, s):
        return (s.left["placement"], s.right["placement"])

    def test_case_level_appears_only_while_a_bud_is_docked(self):
        # Capture 1, extended status with the left bud in the case: byte 7 (0x64) is live.
        s = state_after(fixture(1), "04 0d 64 63 01 00 31 64")
        self.assertEqual(self.placements(s), ("case", "wearing"))
        self.assertEqual(s.case["level"], 100)
        # Both worn: the same byte is present but is not a reading.
        s = state_after(fixture(1), "04 0d 64 63 01 01 11 64")
        self.assertEqual(self.placements(s), ("wearing", "wearing"))
        self.assertIsNone(s.case["level"])

    def test_single_bud_moves_arrive_in_noise_controls_frames(self):
        # Capture 3: the right bud goes idle in a short status, then back in the ear
        # announced only by NOISE_CONTROLS_UPDATE `02 11`.
        s = state_after(fixture(3), "01 64 61 01 01 12 64 00")
        self.assertEqual(self.placements(s), ("wearing", "idle"))
        self.assertFalse(s.right["charging"])
        self.assertIsNone(s.case["level"])
        s = state_after(fixture(3), "02 11 01 00 09 09 02 00 02 02 02")
        self.assertEqual(self.placements(s), ("wearing", "wearing"))
        self.assertIsNone(s.case["level"])

    def test_docking_with_charging_bits_reads_the_case(self):
        s = state_after(fixture(3), "01 64 61 01 01 13 64 04")
        self.assertEqual(self.placements(s), ("wearing", "case"))
        self.assertTrue(s.right["charging"])
        self.assertEqual(s.case["level"], 100)
        # Lifted out again in the next short status: no charging, no case reading.
        s = state_after(fixture(3), "01 64 62 01 01 12 64 00")
        self.assertEqual(self.placements(s), ("wearing", "idle"))
        self.assertFalse(s.right["charging"])
        self.assertIsNone(s.case["level"])

    def test_noise_mode_is_never_taken_from_a_placement_frame(self):
        # Capture 2 opens with the extended status reporting mode 0 (off)...
        s = state_after(fixture(2), "04 0d 64 61 01 01 11 00 00 03 ff 22 00")
        self.assertEqual(s.noise_mode, "off")
        # ...and the placement frames that follow say 02 in byte 0. Not the mode.
        s = state_after(fixture(2), "02 12 01 00 09 09 02 00 00 02 02")
        self.assertEqual(s.noise_mode, "off")
        self.assertEqual(self.placements(s), ("wearing", "idle"))
        # Later the extended status reports ambient; the next placement frame says 00.
        s = state_after(fixture(2), "04 0d 64 61 01 01 12 00 00 03 ff 22 02")
        self.assertEqual(s.noise_mode, "ambient")
        s = state_after(fixture(2), "00 11 01 00 09 09 02 00 00 02 02", occurrence=2)
        self.assertEqual(s.noise_mode, "ambient")
        self.assertEqual(self.placements(s), ("wearing", "wearing"))

    def test_link_drop_and_reconnect_reports_fresh_state(self):
        # Capture 1 closes the link when both buds are shut in the case, then reconnects.
        replay = Replay()
        saw_closed = saw_reopen = False
        for ev in events(fixture(1)):
            replay.feed(ev)
            if ev == ("link", "closed"):
                saw_closed = True
                self.assertFalse(replay.state.connected)
            elif saw_closed and ev[0] == "rx" and ev[1] == ob.Msg.EXTENDED_STATUS_UPDATED:
                saw_reopen = True
                self.assertTrue(replay.state.connected)
                self.assertIn(replay.state.left["placement"], ob.PLACEMENTS.values())
        self.assertTrue(saw_closed and saw_reopen)


if __name__ == "__main__":
    unittest.main()
