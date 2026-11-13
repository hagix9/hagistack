#!/usr/bin/python3 -I
"""Stand-in for git in the harness tests (HS6_GIT, test mode only).

MOCK_GIT_HEAD (default 40 x 'c') is HEAD; MOCK_GIT_DIRTY, if set, is printed as
the status of tracked files; MOCK_GIT_FAIL makes every call fail. Every other
call (the harness reads objects with `cat-file --batch`) runs the real
/usr/bin/git in the test's own repository MOCK_GIT_REPO instead of the checkout."""
import os
import sys

args = sys.argv[1:]
repo = None
if args[:1] == ["-C"]:
    repo, args = args[1], args[2:]
if os.environ.get("MOCK_GIT_FAIL"):
    sys.stderr.write("fatal: not a git repository\n")
    sys.exit(128)
if args[:2] == ["rev-parse", "--verify"]:
    print(os.environ.get("MOCK_GIT_HEAD", "c" * 40))
elif args[:1] == ["status"]:
    if os.environ.get("MOCK_GIT_DIRTY"):
        print(os.environ["MOCK_GIT_DIRTY"])
elif os.environ.get("MOCK_GIT_REPO"):
    with open(os.environ.get("MOCK_GIT_LOG", os.devnull), "a") as f:
        f.write(" ".join(args) + "\n")
    os.execv("/usr/bin/git", ["git", "-C", os.environ["MOCK_GIT_REPO"]] + args)
else:
    sys.stderr.write("mock_git: unexpected %s (no MOCK_GIT_REPO)\n" % args)
    sys.exit(2)
