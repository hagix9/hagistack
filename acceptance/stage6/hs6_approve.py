#!/usr/bin/env python3
"""hs6_approve.py — the Owner approves one stage 6 GCE run by signing it.

Run it yourself, in your own terminal. It shows the exact conditions, asks you
to type the run id, and signs the approval with your SSH key (your passphrase or
your security-key touch). The AI agent cannot do that step: it does not have the
passphrase or the key, and this tool refuses to run without a terminal.

    One time:  python3 -I hs6_approve.py --setup [--sk]
    Each run:  python3 -I hs6_approve.py --run-id RID --ops init,network,n2,ssh,upload,teardown,residual
    Cleanup :  python3 -I hs6_approve.py --run-id RID --ops teardown,residual   (a used run id)

Writes ~/hagistack-approvals/<RID>.json and <RID>.json.sig. hs6.py executes
nothing without a valid signature by a key pinned in hs6.OWNER_SIGNING_KEYS.
Python 3.9+, standard library only. Network: only `gcloud config get-value account`.
"""
import sys

# First, before any other import: without -I, Python would import modules planted
# next to this file (an ignored json.pyc, for example) at the next import line.
# sys is built in and cannot be replaced that way.
if __name__ == "__main__" and not sys.flags.isolated:
    sys.stderr.write("REFUSED: run it as: python3 -I %s ...\n" % sys.argv[0].rsplit("/", 1)[-1])
    sys.exit(2)

import argparse  # noqa: E402
import datetime  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import re  # noqa: E402
import secrets  # noqa: E402
import shutil  # noqa: E402
import subprocess  # noqa: E402
import types  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
HS6_PATH = os.path.join(HERE, "hs6.py")


def _load_hs6():
    """hs6.py from its source text, never from a cached .pyc: what is checked in
    git is what this tool trusts (a planted .pyc could carry other keys)."""
    with open(HS6_PATH, "rb") as f:
        src = f.read()
    mod = types.ModuleType("hs6_from_source")
    mod.__file__ = HS6_PATH
    exec(compile(src, HS6_PATH, "exec"), mod.__dict__)
    return mod


sys.dont_write_bytecode = True
hs6 = _load_hs6()
GIT = "/usr/bin/git"
SSH_ADD = "/usr/bin/ssh-add"

DEFAULT_KEY = os.path.expanduser("~/.ssh/hagistack-owner-approval")
APPROVAL_DIR = os.path.expanduser("~/hagistack-approvals")
AGENT_ENV = ("CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CODEX_SANDBOX", "CODEX_HOME")


class Refused(Exception):
    pass


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def build_approval(rid, ops, budget, max_hours, valid_hours, account, harness_sha, now, nonce, commit):
    """The approval document. Pure: the tests call it to build what the Owner would sign."""
    if not hs6.RUN_ID_RE.fullmatch(rid or ""):
        raise Refused("run id must match %s" % hs6.RUN_ID_RE.pattern)
    if not ops or any(o not in hs6.OPERATIONS for o in ops) or len(set(ops)) != len(ops):
        raise Refused("operations must be distinct names from %s" % ", ".join(hs6.OPERATIONS))
    if "teardown" not in ops:
        raise Refused("operations must include teardown, so the run can always be cleaned up")
    if not (0 < budget <= hs6.COST_STOP_ALL):
        raise Refused("budget must be more than 0 and at most US$%.0f" % hs6.COST_STOP_ALL)
    if not (0 < max_hours <= hs6.MAX_HOURS):
        raise Refused("max hours must be more than 0 and at most %.0f" % hs6.MAX_HOURS)
    if not (0 < valid_hours <= hs6.MAX_APPROVAL_HOURS):
        raise Refused("validity must be more than 0 and at most %.0f hours" % hs6.MAX_APPROVAL_HOURS)
    if not isinstance(account, str) or "@" not in account:
        raise Refused("no gcloud account is configured")
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise Refused("the commit to approve must be a full commit id")
    return {
        "format": hs6.APPROVAL_FORMAT, "run_id": rid, "project": hs6.PROJECT, "zone": hs6.ZONE,
        "account": account, "owner_statement": hs6.owner_statement(rid), "harness_sha256": harness_sha,
        "commit": commit,
        "operations": list(ops), "budget_usd": budget, "max_hours": max_hours,
        "approved_at": iso(now), "expires_at": iso(now + datetime.timedelta(hours=valid_hours)),
        "nonce": nonce, "signed_with": "hs6_approve.py (ssh-keygen -Y sign, namespace %s)" % hs6.SIG_NAMESPACE,
    }


def run(cmd, **kw):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60, **kw)
    except (OSError, subprocess.SubprocessError) as e:
        raise Refused("could not run %s: %s" % (cmd[0], e))


def need_terminal():
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        raise Refused("run this yourself in a terminal (it needs your typed confirmation)")
    hit = [k for k in AGENT_ENV if os.environ.get(k)]
    if hit:
        raise Refused("this looks like an AI agent's shell (%s is set): run it in your own terminal" % ", ".join(hit))


def pub_line(key):
    try:
        with open(key + ".pub") as f:
            parts = f.read().split()
    except OSError:
        raise Refused("public key %s.pub not found (run --setup first)" % key)
    return " ".join(parts[:2])


def key_in_agent(pub):
    if not os.environ.get("SSH_AUTH_SOCK"):
        return False
    if not os.path.exists(SSH_ADD):
        raise Refused("an ssh-agent is running but %s is missing, so the agent cannot be checked" % SSH_ADD)
    p = run([SSH_ADD, "-L"])
    return bool(p and p.returncode == 0 and any(" ".join(l.split()[:2]) == pub for l in p.stdout.splitlines()))


def harness_state():
    """The whole stage 6 directory (hs6.py, this tool, the mock and the tests) must
    be committed and unchanged, so you approve code that can be reviewed."""
    repo = run([GIT, "-C", HERE, "rev-parse", "--show-toplevel"])
    if repo.returncode != 0:
        raise Refused("hs6.py is not in a git checkout")
    top = repo.stdout.strip()
    rel = os.path.relpath(HERE, top)
    for f in ("hs6.py", "hs6_approve.py"):
        if run([GIT, "-C", top, "ls-files", "--error-unmatch", os.path.join(rel, f)]).returncode != 0:
            raise Refused("%s is not committed" % f)
    st = run([GIT, "-C", top, "status", "--porcelain", "--untracked-files=all", "--ignored", "--", rel])
    if st.returncode != 0 or st.stdout.strip():
        raise Refused("%s has uncommitted or untracked changes: approve only committed code\n%s"
                      % (rel, st.stdout.strip()))
    # The run is bound to one commit: the whole checkout must have no change to a
    # tracked file (untracked files are allowed), so the commit is what runs.
    tracked = run([GIT, "-C", top, "status", "--porcelain", "--untracked-files=no"])
    if tracked.returncode != 0 or tracked.stdout.strip():
        raise Refused("the checkout has changes to tracked files: commit or drop them first\n%s"
                      % tracked.stdout.strip())
    head = run([GIT, "-C", top, "rev-parse", "--verify", "HEAD"]).stdout.strip()
    subject = run([GIT, "-C", top, "log", "-1", "--format=%s", head]).stdout.strip()
    return head, subject, top


def key_outside(key, top):
    """The private key must never be inside the repository (it could be committed)."""
    k = os.path.realpath(key)
    if k == top or k.startswith(top.rstrip(os.sep) + os.sep):
        raise Refused("the key %s is inside the repository %s: keep it outside (default %s)" % (key, top, DEFAULT_KEY))


def pinned_ok(pub, pinned):
    """The harness must trust your key and only your key."""
    keys = {" ".join(k.split()[:2]) for k in pinned}
    if pub not in keys:
        raise Refused("hs6.py does not trust this key (it is not in OWNER_SIGNING_KEYS). If you did not "
                      "change that list, someone else did: do not approve, and check the git history")
    if keys != {pub}:
        raise Refused("hs6.py also trusts %d other key(s) in OWNER_SIGNING_KEYS. Only your key may be "
                      "there: do not approve, and check the git history" % (len(keys) - 1))


def setup(args):
    need_terminal()
    key = os.path.expanduser(args.key)
    top = run([GIT, "-C", HERE, "rev-parse", "--show-toplevel"])
    if top.returncode == 0:
        key_outside(key, os.path.realpath(top.stdout.strip()))
    if os.path.exists(key):
        raise Refused("%s already exists; it is kept. Use it, or choose another --key" % key)
    os.makedirs(os.path.dirname(key), mode=0o700, exist_ok=True)
    kind = "ed25519-sk" if args.sk else "ed25519"
    print("Creating your approval key %s (%s)." % (key, kind))
    print("Choose a passphrase you do not tell anyone, including the AI agent.")
    if subprocess.run([hs6.ssh_keygen(), "-t", kind, "-a", "100", "-C", "hagistack-owner-approval", "-f", key]).returncode:
        raise Refused("ssh-keygen failed")
    if not args.sk and run([hs6.ssh_keygen(), "-y", "-P", "", "-f", key]).returncode == 0:
        os.replace(key, key + ".no-passphrase")
        raise Refused("the key has no passphrase, so anyone with your account could sign. It was moved to "
                      "%s.no-passphrase; delete it and run --setup again with a passphrase" % key)
    print()
    print("Done. Give the AI agent this public key line to pin in hs6.py (OWNER_SIGNING_KEYS):")
    print()
    print("    " + pub_line(key))
    print()
    print("Do not add the key to ssh-agent or the macOS keychain: then signing would need no passphrase.")
    return 0


def approve(args):
    need_terminal()
    key = os.path.expanduser(args.key)
    pub = pub_line(key)
    pinned_ok(pub, hs6.OWNER_SIGNING_KEYS)
    if key_in_agent(pub):
        raise Refused("your approval key is loaded in ssh-agent, so it could sign without you. Remove it "
                      "(ssh-add -d %s.pub) and run this again" % key)
    head, subject, top = harness_state()
    key_outside(key, top)
    ops = [o.strip() for o in args.ops.split(",") if o.strip()]
    used = os.path.join(hs6.registry_dir(), "used-run-ids")
    if os.path.exists(used) and args.run_id in open(used).read().split() \
            and not set(ops) <= set(hs6.CLEANUP_OPS):
        raise Refused("run id %s was used before. Choose a new one, or approve only its cleanup "
                      "(--ops teardown,residual)" % args.run_id)
    gcloud = shutil.which("gcloud")
    if not gcloud:
        raise Refused("gcloud is not on PATH; the approval must name the gcloud account")
    acct = run([gcloud, "config", "get-value", "account"]).stdout.strip()
    now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
    doc = build_approval(args.run_id, ops, args.budget, args.max_hours, args.valid_hours, acct,
                         hs6.harness_sha256(), now, secrets.token_hex(16), head)
    nodes = [o for o in ops if o in hs6.NODES]
    print()
    print("You are approving these GCE operations / 次の GCE 操作を承認します")
    print("  run id      : %s" % doc["run_id"])
    print("  project/zone: %s / %s" % (doc["project"], doc["zone"]))
    print("  account     : %s" % doc["account"])
    print("  operations  : %s" % ", ".join(ops))
    print("  nodes       : %s" % (", ".join("%s (%s, %s GB)" % (n, hs6.NODES[n][0], hs6.NODES[n][2]) for n in nodes) or "none"))
    print("  limits      : US$%s, %s h from the first creation (then automatic teardown)" % (doc["budget_usd"], doc["max_hours"]))
    print("  valid       : %s to %s (UTC)" % (doc["approved_at"], doc["expires_at"]))
    print("  commit      : %s (%s)" % (doc["commit"], subject))
    print("  harness     : hs6.py %s" % doc["harness_sha256"][:16])
    print()
    typed = input("To approve, type the run id (anything else cancels) / 承認する場合は run ID を入力: ").strip()
    if typed != args.run_id:
        print("Cancelled. Nothing was written.")
        return 1
    os.makedirs(APPROVAL_DIR, mode=0o700, exist_ok=True)
    out = os.path.join(APPROVAL_DIR, "%s.json" % args.run_id)
    for p in (out, out + ".sig"):
        if os.path.lexists(p):
            raise Refused("%s already exists; an approval is never overwritten" % p)
    data = (json.dumps(doc, indent=1, ensure_ascii=False) + "\n").encode()
    fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    print("Signing (enter your key's passphrase, or touch your security key) / 署名します")
    done = False
    try:
        if subprocess.run([hs6.ssh_keygen(), "-Y", "sign", "-f", key, "-n", hs6.SIG_NAMESPACE, out]).returncode:
            raise Refused("signing failed; nothing is approved")
        os.chmod(out + ".sig", 0o600)
        with open(out + ".sig", "rb") as f:
            hs6.verify_owner_signature(data, f.read())
        done = True
    except hs6.Stop as e:
        raise Refused("the harness does not accept the signature: %s" % e)
    finally:
        if not done:   # nothing half-made is left behind
            for p in (out, out + ".sig"):
                if os.path.lexists(p):
                    os.unlink(p)
    print()
    print("Approved and signed: %s (+ .sig), sha256 %s" % (out, hashlib.sha256(data).hexdigest()[:16]))
    print("Tell the AI agent: \"approved %s\". It cannot change this file without breaking the signature." % args.run_id)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="Owner approval for one stage 6 GCE run (signed).")
    ap.add_argument("--setup", action="store_true", help="create your approval key (once)")
    ap.add_argument("--sk", action="store_true", help="with --setup: use a FIDO security key (ed25519-sk)")
    ap.add_argument("--key", default=DEFAULT_KEY)
    ap.add_argument("--run-id")
    ap.add_argument("--ops", default="init,network,n1,n2,n3,n4,u1,ssh,upload,teardown,residual")
    ap.add_argument("--budget", type=float, default=hs6.COST_STOP_ALL)
    ap.add_argument("--max-hours", type=float, default=hs6.MAX_HOURS)
    ap.add_argument("--valid-hours", type=float, default=12.0)
    a = ap.parse_args(argv)
    try:
        if a.setup:
            return setup(a)
        if not a.run_id or not re.fullmatch(r"[a-z][a-z0-9]{3,7}", a.run_id):
            raise Refused("--run-id is required (a lowercase letter, then 3-7 lowercase letters or digits)")
        return approve(a)
    except Refused as e:
        print("REFUSED: %s" % e, file=sys.stderr)
        return 2
    except (KeyboardInterrupt, EOFError):
        print("\nCancelled. Nothing was approved.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
