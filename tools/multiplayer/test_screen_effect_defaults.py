import json
import tempfile
import unittest
from pathlib import Path

import friends
import workshop_loadout


class ScreenEffectDefaultsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def load(self, saved=None, *options):
        if saved is not None:
            (self.root / "launcher.json").write_text(json.dumps(saved), encoding="utf-8")
        args = friends.parse_options(["--solo", *options])
        args.profile_root = self.root
        workshop_loadout.load_preferences(args)
        return args.hbao, args.reflections

    def test_fresh_install_turns_both_on(self):
        self.assertEqual((True, True), self.load())

    def test_saved_off_choices_are_kept(self):
        self.assertEqual((False, True), self.load({"hbao": False}))
        self.assertEqual((False, False), self.load({"hbao": False, "reflections": False}))

    def test_command_line_overrides_the_default(self):
        self.assertEqual((False, True), self.load(None, "--no-hbao"))


if __name__ == "__main__":
    unittest.main()
