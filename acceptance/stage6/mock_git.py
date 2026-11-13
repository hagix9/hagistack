#!/usr/bin/python3 -I
"""Stand-in for git in the harness tests (HS6_GIT, test mode only).

MOCK_GIT_HEAD (default 40 x 'c') is HEAD; MOCK_GIT_DIRTY, if set, is printed as
the status of tracked files; MOCK_GIT_FAIL makes every call fail."""
import os
import sys

args = sys.argv[1:]
if args[:1] == ["-C"]:
    args = args[2:]
if os.environ.get("MOCK_GIT_FAIL"):
    sys.stderr.write("fatal: not a git repository\n")
    sys.exit(128)
if args[:2] == ["rev-parse", "--verify"]:
    print(os.environ.get("MOCK_GIT_HEAD", "c" * 40))
elif args[:1] == ["status"]:
    if os.environ.get("MOCK_GIT_DIRTY"):
        print(os.environ["MOCK_GIT_DIRTY"])
else:
    sys.stderr.write("mock_git: unexpected %s\n" % args)
    sys.exit(2)
