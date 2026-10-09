import unittest

import join_code


def details(password):
    return dict(address="203.0.113.7", password=password, port=7777, query_port=27015,
                build="0.1.0-alpha-test", mods=[], map="KF-Prison")


class OpenServerJoinCodeTest(unittest.TestCase):
    def test_no_password_round_trips(self):
        code = join_code.encode(details(""))
        self.assertEqual(join_code.decode(code, "0.1.0-alpha-test")["password"], "")

    def test_password_still_round_trips(self):
        code = join_code.encode(details("12345vr"))
        self.assertEqual(join_code.decode(code, "0.1.0-alpha-test")["password"], "12345vr")

    def test_password_characters_stay_bounded(self):
        for bad in ("pass word", "a?b", "x" * 65):
            with self.assertRaises(ValueError):
                join_code.encode(details(bad))


if __name__ == "__main__":
    unittest.main()
