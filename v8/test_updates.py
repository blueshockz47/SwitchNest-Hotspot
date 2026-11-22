import unittest
from v8.updates import version_key, release_url

class UpdateTests(unittest.TestCase):
    def test_order(self):
        tags=["8.0-alpha.9","8.0-alpha.10","8.0-beta.1","8.0-RC.1","8.0-RC.2","8.0","8.0.1"]
        self.assertEqual(sorted(tags,key=version_key),tags)
    def test_invalid(self):
        with self.assertRaises(ValueError): version_key("development/v8.0")
    def test_release_url(self):
        self.assertEqual(release_url("v8.0.3"), "https://github.com/blueshockz47/SwitchNest-Hotspot/releases/tag/v8.0.3")
        with self.assertRaises(ValueError): release_url("../../unsafe")

    def test_stable_final_release_tag(self):
        self.assertEqual(version_key("8.1.7-Stable-Final"), version_key("v8.1.7"))
        self.assertGreater(version_key("8.1.7-Stable-Final"), version_key("8.1.6"))
        self.assertEqual(release_url("8.1.7-Stable-Final"), "https://github.com/blueshockz47/SwitchNest-Hotspot/releases/tag/8.1.7-Stable-Final")

    def test_prefix(self):
        self.assertEqual(version_key("v8.0-rc.2"),version_key("8.0-RC.2"))
