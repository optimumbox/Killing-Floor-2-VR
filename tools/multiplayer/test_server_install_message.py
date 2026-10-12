import unittest

import friends


class ServerInstallMessageTest(unittest.TestCase):
    def test_full_disk_reason_is_shown_plainly(self):
        output = ("C:\\app\\tools\\install-multiplayer-server.ps1 : Not enough free disk space to install the KF2 "
                  "dedicated server: it needs about 35 GB\r\n    on C:\\ and only 4 GB is free. Free up space on C:\\ "
                  "and try again.\r\nAt line:1 char:1\r\n")
        self.assertEqual("Not enough free disk space to install the KF2 dedicated server: it needs about 35 GB "
                         "on C:\\ and only 4 GB is free. Free up space on C:\\ and try again.",
                         friends.server_install_failure(output, 1))

    def test_out_of_space_during_download(self):
        output = "x : The disk ran out of space while installing the KF2 dedicated server (C:\\). Free up space and try again."
        self.assertTrue(friends.server_install_failure(output, 1).startswith("The disk ran out of space"))

    def test_other_failures_keep_the_exit_code(self):
        self.assertIn("exit 3", friends.server_install_failure("something else", 3))


if __name__ == "__main__":
    unittest.main()
