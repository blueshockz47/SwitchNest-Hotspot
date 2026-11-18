import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from v8 import autostart

class AutostartTests(unittest.TestCase):
    def test_toggle(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"autostart"/"switchnest.desktop"
            launch=Path(d)/"launch"
            launch.touch()
            launch.chmod(0o700)
            with patch.object(autostart,"entry",return_value=p),patch.object(autostart,"launcher",return_value=launch):
                self.assertFalse(autostart.enabled())
                autostart.set_enabled(True)
                self.assertTrue(autostart.enabled())
                autostart.set_enabled(False)
                self.assertFalse(p.exists())
    def test_missing_launcher(self):
        with tempfile.TemporaryDirectory() as d:
            with patch.object(autostart,"launcher",return_value=Path(d)/"missing"):
                with self.assertRaises(RuntimeError): autostart.set_enabled(True)
