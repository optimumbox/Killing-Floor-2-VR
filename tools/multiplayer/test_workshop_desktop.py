import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from session import read_ini
from workshop_loadout import KF2VR_WORKSHOP_ID, configure_content

ENGINE = "[Core.System]\r\nPaths=..\\KFGame\\BrewedPC\r\n[IpDrv.TcpNetDriver]\r\nDownloadManagers=Engine.ChannelDownload\r\n"


class WorkshopDesktopTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.configs = Path(self.temp.name)
        (self.configs / "KFEngine.ini").write_text(ENGINE, encoding="utf-16")

    def tearDown(self):
        self.temp.cleanup()

    def engine(self):
        return read_ini(self.configs / "KFEngine.ini")

    def test_host_offers_the_mod_item_without_other_content(self):
        configure_content(self.configs, SimpleNamespace(workshop_content=[], workshop_desktop=True), server=True)
        text = self.engine()
        self.assertIn("[OnlineSubsystemSteamworks.KFWorkshopSteamworks]", text)
        self.assertIn("ServerSubscribedWorkshopItems=" + KF2VR_WORKSHOP_ID, text)
        self.assertLess(text.index("DownloadManagers=OnlineSubsystemSteamworks.SteamWorkshopDownload"),
                        text.index("DownloadManagers=Engine.ChannelDownload"))
        self.assertEqual(text.count("Paths="), 1)

    def test_mod_item_follows_selected_mods(self):
        root = self.configs / "ukfp"
        content = [{"workshop_id": "2875147606", "root": str(root), "files_sha256": {"BrewedPC/UnofficialKFPatch.u": "0"}}]
        configure_content(self.configs, SimpleNamespace(workshop_content=content, workshop_desktop=True), server=True)
        text = self.engine()
        self.assertLess(text.index("ServerSubscribedWorkshopItems=2875147606"),
                        text.index("ServerSubscribedWorkshopItems=" + KF2VR_WORKSHOP_ID))

    def managers(self):
        return [line.split("=", 1)[1] for line in self.engine().splitlines() if line.startswith("DownloadManagers=")]

    def test_workshop_stays_first(self):
        configure_content(self.configs, SimpleNamespace(workshop_content=[], workshop_desktop=True), server=True)
        self.assertEqual(self.managers(), ["OnlineSubsystemSteamworks.SteamWorkshopDownload", "Engine.ChannelDownload"])

    def test_off_or_client_leaves_config_alone(self):
        configure_content(self.configs, SimpleNamespace(workshop_content=[], workshop_desktop=False), server=True)
        configure_content(self.configs, SimpleNamespace(workshop_content=[], workshop_desktop=True), server=False)
        self.assertEqual(self.engine().replace("\r\n", "\n"), ENGINE.replace("\r\n", "\n"))


if __name__ == "__main__":
    unittest.main()
