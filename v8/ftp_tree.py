"""Recursive FTP transfers using the established curl PASV transport."""
import os
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import quote
import ipaddress
import shutil
import re

def valid(name):
    return bool(name and name not in (".", "..") and "/" not in name and
                not any(ord(c)<32 or ord(c)==127 for c in name))

def listing(text):
    result = {}
    for line in text.splitlines():
        if not line.strip() or re.fullmatch(r"total \d+", line.strip()):
            continue
        p = line.split(maxsplit=8)
        if len(p)!=9 or not valid(p[8]):
            raise ValueError("Unsupported directory entry: "+line[:100])
        if p[0][0] not in "d-":
            raise ValueError("Unsupported file type: "+p[8])
        result[p[8]] = p[0][0]=="d"
    return result

class Tree:
    def __init__(self, host, port, policy, cancelled, report):
        ip=ipaddress.IPv4Address(host)
        if ip not in ipaddress.IPv4Network("10.42.60.0/24") or int(ip)%256 in (0,1,255) or not 1<=int(port)<=65535:
            raise ValueError("Invalid local FTP endpoint")
        if policy not in ("skip","replace","rename"):
            raise ValueError("Invalid conflict policy")
        self.base=["curl","-q","--globoff","--noproxy","*","--proto","=ftp","--disable-epsv","--ftp-skip-pasv-ip","--connect-timeout","8","--speed-limit","1","--speed-time","30","--silent","--show-error"]
        self.endpoint=f"ftp://{ip}:{int(port)}"
        self.policy=policy
        self.cancelled=cancelled
        self.report=report
        self.count=0

    def check(self):
        if self.cancelled():
            raise InterruptedError("Cancelled; remote partial files may remain")

    def run(self, path, args=(), read=False):
        self.check()
        cmd=self.base.copy()
        if read:
            cmd+=["--retry","2","--retry-connrefused","--retry-delay","1","--max-time","60"]
        with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
            with subprocess.Popen(cmd+list(args)+["--",self.endpoint+quote(path,safe="/")],stdout=out,stderr=err) as p:
                import time
                while p.poll() is None:
                    if self.cancelled():
                        p.kill()
                        p.wait()
                        self.check()
                    time.sleep(.1)
                if p.returncode:
                    err.seek(0)
                    raise OSError(err.read().decode(errors="replace")[-500:])
            out.seek(0)
            return out.read().decode("utf-8",errors="strict")

    def entries(self, path):
        return listing(self.run(path,read=True))

    def choose(self, name, existing, directory):
        if name not in existing:
            return name
        if self.policy=="skip":
            return None
        if self.policy=="replace":
            if existing[name]!=directory:
                raise ValueError("File/folder conflict: "+name)
            return name
        stem,ext=os.path.splitext(name) if not directory else (name,"")
        for i in range(1,10001):
            new=f"{stem} ({i}){ext}"
            if new not in existing:
                return new
        raise ValueError("Too many name conflicts")

    def tick(self, name, status):
        self.count+=1
        if self.count>100000:
            raise ValueError("Transfer entry limit reached")
        self.report(name,status)

    def upload(self, source, remote, depth=0):
        self.check()
        if depth>64 or source.is_symlink() or not valid(source.name):
            raise ValueError("Unsupported source or directory depth")
        directory=source.is_dir()
        if not directory and not source.is_file():
            raise ValueError("Unsupported local file")
        existing=self.entries(remote)
        name=self.choose(source.name,existing,directory)
        if name is None:
            self.tick(source.name,"Skipped"); return
        dest=remote+name
        if directory:
            if name not in existing:
                self.run(remote,["--quote","MKD "+dest,"--output",os.devnull])
            self.tick(dest,"Folder")
            for child in sorted(source.iterdir()):
                self.upload(child,dest+"/",depth+1)
        else:
            self.run(dest,["--upload-file",str(source)])
            self.tick(dest,"Completed")

    def download(self, remote, name, local, directory, depth=0):
        self.check()
        if depth>64 or not valid(name) or local.is_symlink():
            raise ValueError("Unsupported destination or directory depth")
        existing={p.name:p.is_dir() for p in local.iterdir()}
        target=self.choose(name,existing,directory)
        if target is None:
            self.tick(name,"Skipped"); return
        dest=local/target
        if dest.is_symlink():
            raise ValueError("Symbolic link destination")
        path=remote+name
        if directory:
            dest.mkdir(exist_ok=True)
            self.tick(path,"Folder")
            for child,isdir in self.entries(path+"/").items():
                self.download(path+"/",child,dest,isdir,depth+1)
        else:
            fd,tmp=tempfile.mkstemp(prefix=".switchnest-",dir=local)
            os.close(fd)
            try:
                self.run(path,["--output",tmp])
                if self.policy=="replace":
                    os.replace(tmp,dest)
                else:
                    os.link(tmp,dest)
                self.tick(path,"Completed")
            finally:
                Path(tmp).unlink(missing_ok=True)
