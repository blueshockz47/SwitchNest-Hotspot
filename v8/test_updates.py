import unittest
from v8.updates import version_key

class UpdateTests(unittest.TestCase):
    def test_order(self):
        tags=["8.0-alpha.9","8.0-alpha.10","8.0-beta.1","8.0-RC.1","8.0-RC.2","8.0","8.0.1"]
        self.assertEqual(sorted(tags,key=version_key),tags)
    def test_invalid(self):
        with self.assertRaises(ValueError): version_key("development/v8.0")
    def test_prefix(self):
        self.assertEqual(version_key("v8.0-rc.2"),version_key("8.0-RC.2"))
