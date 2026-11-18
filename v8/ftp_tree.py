"""Recursive FTP transfers using the established curl PASV transport."""
import os
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import quote
import ipaddress
import shutil
import re
import time

def valid(name):
    return bool(name and name not in (".", "..") and "/" not in name and
                not any(ord(c)<32 or ord(c)==127 for c in name))

def listing(text):
    result = {}
    for line in text.splitlines():
        if not line.strip() or re.fullmatch(r"total \d+", line.strip()):
            continue
        p = line.split(maxsplit=8)
        if len(p)==9 and p[0].startswith("d") and p[8] in (".",".."):
            continue
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
        self.metric=lambda *args: None
        self.expected_total=0
        self.finished_bytes=0
        self.started=time.monotonic()

    def check(self):
        if self.cancelled():
            raise InterruptedError("Cancelled; remote partial files may remain")

    def run(self, path, args=(), read=False, size=None):
        self.check()
        cmd=self.base.copy()
        if size is not None:
            cmd.remove('--silent')
            cmd+=['--progress-bar']
        if read:
            cmd+=["--retry","2","--retry-connrefused","--retry-delay","1","--max-time","60"]
        with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
            with subprocess.Popen(cmd+list(args)+["--",self.endpoint+quote(path,safe="/")],stdout=out,stderr=err) as p:
                last=0
                while p.poll() is None:
                    if self.cancelled():
                        p.kill()
                        p.wait()
                        self.check()
                    if size is not None and time.monotonic()-last>=.25:
                        last=time.monotonic()
                        # Read with independent file description: do not move curl's write offset.
                        data=os.pread(err.fileno(),8192,max(0,os.fstat(err.fileno()).st_size-8192))
                        matches=re.findall(rb'(\d+(?:\.\d+)?)%',data)
                        if matches:
                            self.emit_metric(int(size*min(100,float(matches[-1]))/100))
                    time.sleep(.05)
                if p.returncode:
                    err.seek(0)
                    raise OSError(err.read().decode(errors="replace")[-500:])
            if size is not None:
                self.finished_bytes+=size
                self.emit_metric(0)
            out.seek(0)
            return out.read().decode("utf-8",errors="strict")

    def emit_metric(self, partial):
        done=self.finished_bytes+partial
        elapsed=max(.1,time.monotonic()-self.started)
        self.metric(done,self.expected_total,int(done/elapsed))

    def prepare(self, direction, local, remote, names, allowed):
        total=0
        count=0
        for name in names:
            self.check()
            if direction=="download":
                n,b=self.properties(remote,name,allowed[name])
                total+=b
                count+=n
            else:
                p=local/name
                files=p.rglob("*") if p.is_dir() else [p]
                for f in files:
                    self.check()
                    if f.is_symlink(): raise ValueError("Symbolic link not supported")
                    if f.is_file():
                        count+=1
                        total+=f.stat().st_size
            if count>100000: raise ValueError("File limit reached")
        self.expected_total=total
        self.started=time.monotonic()
        self.emit_metric(0)

    def entries(self, path):
        return listing(self.run(path,read=True))

    def sizes(self,path):
        result={}
        for line in self.run(path,read=True).splitlines():
            p=line.split(maxsplit=8)
            if len(p)==9 and p[0].startswith("-") and valid(p[8]) and p[4].isdigit():
                result[p[8]]=int(p[4])
        return result

    def properties(self,remote,name,directory,depth=0):
        self.check()
        if depth>64 or not valid(name):
            raise ValueError("Invalid path or depth")
        if not directory:
            size=self.sizes(remote).get(name)
            if size is None:
                raise ValueError("File size unavailable")
            return (1,size)
        count=size=0
        folder=remote+name+"/"
        entries=self.entries(folder)
        sizes=self.sizes(folder)
        for child,isdir in entries.items():
            if isdir:
                n,b=self.properties(folder,child,True,depth+1)
            else:
                if child not in sizes: raise ValueError("File size unavailable")
                n,b=1,sizes[child]
            count+=n
            size+=b
        return count,size

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
            size=source.stat().st_size
            self.run(dest,["--upload-file",str(source)],size=size)
            if self.sizes(remote).get(name)!=size:
                raise OSError("Upload size verification failed: "+dest)
            self.tick(dest,"Verified")

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
            expected=self.sizes(remote).get(name)
            if expected is None:
                raise OSError("Remote size unavailable")
            if expected>shutil.disk_usage(local).free:
                raise OSError("Insufficient local storage")
            fd,tmp=tempfile.mkstemp(prefix=".switchnest-",dir=local)
            os.close(fd)
            try:
                self.run(path,["--output",tmp],size=expected)
                if Path(tmp).stat().st_size!=expected:
                    raise OSError("Download size verification failed")
                if self.policy=="replace":
                    os.replace(tmp,dest)
                else:
                    os.link(tmp,dest)
                self.tick(path,"Verified")
            finally:
                Path(tmp).unlink(missing_ok=True)

    def delete(self, remote, name):
        """Plan the entire tree before issuing any destructive command."""
        plan=[]
        def visit(parent, entry, directory, depth):
            self.check()
            if depth>64 or not valid(entry) or len(plan)>=100000:
                raise ValueError("Unsupported name or tree limit")
            path=parent+entry
            if directory:
                for child,isdir in self.entries(path+"/").items():
                    visit(path+"/",child,isdir,depth+1)
            if len(plan)>=100000: raise ValueError("Tree limit reached")
            plan.append((parent,path,directory))
        entries=self.entries(remote)
        if name not in entries:
            raise ValueError("Entry no longer exists")
        visit(remote,name,entries[name],0)
        for parent,path,directory in plan:
            self.check()
            try:
                self.run(parent,["--quote",("RMD " if directory else "DELE ")+path,"--head","--output",os.devnull])
            except OSError as exc:
                raise OSError(("RMD " if directory else "DELE ")+path+": "+str(exc)) from exc
            self.report(path,"Deleted")

def delete_local(root, cancelled, report):
    plan=[]
    def visit(path,depth):
        if cancelled():
            raise InterruptedError("Deletion cancelled")
        if depth>64 or len(plan)>=100000 or path.is_symlink():
            raise ValueError("Unsupported link or tree limit")
        if path.is_dir():
            for child in path.iterdir():
                visit(child,depth+1)
            plan.append((path,True))
        elif path.is_file():
            plan.append((path,False))
        else:
            raise ValueError("Unsupported file type")
    visit(root,0)
    for path,directory in plan:
        if cancelled():
            raise InterruptedError("Deletion cancelled")
        if path.is_symlink() or any(p.is_symlink() for p in path.parents):
            raise ValueError("Symbolic link encountered")
        if directory:
            path.rmdir()
        else:
            path.unlink()
        report(str(path),"Deleted")
