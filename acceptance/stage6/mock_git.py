#!/usr/bin/python3 -I
"""Stand-in for git in the harness tests (HS6_GIT, test mode only).

MOCK_GIT_HEAD (default 40 x 'c') is HEAD; MOCK_GIT_DIRTY, if set, is printed as
the status of tracked files; MOCK_GIT_FAIL makes every call fail.
`show COMMIT:acceptance/stage6/run-plan.json` prints the file MOCK_GIT_PLAN
(missing: fails as git does for a path not in the commit). `archive ... -o FILE
COMMIT -- PATHS` writes a small stand-in archive naming the commit and paths."""
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
elif args[:1] == ["show"] and len(args) == 2:
    commit, _, path = args[1].partition(":")
    plan = os.environ.get("MOCK_GIT_PLAN")
    if path != "acceptance/stage6/run-plan.json" or not plan or not os.path.isfile(plan):
        sys.stderr.write("fatal: path '%s' does not exist in '%s'\n" % (path, commit))
        sys.exit(128)
    with open(plan, "rb") as f:
        sys.stdout.buffer.write(f.read())
elif args[:2] == ["archive", "--format=tar"] and args[2] == "-o" and "--" in args:
    out, commit = args[3], args[4]
    paths = args[args.index("--") + 1:]
    with open(out, "wb") as f:
        f.write(("mock tree %s %s\n" % (commit, " ".join(paths))).encode())
    with open(os.environ.get("MOCK_GIT_LOG", os.devnull), "a") as f:
        f.write("archive %s %s\n" % (commit, " ".join(paths)))
else:
    sys.stderr.write("mock_git: unexpected %s\n" % args)
    sys.exit(2)
