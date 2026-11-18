import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from v8 import install

class InstallerTests(unittest.TestCase):
    def test_release_switch(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            releases=root/"releases"
            for name in ("old","new"):
                p=releases/name/"v8"
                p.mkdir(parents=True)
                (p/"control_center.py").touch()
            with patch.object(install,"ROOT",root):
                self.assertIsNone(install.current("current"))
                install.point("current",releases/"old")
                install.point("previous",install.current("current"))
                install.point("current",releases/"new")
                self.assertEqual(install.current("current"),releases/"new")
                self.assertEqual(install.current("previous"),releases/"old")

    def test_reject_outside_release(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            (root/"current").symlink_to(root)
            with patch.object(install,"ROOT",root):
                with self.assertRaises(RuntimeError):
                    install.current("current")

if __name__=="__main__":
    unittest.main()
