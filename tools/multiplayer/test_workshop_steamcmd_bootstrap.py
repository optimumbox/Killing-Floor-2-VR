import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import dependencies
import workshop_loadout


class SteamCmdBootstrapTest(unittest.TestCase):
    def test_fresh_copy_fetches_steamcmd_before_downloading_an_item(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            game = root / "steamapps/common/killingfloor2"
            game.mkdir(parents=True)
            steam = root / "steamcmd"
            fetched = []

            def fake_extract(name, archive, destination):
                fetched.append(name)
                (Path(destination) / "steamcmd.exe").write_text("")

            def fake_run(command, **kwargs):
                raise RuntimeError("download attempted")

            with patch.object(dependencies, "extract_verified", fake_extract), \
                    patch.object(workshop_loadout.subprocess, "run", fake_run):
                with self.assertRaisesRegex(RuntimeError, "download attempted"):
                    workshop_loadout.ensure_item("643383080", game, root / "cache", steam, download=True)
            self.assertEqual(["steamcmd.zip"], fetched)


if __name__ == "__main__":
    unittest.main()
