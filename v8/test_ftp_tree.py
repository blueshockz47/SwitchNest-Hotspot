import tempfile
import unittest
from pathlib import Path
from v8.ftp_tree import Tree, listing, valid, delete_local

class TreeTests(unittest.TestCase):
    def tree(self, policy="skip"):
        return Tree("10.42.60.99",1337,policy,lambda:False,lambda *args:None)

    def test_names(self):
        for name in ("", ".", "..", "a/b", "a\nDELE x"):
            self.assertFalse(valid(name))
        self.assertTrue(valid("file with spaces.txt"))

    def test_listing(self):
        self.assertEqual(listing("total 2\ndrwxrwxrwx 1 u g 0 Jan 1 1970 .\n-rw-rw-rw- 1 u g 2 Jan 1 1970 a b"),{"a b":False})
        with self.assertRaises(ValueError):
            listing("lrwxrwxrwx 1 u g 0 Jan 1 1970 link")

    def test_endpoint(self):
        for address in ("8.8.8.8","10.42.60.1","10.42.60.255"):
            with self.assertRaises(ValueError):
                Tree(address,1337,"skip",lambda:False,lambda *a:None)

    def test_conflicts(self):
        self.assertIsNone(self.tree().choose("a",{"a":False},False))
        self.assertEqual(self.tree("rename").choose("a.txt",{"a.txt":False},False),"a (1).txt")
        with self.assertRaises(ValueError):
            self.tree("replace").choose("a",{"a":True},False)

    def test_local_recursive_delete(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/"folder"
            (root/"nested").mkdir(parents=True)
            (root/"nested"/"a").write_bytes(b"data")
            sibling=Path(d)/"keep"
            sibling.touch()
            delete_local(root,lambda:False,lambda *a:None)
            self.assertFalse(root.exists())
            self.assertTrue(sibling.exists())

    def test_cancel_and_symlink(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)/"folder"
            root.mkdir()
            (root/"a").touch()
            with self.assertRaises(InterruptedError):
                delete_local(root,lambda:True,lambda *a:None)
            (root/"link").symlink_to(root/"a")
            with self.assertRaises(ValueError):
                delete_local(root,lambda:False,lambda *a:None)
            self.assertTrue((root/"a").exists())

    def test_remote_delete_order(self):
        tree=self.tree()
        tree.entries=lambda path: {"/":{"folder":True},"/folder/":{"nested":True,"b":False},"/folder/nested/":{"a":False}}[path]
        calls=[]
        tree.run=lambda path,args: calls.append(args[1])
        tree.delete("/","folder")
        self.assertEqual(calls,["DELE /folder/nested/a","RMD /folder/nested","DELE /folder/b","RMD /folder"])

    def test_remote_preflight_failure(self):
        tree=self.tree()
        tree.entries=lambda path: {"/":{"folder":True},"/folder/":{"..":True}}[path]
        calls=[]
        tree.run=lambda *a: calls.append(a)
        with self.assertRaises(ValueError):
            tree.delete("/","folder")
        self.assertEqual(calls,[])

if __name__=="__main__":
    unittest.main()
