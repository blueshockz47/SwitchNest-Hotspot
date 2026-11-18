"""Local checks only: no sudo, no host network/service/firewall changes."""
import contextlib
import http.client
import io
import json
from pathlib import Path
import re
import shlex
import subprocess
import threading
import types
import unittest

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / 'install-switchnest-pico-connectivity-v7.1-password.sh'
PANEL = ROOT / 'install-switchnest-plasma67-panel-toggle.sh'


def heredoc(source, tag):
    match = re.search(r"<<'" + re.escape(tag) + r"'\n(.*?)^" + re.escape(tag) + r'$' , source, re.M | re.S)
    if not match:
        raise AssertionError('Missing heredoc: ' + tag)
    return match.group(1)


class SourceChecks(unittest.TestCase):
    def test_bash_syntax(self):
        for path in (INSTALLER, PANEL):
            with self.subTest(path=path.name):
                subprocess.run(['bash', '-n', str(path)], check=True)

    def test_embedded_payloads(self):
        portal = heredoc(INSTALLER.read_text(), 'PORTAL_PY')
        compile(portal, 'connectivity.py', 'exec')
        panel = PANEL.read_text()
        compile(heredoc(panel, 'LAUNCH_CODE'), 'launch.py', 'exec')
        for name in ('ROOT_HELPER_CODE', 'STATUS_CODE'):
            subprocess.run(['bash', '-n'], input=heredoc(panel, name), text=True, check=True)
        metadata = json.loads(heredoc(panel, 'META_CODE'))
        self.assertEqual(metadata['KPackageStructure'], 'Plasma/Applet')
        self.assertEqual(metadata['KPlugin']['Id'], 'local.steamdeck.switch2.offlinehotspot')


class ConnectivityChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = types.ModuleType('offline_test_responder')
        exec(compile(heredoc(INSTALLER.read_text(), 'PORTAL_PY'), 'connectivity.py', 'exec'), cls.module.__dict__)
        # Suppress peer logs during tests; behavior under test is unchanged.
        cls.module.Handler.log_request = lambda self, *args: None
        cls.server = cls.module.Server(('127.0.0.1', 0), cls.module.Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(3)

    def request(self, host, method='GET'):
        conn = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=3)
        try:
            conn.request(method, '/connectivity-test', headers={'Host': host})
            response = conn.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            conn.close()

    def test_all_seven_local_get_responses(self):
        hosts = (self.module.LEGACY_HOST, *sorted(self.module.MODERN_HOSTS))
        self.assertEqual(len(hosts), 7)
        for host in hosts:
            with self.subTest(host=host):
                status, headers, body = self.request(host.upper() + ':80')
                self.assertEqual(status, 200)
                self.assertEqual(headers['X-Organization'], 'Nintendo')
                self.assertEqual(headers['Cache-Control'], 'no-store')
                expected = self.module.LEGACY_BODY if host == self.module.LEGACY_HOST else b'ok'
                self.assertEqual(body, expected)
                self.assertEqual(int(headers['Content-Length']), len(expected))

    def test_head_is_bodyless(self):
        status, headers, body = self.request(self.module.LEGACY_HOST, 'HEAD')
        self.assertEqual(status, 200)
        self.assertEqual(body, b'')
        self.assertEqual(int(headers['Content-Length']), len(self.module.LEGACY_BODY))

    def test_post_matches_get(self):
        status, _, body = self.request('ctest.cdn.nintendo.net', 'POST')
        self.assertEqual((status, body), (200, b'ok'))

    def test_unknown_host_does_not_proxy(self):
        status, _, body = self.request('unrecognized.invalid')
        self.assertEqual((status, body), (404, b''))

    def test_builtin_local_check(self):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.module.check('127.0.0.1', self.server.server_port)
        self.assertEqual(output.getvalue().count('PASS '), 7)


class PasswordChecks(unittest.TestCase):
    def bash(self, code, data=''):
        # Sourcing does not run main, because the installer has a main guard.
        result = subprocess.run(['bash', '-c', 'source "$1"\n' + code, 'test', str(INSTALLER)], input=data, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return result

    def test_valid_password_confirmed_without_echo(self):
        result = self.bash('choose_wifi_security\n[[ $WIFI_SECURITY_CHOICE == wpa2 && $WIFI_SECURITY_PSK == "SyntheticPass!9" ]]', '1\nSyntheticPass!9\nSyntheticPass!9\n')
        self.assertNotIn('SyntheticPass!9', result.stdout + result.stderr)

    def test_short_password_rejected_then_valid(self):
        self.bash('choose_wifi_security\n[[ $WIFI_SECURITY_PSK == "SyntheticPass!9" ]]', '1\nshort\nSyntheticPass!9\nSyntheticPass!9\n')

    def test_mismatch_rejected_then_valid(self):
        self.bash('choose_wifi_security\n[[ $WIFI_SECURITY_PSK == "SyntheticPass!9" ]]', '1\nSyntheticPass!9\nWrongPass!8\nSyntheticPass!9\nSyntheticPass!9\n')

    def test_cancel_does_not_select_security(self):
        self.bash('if choose_wifi_security; then exit 1; fi\n[[ -z $WIFI_SECURITY_CHOICE && -z $WIFI_SECURITY_PSK ]]', '3\n')

    def test_open_selection(self):
        self.bash('choose_wifi_security\n[[ $WIFI_SECURITY_CHOICE == open && -z $WIFI_SECURITY_PSK ]]', '2\n')

    def test_wpa2_uses_rsn_and_profile_secret(self):
        self.bash('''
nmcli(){ CALL=("$@"); }
apply_wifi_security mock-uuid wpa2 SyntheticPass9
[[ ${CALL[0]} == connection && ${CALL[1]} == modify && ${CALL[3]} == mock-uuid ]]
[[ ${CALL[4]} == 802-11-wireless-security.key-mgmt && ${CALL[5]} == wpa-psk ]]
[[ ${CALL[6]} == 802-11-wireless-security.proto && ${CALL[7]} == rsn ]]
[[ ${CALL[8]} == 802-11-wireless-security.psk && ${CALL[9]} == SyntheticPass9 ]]
[[ ${CALL[10]} == 802-11-wireless-security.psk-flags && ${CALL[11]} == 0 ]]
''')

    def test_open_removes_security_setting(self):
        self.bash('''
wifi_security_mode(){ echo wpa2; }
nmcli(){ CALL=("$@"); }
apply_wifi_security mock-uuid open
[[ ${CALL[4]} == remove && ${CALL[5]} == 802-11-wireless-security ]]
''')

    def test_failed_restart_restores_old_mode(self):
        self.bash('''
MODE=open; POWER=on; STARTS=0
# Use the source path so this mocked test never writes an installed manager.
load_config(){ AP_UUID=mock-uuid; RUNNER=''' + shlex.quote(str(INSTALLER)) + '''; }
wifi_security_mode(){ echo "$MODE"; }
choose_wifi_security(){ WIFI_SECURITY_CHOICE=wpa2; WIFI_SECURITY_PSK=SyntheticPass9; }
ask(){ return 0; }
active(){ [[ $POWER == on ]]; }
systemctl(){ case $1 in is-active) [[ $POWER == on ]];; stop) POWER=off;; *) return 1;; esac; }
stop_runtime(){ POWER=off; }
apply_wifi_security(){ MODE=$2; }
turn_on(){ STARTS=$((STARTS+1)); if ((STARTS==1)); then POWER=off; else POWER=on; fi; }
change_wifi_security
[[ $MODE == open && $POWER == on && $STARTS == 2 ]]
''')


if __name__ == '__main__':
    unittest.main()
