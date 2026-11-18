import unittest
from v8.mode_model import Mode, Evidence, evaluate

class ModeTests(unittest.TestCase):
    def test_inactive(self):
        self.assertEqual(evaluate(Mode.OFFLINE, Evidence())["effective"], "inactive")

    def test_default_offline(self):
        e = Evidence(True, True, True, True, True, True)
        self.assertEqual(evaluate(Mode.FILTERED, e)["effective"], "offline")

    def test_unverified_guard(self):
        self.assertEqual(evaluate(Mode.OFFLINE, Evidence(True))["action"],
                         "block_forwarding_or_stop_hotspot")

    def test_verified_offline(self):
        self.assertEqual(evaluate(Mode.OFFLINE, Evidence(True, True, True))["effective"], "offline")

    def test_failed_dns(self):
        self.assertEqual(evaluate(Mode.FILTERED, Evidence(True, True), experimental_enabled=True)["effective"], "unverified")

    def test_filtered_requires_all_evidence(self):
        for i in range(2, 6):
            values = [True] * 6
            values[i] = False
            self.assertNotEqual(evaluate(Mode.FILTERED, Evidence(*values), experimental_enabled=True)["effective"], "filtered")

    def test_filtered_verified_model_only(self):
        self.assertEqual(evaluate(Mode.FILTERED, Evidence(True, True, True, True, True, True), experimental_enabled=True)["effective"], "filtered")
