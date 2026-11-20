"""Small, isolated SwitchNest FTP ZIP installer acceptance test.

No network writes unless --install --confirm are both supplied.
First pass can cancel after the first verified upload. Re-run to resume.
All remote files live beneath /switch/switchnest-ftp-test-v810/.
"""
import argparse
import hashlib
from pathlib import Path
import tempfile
import threading
import zipfile

from v8 import homebrew_zip

FOLDER = "switch/switchnest-ftp-test-v810"
PAYLOADS = {
    FOLDER + "/01-readme.txt": b"SwitchNest FTP test only. Safe to delete.\\n",
    FOLDER + "/02-data.bin": bytes(range(256)) * 128,
    FOLDER + "/03-data.bin": bytes(range(256)) * 256,
}

def build(path):
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for name, data in PAYLOADS.items():
            z.writestr(name, data)
    return homebrew_zip.inspect_zip(path)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install", action="store_true", help="Upload to Switch 2 via FTP")
    parser.add_argument("--confirm", action="store_true", help="Explicitly authorize FTP writes")
    parser.add_argument("--host", default="10.42.60.99", help="Connected Switch 2 FTP IPv4")
    parser.add_argument("--port", type=int, default=1337, help="Switch 2 FTP port")
    parser.add_argument("--cancel-after-first", action="store_true",
                        help="Cancel after the first completed file; rerun to resume")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="switchnest-ftp-test-") as temp:
        archive = Path(temp) / "switchnest-ftp-test.zip"
        plan = build(archive)
        print("Test archive:", plan["count"], "files,", plan["bytes"], "bytes")
        print("Destinations:", *plan["sample"], sep="\\n  ")
        if not args.install:
            print("PREVIEW ONLY. No FTP operations performed.")
            return
        if not args.confirm:
            parser.error("Installation requires both --install and --confirm")
        event = threading.Event()
        def report(done, total, index, count, name, status):
            print(f"{done}/{total} bytes | {index}/{count} | {status}: {name}", flush=True)
            if args.cancel_after_first and index == 1 and status in (
                    "Uploaded and size-verified", "Verified existing file"):
                event.set()
        try:
            print("FTP destination: /" + FOLDER + "/")
            result = homebrew_zip.install_zip(
                archive, plan, args.host, args.port, confirmed=True,
                progress=report, cancelled=event.is_set)
            print("SUCCESS:", result)
            print("You may delete /" + FOLDER + "/ using the FTP File Manager.")
        except InterruptedError as exc:
            print("EXPECTED CANCELLATION:", exc)
            print("Rerun without --cancel-after-first to verify and resume.")
        except Exception as exc:
            print("FAILED:", type(exc).__name__, str(exc))
            raise

if __name__ == "__main__":
    main()
