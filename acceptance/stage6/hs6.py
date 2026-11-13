#!/usr/bin/env python3
"""hs6.py — GCE lifecycle harness for Hagistack stage 6 (own RPM set, real-machine acceptance).

Dry-run by default. Without an Owner approval file AND the matching HS6_EXECUTE
value, every command only prints what it would do and calls nothing (not even
read-only gcloud).

    hs6.py --run-id RID --state-dir DIR plan
    hs6.py --run-id RID --state-dir DIR [--approval FILE] init
    hs6.py --run-id RID --state-dir DIR [--approval FILE] create-network
    hs6.py --run-id RID --state-dir DIR [--approval FILE] create-node n1|n2|n3|n4|u1
    hs6.py --run-id RID --state-dir DIR [--approval FILE] delete-node n1|n2|n3|n4|u1
    hs6.py --run-id RID --state-dir DIR [--approval FILE] teardown
    hs6.py --run-id RID --state-dir DIR [--approval FILE] ssh NODE -- COMMAND
    hs6.py --run-id RID --state-dir DIR [--approval FILE] upload NODE LOCAL REMOTE
    hs6.py --run-id RID --state-dir DIR status        (local only: ledger, cost, guards)
    hs6.py --run-id RID --state-dir DIR [--approval FILE] residual

An approval FILE is executed only with FILE.sig, the Owner's SSH signature made
by hs6_approve.py with a key pinned in OWNER_SIGNING_KEYS.

See README.md for the safety model. Python 3.9+, standard library only.
"""
import argparse
import datetime
import stat
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time

# ---------------------------------------------------------------- constants --
PROJECT = "<GCP_PROJECT>"
ZONE = "asia-northeast1-a"
REGION = "asia-northeast1"
IMAGE_PROJECT = "rocky-linux-cloud"
IMAGE_FAMILY = "rocky-linux-10"
DISK_TYPE = "pd-standard"
SUBNET_RANGE = "10.86.0.0/24"
IAP_RANGE = "35.235.240.0/20"
PREFIX = "hagistack-s6-"

# node -> (machine type, vCPUs, boot disk GB, planned hours)
NODES = {
    "n1": ("n2-standard-8", 8, 100, 4.0),
    "n2": ("n2-standard-4", 4, 60, 3.0),
    "n3": ("n2-standard-4", 4, 50, 3.0),
    "n4": ("n2-standard-4", 4, 50, 2.5),
    "u1": ("n2-standard-4", 4, 60, 3.0),
}
NETWORK_PARTS = ("net", "subnet", "fw-iap", "fw-int", "router", "nat")
ALL_PARTS = NETWORK_PARTS + tuple(NODES)
OPERATIONS = ("init", "network", "n1", "n2", "n3", "n4", "u1", "ssh", "upload", "download", "teardown", "residual")
# download: a file from a node of this run into <state-dir>/downloads/<NAME>, never
# overwriting, kept only when its SHA-256 equals the node's sha256sum of it.
DOWNLOAD_NAME_RE = r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}"
DOWNLOAD_REMOTE_RE = r"/[A-Za-z0-9._/+-]{1,511}"
CLEANUP_OPS = ("teardown", "residual")

# Tokyo list prices (USD), read from cloud.google.com pricing pages on 2026-11-12.
PRICE_VM_HOUR = {"n2-standard-8": 0.498352, "n2-standard-4": 0.249176}
PRICE_PD_STANDARD_GIB_HOUR = 0.000071233
PRICE_NAT_VM_HOUR = 0.0014
PRICE_NAT_IP_HOUR = 0.005
PRICE_NAT_GIB = 0.045
EST_NAT_GIB_PER_NODE = 3.0
# Internet egress price for Tokyo was NOT verified. A deliberately high assumption:
ASSUMED_EGRESS_USD_PER_GIB = 0.20
EST_EGRESS_GIB_TOTAL = 2.0
UNPRICED = ("internet egress (assumed US$0.20/GiB for 2 GiB)",
            "NAT data volume (assumed 3 GiB per node at US$0.045/GiB)")

COST_STOP_NEW = 7.0
COST_STOP_ALL = 8.0
MAX_HOURS = 6.0
NODE_OVERRUN = 1.5
MAX_APPROVAL_HOURS = 24.0
SETTLE_SECONDS = 15 * 60   # a creation absent this long after its request is taken as never made

RUN_ID_RE = re.compile(r"[a-z][a-z0-9]{3,7}")
FORBIDDEN_ENV = ("CLOUDSDK_CORE_ACCOUNT", "CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT",
                 "CLOUDSDK_AUTH_ACCESS_TOKEN_FILE", "CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE",
                 "CLOUDSDK_CORE_PROJECT", "CLOUDSDK_API_ENDPOINT_OVERRIDES_COMPUTE")
MIN_NODE_HOURS = 0.5

# Exact command prefixes (positional words) allowed for each kind of call.
READ_PREFIXES = (
    ("config", "get-value"), ("auth", "list"),
    ("compute", "instances", "list"), ("compute", "instances", "describe"),
    ("compute", "disks", "list"), ("compute", "disks", "describe"),
    ("compute", "networks", "list"), ("compute", "networks", "describe"),
    ("compute", "networks", "subnets", "list"), ("compute", "networks", "subnets", "describe"),
    ("compute", "firewall-rules", "list"), ("compute", "firewall-rules", "describe"),
    ("compute", "routers", "list"), ("compute", "routers", "describe"),
    ("compute", "routers", "nats", "describe"),
    ("compute", "addresses", "list"), ("compute", "regions", "describe"),
    ("compute", "project-info", "describe"), ("compute", "images", "describe-from-family"),
)
MUTATE_PREFIXES = tuple(
    ("compute",) + k + (v,) for k in (("instances",), ("networks",), ("networks", "subnets"), ("firewall-rules",),
                                       ("routers",), ("routers", "nats")) for v in ("create", "delete"))
REMOTE_PREFIXES = (("compute", "ssh"), ("compute", "scp"))

EXIT_REFUSED, EXIT_IAM, EXIT_QUOTA, EXIT_UNKNOWN, EXIT_LEDGER, EXIT_GUARD, EXIT_CLEANUP, EXIT_LOCK = 2, 3, 4, 5, 6, 7, 8, 9
EXIT_REMOTE = 10   # the command on the node exited non-zero (its output and status are kept)


class Stop(Exception):
    """Stop the run. code is the process exit status; teardown asks main() to
    tear this run's resources down (accrued cost over the limit)."""
    def __init__(self, msg, code=EXIT_REFUSED, teardown=False):
        super().__init__(msg)
        self.code = code
        self.teardown = teardown


class NotFound(Exception):
    pass


# -------------------------------------------------------------------- mode --
# HS6_GCLOUD (a gcloud stand-in) and HS6_NOW (a fake clock) exist for the tests.
# They are honoured only for an approval whose account is in the reserved
# ".invalid" domain, which no real Google account can have; with a real account
# they make the harness refuse to run. Without an approval nothing is called.
_TEST_MODE = {"on": False}
TEST_HOOKS = ("HS6_GCLOUD", "HS6_NOW", "HS6_CLOCK_FILE", "HS6_REGISTRY", "HS6_WATCH_MAX_LOOPS",
              "HS6_OWNER_SIGNERS")

# ------------------------------------------------------- Owner signing keys --
# An approval is executed only if it carries the Owner's SSH signature
# (`ssh-keygen -Y sign`, namespace below) made with one of these keys. Only the
# public halves are here; the private key stays with the Owner, protected by a
# passphrase or a hardware key, and is never given to the AI agent or to
# ssh-agent. hs6_approve.py --setup prints the line to put here. While the tuple
# is empty, nothing can be executed. Changing it changes this file's SHA-256, so
# it needs the Owner's review like any other harness change (README).
OWNER_SIGNING_KEYS = ()
SIG_NAMESPACE = "hagistack-stage6-approval"
SIGNER_ID = "hagistack-owner"
APPROVAL_FORMAT = 2
SSH_KEYGEN_PATHS = ("/usr/bin/ssh-keygen",)


def watch_interval():
    """Seconds between guard checks while waiting. Outside the tests it is kept
    between 5 s and 5 min, so it can neither busy-loop nor switch monitoring off."""
    v = float(os.environ.get("HS6_WATCH_INTERVAL", "60"))
    return v if _TEST_MODE["on"] else min(300.0, max(5.0, v))


def record_stop(state_dir, rec):
    """Append to stops.jsonl without the lock: a limit or a monitor failure is
    recorded even when the lock is busy or the teardown cannot start. Any
    entry there blocks new resources and test steps for the rest of the run."""
    rec = dict(rec, at=iso(now()))
    try:
        with open(os.path.join(state_dir, "stops.jsonl"), "a") as f:
            f.write(json.dumps(rec, sort_keys=True) + "\n")
            f.flush()
            os.fsync(f.fileno())
    except OSError as e:
        print("WARNING: could not record the stop (%s): %s" % (e, rec), file=sys.stderr)


def recorded_stops(state_dir):
    path = os.path.join(state_dir, "stops.jsonl")
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [line for line in f.read().splitlines() if line.strip()]


def _decide_test_mode(account):
    stub = any(os.environ.get(k) for k in TEST_HOOKS)
    fake = isinstance(account, str) and account.endswith(".invalid")
    if stub and not fake:
        raise Stop("%s are for tests only and are refused with a real account" % " / ".join(TEST_HOOKS))
    if fake and not os.environ.get("HS6_GCLOUD"):
        raise Stop("an .invalid account is a test account: refused with the real gcloud")
    _TEST_MODE["on"] = fake


def now():
    test = _TEST_MODE["on"] or os.environ.get("HS6_GCLOUD")
    if test and os.environ.get("HS6_CLOCK_FILE"):
        # a clock the tests can move while a command runs
        with open(os.environ["HS6_CLOCK_FILE"]) as f:
            return float(f.read().strip())
    if test and os.environ.get("HS6_NOW"):
        return float(os.environ["HS6_NOW"])
    return time.time()


def iso(t):
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_ts(s):
    # GCE: 2026-11-12T10:52:33.001-08:00 ; ours: 2026-11-12T18:52:33Z
    s = s.replace("Z", "+00:00")
    m = re.match(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(\.\d+)?([+-]\d\d:\d\d)$", s)
    if not m:
        raise ValueError("unparseable timestamp: " + s)
    return datetime.datetime.fromisoformat(m.group(1) + m.group(3)).timestamp()


def duration(hours):
    m = int(round(hours * 60))
    return "%dh%dm" % (m // 60, m % 60) if m % 60 else "%dh" % (m // 60)


# ------------------------------------------------------------------- names --
def name_of(rid, part):
    if part not in ALL_PARTS:
        raise Stop("internal: unknown resource part " + part)
    return PREFIX + rid + "-" + part


def check_target(rid, name):
    if not re.fullmatch(re.escape(PREFIX + rid) + "-(" + "|".join(re.escape(p) for p in ALL_PARTS) + ")", name):
        raise Stop("refused: %s is not a resource of run %s (only %s%s-<part> may be changed)"
                   % (name, rid, PREFIX, rid))


def positionals(args):
    return [a for a in args if not a.startswith("-")]


def _prefix_ok(args, allowed):
    pos = tuple(positionals(args))
    return any(pos[:len(p)] == p for p in allowed)


# ------------------------------------------------------------------ gcloud --
class Gcloud:
    """The only way this program talks to GCE. read() takes exact read-only
    command prefixes; mutate() takes exact create/delete prefixes with exactly
    one target of this run; remote() takes ssh/scp to one node of this run. In
    dry-run every call is printed and nothing is run."""

    def __init__(self, rid, execute, log, account=None):
        self.rid = rid
        self.execute = execute
        self.log = log
        self.account = account
        self.bin = os.environ.get("HS6_GCLOUD") or "gcloud"
        # test hook: a Python stand-in is run with this interpreter (no new executable file needed)
        self.cmd = [sys.executable, "-I", self.bin] if os.environ.get("HS6_GCLOUD") and self.bin.endswith(".py") \
            else [self.bin]
        self.timeout = float(os.environ.get("HS6_TIMEOUT", "600"))
        self.planned = []

    def _run(self, args, with_account=True):
        # --account pins the identity of every call; the account check itself
        # reads gcloud's own configuration without it (it would override it).
        if self.execute and self.account and with_account:
            args = args + ["--account=" + self.account]
        self.log("gcloud " + " ".join(args))
        if not self.execute:
            self.planned.append(args)
            print("DRY-RUN: gcloud " + " ".join(args))
            return ""
        env = dict(os.environ)
        env["CLOUDSDK_CORE_DISABLE_PROMPTS"] = "1"
        try:
            p = subprocess.run(self.cmd + args, capture_output=True, text=True, timeout=self.timeout, env=env)
        except subprocess.TimeoutExpired:
            raise Stop("gcloud timed out after %.0fs: %s" % (self.timeout, " ".join(args)), EXIT_UNKNOWN)
        except OSError as e:
            raise RuntimeError("gcloud could not be run: %s" % e)
        if p.returncode != 0:
            err = (p.stderr or "") + (p.stdout or "")
            low = err.lower()
            if "traceback" in low or "filenotfounderror" in low:
                raise RuntimeError("gcloud crashed (%d): %s" % (p.returncode, err.strip()[:300]))
            if "permission_denied" in low or "does not have permission" in low or "required '" in low \
                    or "permission denied" in low or ("403" in low and "forbidden" in low):
                raise Stop("permission error (stop at once, no IAM change is made): " + err.strip()[:300], EXIT_IAM)
            if "quota" in low and "exceeded" in low:
                raise Stop("quota error: " + err.strip()[:300], EXIT_QUOTA)
            names = [a for a in positionals(args) if a.startswith(PREFIX)]
            if names and ("was not found" in low or "not found" in low) and any(n in err for n in names):
                raise NotFound(err.strip()[:300])
            raise RuntimeError("gcloud failed (%d): %s" % (p.returncode, err.strip()[:300]))
        return p.stdout

    def read(self, args, with_account=True):
        if not _prefix_ok(args, READ_PREFIXES):
            raise Stop("internal: not an allowed read-only gcloud call: " + " ".join(args))
        return self._run(args, with_account)

    def read_json(self, args):
        out = self.read(args + ["--format=json"])
        if not self.execute:
            return None
        return json.loads(out or "null")

    def mutate(self, args, target):
        check_target(self.rid, target)
        if not _prefix_ok(args, MUTATE_PREFIXES):
            raise Stop("internal: not an allowed create/delete call: " + " ".join(args))
        pos = positionals(args)
        verb_at = max(i for i, a in enumerate(pos) if a in ("create", "delete"))
        if pos[verb_at + 1:] != [target]:
            raise Stop("internal: a mutating call must name exactly its target %s" % target)
        if [a for a in args if a.startswith("--project")] != ["--project=" + PROJECT]:
            raise Stop("internal: the project must be pinned exactly once in a mutating call")
        return self._run(args)

    def remote(self, args, target, timeout, monitor=None, interval=60.0):
        """ssh/scp to one node of this run. Returns (status, stdout, stderr)
        without raising on a non-zero status: a failed test step keeps its
        whole output and exit code. While the command runs, monitor() is called
        every `interval` seconds; if it raises Stop, the command is killed and
        the Stop is re-raised with the output collected so far attached."""
        check_target(self.rid, target)
        if not _prefix_ok(args, REMOTE_PREFIXES):
            raise Stop("internal: not an ssh/scp call")
        if self.account:
            args = args + ["--account=" + self.account]
        self.log("gcloud " + " ".join(args))
        if not self.execute:
            self.planned.append(args)
            print("DRY-RUN: gcloud " + " ".join(args))
            return 0, "", ""
        env = dict(os.environ)
        env["CLOUDSDK_CORE_DISABLE_PROMPTS"] = "1"
        # its own process group, so a stop kills ssh and everything it started
        p = subprocess.Popen(self.cmd + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env,
                             start_new_session=True)
        start = time.monotonic()
        while True:
            left = timeout - (time.monotonic() - start)
            try:
                out, err = p.communicate(timeout=max(0.1, min(interval, left)))
                return p.returncode, out, err
            except subprocess.TimeoutExpired:
                pass
            except KeyboardInterrupt:
                # Ctrl-C, or SIGTERM/SIGHUP turned into this by main(): the step's own process
                # group does not get the terminal's signal, so stop it here
                rc_out_err = _kill_group(p)
                e = Stop("interrupted: the step on the node was stopped", EXIT_REMOTE)
                e.partial = rc_out_err
                raise e
            stop = None
            if time.monotonic() - start >= timeout:
                stop = Stop("the command ran longer than %.0fs" % timeout, EXIT_REMOTE)
            elif monitor is not None:
                try:
                    monitor()
                except Stop as e:
                    stop = e
                except Exception as e:  # noqa: BLE001 - a monitor that cannot run stops the step
                    stop = Stop("the monitor failed while the command ran (%s)" % e, EXIT_GUARD)
            if stop is not None:
                stop.partial = _kill_group(p)
                raise stop


def _kill_group(p):
    """TERM then KILL the whole process group; never wait without a bound.
    Returns (status, stdout, stderr) with whatever output could be collected."""
    for sig, grace in ((signal.SIGTERM, 5.0), (signal.SIGKILL, 5.0)):
        try:
            os.killpg(p.pid, sig)
        except (ProcessLookupError, PermissionError):
            pass
        try:
            out, err = p.communicate(timeout=grace)
            return p.returncode, out or "", err or ""
        except subprocess.TimeoutExpired:
            continue
    for stream in (p.stdout, p.stderr):
        try:
            stream.close()
        except Exception:  # noqa: BLE001
            pass
    return -9, "", "(output lost: the process group did not end after SIGKILL)"


def P():
    return "--project=" + PROJECT


# ------------------------------------------------------------------ ledger --
class Ledger:
    """Append-only JSON lines. Each line carries seq and the SHA-256 of the
    previous line; ledger.head holds the last seq and line hash, so a removed
    or edited line, a truncation or a missing file is detected."""

    def __init__(self, state_dir):
        self.path = os.path.join(state_dir, "ledger.jsonl")
        self.head = os.path.join(state_dir, "ledger.head")

    def exists(self):
        return os.path.exists(self.path) or os.path.exists(self.head)

    def load(self):
        if not os.path.isfile(self.path) or not os.path.isfile(self.head):
            raise Stop("ledger missing (%s / %s): nothing is created or deleted automatically"
                       % (self.path, self.head), EXIT_LEDGER)
        recs, prev = [], "0" * 64
        with open(self.path, "rb") as f:
            raw = f.read()
        if raw and not raw.endswith(b"\n"):
            raise Stop("ledger broken: last line is incomplete", EXIT_LEDGER)
        for i, line in enumerate(raw.splitlines()):
            try:
                r = json.loads(line)
            except ValueError:
                raise Stop("ledger broken at line %d: not JSON" % (i + 1), EXIT_LEDGER)
            if r.get("seq") != i or r.get("prev") != prev:
                raise Stop("ledger broken at line %d: sequence or hash chain mismatch" % (i + 1), EXIT_LEDGER)
            prev = hashlib.sha256(line).hexdigest()
            recs.append(r)
        try:
            with open(self.head) as f:
                head = json.load(f)
        except (OSError, ValueError):
            raise Stop("ledger head unreadable", EXIT_LEDGER)
        if not recs or head.get("seq") != len(recs) - 1 or head.get("hash") != prev:
            raise Stop("ledger and its head disagree (truncated or edited)", EXIT_LEDGER)
        if recs[0].get("kind") != "header":
            raise Stop("ledger has no header", EXIT_LEDGER)
        return recs

    def append(self, rec, recs):
        prev = "0" * 64
        if recs:
            with open(self.path, "rb") as f:
                prev = hashlib.sha256(f.read().splitlines()[-1]).hexdigest()
        rec = dict(rec)
        rec["seq"] = len(recs)
        rec["prev"] = prev
        rec["recorded_at"] = iso(now())
        line = json.dumps(rec, sort_keys=True).encode()
        with open(self.path, "ab") as f:
            f.write(line + b"\n")
            f.flush()
            os.fsync(f.fileno())
        tmp = self.head + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"seq": rec["seq"], "hash": hashlib.sha256(line).hexdigest()}, f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, self.head)
        recs.append(rec)
        return rec


def state_of(recs):
    """part -> latest record about it (excluding the header)."""
    st = {}
    for r in recs[1:]:
        if r.get("part"):
            st[r["part"]] = r
    return st


def last_event(recs, part, event):
    found = None
    for r in recs[1:]:
        if r.get("part") == part and r.get("event") == event:
            found = r
    return found


def unresolved(recs):
    """Parts whose deletion failed or whose state is unknown: while any exists,
    nothing new is created and no test step runs (only teardown)."""
    return sorted(p for p, r in state_of(recs).items() if r["event"] in ("delete-failed", "unknown", "create-requested"))


# ------------------------------------------------------------------- cost --
def _unit_cost(part):
    mt, _cpu, gb, _planned = NODES[part]
    return PRICE_VM_HOUR[mt] + gb * PRICE_PD_STANDARD_GIB_HOUR + PRICE_NAT_VM_HOUR


def lifetimes(recs):
    """part -> (start ts, end ts or None, latest event). A resource whose state
    is unknown or whose deletion failed counts as running; one whose creation
    was refused by the API, or that stayed absent past the settle time, counts
    as nothing."""
    requested, created, deleted, latest = {}, {}, {}, {}
    for r in recs[1:]:
        p = r.get("part")
        if not p:
            continue
        ev = r["event"]
        latest[p] = ev
        if ev == "create-requested":
            requested[p] = parse_ts(r["recorded_at"])
        elif ev == "created":
            created[p] = parse_ts(r["created_at"])
        elif ev == "deleted":
            deleted[p] = parse_ts(r["deleted_at"])
    out = {}
    for p, ev in latest.items():
        if ev == "create-failed":
            continue
        start = created.get(p, requested.get(p))
        if start is None:
            raise ValueError("no start time for " + p)
        out[p] = (start, deleted.get(p) if ev == "deleted" else None, ev)
    return out


def cost_report(recs, t):
    """Accrued and projected cost (USD, list prices, not final). Raises on any
    inconsistency; guard() turns that into a stop."""
    life = lifetimes(recs)
    accrued = remaining = future = 0.0
    overrun = []
    running = 0
    first = min([s for s, _e, _v in life.values()] or [t])
    elapsed = max(0.0, (t - first) / 3600.0)
    for p, (start, end, _ev) in life.items():
        h = max(0.0, ((end if end is not None else t) - start) / 3600.0)
        if p in NODES:
            accrued += h * _unit_cost(p) + PRICE_NAT_GIB * EST_NAT_GIB_PER_NODE
            if end is None:
                running += 1
                remaining += max(0.0, NODES[p][3] - h) * _unit_cost(p)
                if h > NODES[p][3] * NODE_OVERRUN:
                    overrun.append("%s %.2fh > %.2fh" % (p, h, NODES[p][3] * NODE_OVERRUN))
        elif p == "nat":
            accrued += h * PRICE_NAT_IP_HOUR
            if end is None:
                remaining += max(0.0, MAX_HOURS - elapsed) * PRICE_NAT_IP_HOUR
    failed = {r["part"] for r in recs[1:] if r.get("event") == "create-failed"}
    for n in NODES:
        if n not in life and n not in failed:
            future += NODES[n][3] * _unit_cost(n) + PRICE_NAT_GIB * EST_NAT_GIB_PER_NODE
    if "nat" not in life:
        future += MAX_HOURS * PRICE_NAT_IP_HOUR
    assumed = ASSUMED_EGRESS_USD_PER_GIB * EST_EGRESS_GIB_TOTAL + PRICE_NAT_GIB * EST_NAT_GIB_PER_NODE * sum(
        1 for p in life if p in NODES)
    accrued += ASSUMED_EGRESS_USD_PER_GIB * EST_EGRESS_GIB_TOTAL
    return {"accrued_usd": round(accrued, 4), "assumed_part_usd": round(assumed, 4),
            "projected_usd": round(accrued + remaining + future, 4),
            "elapsed_hours": round(elapsed, 3), "overrun": overrun, "running_nodes": running,
            "final": False, "unpriced": list(UNPRICED)}


def unattended_bound():
    """Upper estimate if nobody runs the harness after creating every node:
    each node lives until GCE deletes it at its max run duration (never more
    than planned x 1.5 or the run's time limit), plus NAT data and assumed
    egress. Leftover NAT IP hours are not included (they last until removed)."""
    total = sum(min(NODES[n][3] * NODE_OVERRUN, MAX_HOURS) * _unit_cost(n) + PRICE_NAT_GIB * EST_NAT_GIB_PER_NODE
                for n in NODES)
    return round(total + ASSUMED_EGRESS_USD_PER_GIB * EST_EGRESS_GIB_TOTAL + MAX_HOURS * PRICE_NAT_IP_HOUR, 2)


def cost_text(rep, recs, t):
    life = lifetimes(recs)
    running = [p for p, (_s, e, _v) in life.items() if p in NODES and e is None]
    net_left = [p for p, (_s, e, _v) in life.items() if p in NETWORK_PARTS and e is None]
    lines = ["cost (USD, Tokyo list prices; an estimate, NOT the Google Cloud bill):",
             "  harness estimate, accrued so far: US$%.2f, of which US$%.2f is assumed (egress, NAT data)"
             % (rep["accrued_usd"], rep["assumed_part_usd"]),
             "  projection for the planned run:  US$%.2f" % rep["projected_usd"],
             "  assumed, not verified: %s" % "; ".join(UNPRICED),
             "  actual billing: not known to the harness; check Cloud Billing"]
    if running:
        lines.append("  if the harness stopped now: GCE deletes %s at their max run duration" % ", ".join(running))
    if net_left:
        lines.append("  still recorded as present and never deleted by GCE itself: %s (NAT IP US$%.3f/h)"
                     % (", ".join(net_left), PRICE_NAT_IP_HOUR))
    return "\n".join(lines)


def limits_from(appr):
    """The Owner's approval can only lower the limits, never raise them."""
    if not appr:
        return {"stop_all": COST_STOP_ALL, "stop_new": COST_STOP_NEW, "max_hours": MAX_HOURS}
    b = min(COST_STOP_ALL, float(appr["budget_usd"]))
    return {"stop_all": b, "stop_new": min(COST_STOP_NEW, b * COST_STOP_NEW / COST_STOP_ALL),
            "max_hours": min(MAX_HOURS, float(appr["max_hours"]))}


def guard(recs, t, creating=False, limits=None):
    """Returns the cost report; raises Stop when a limit applies."""
    lim = limits or limits_from(None)
    try:
        rep = cost_report(recs, t)
    except Exception as e:  # noqa: BLE001 - any failure of the monitor stops the run
        raise Stop("cost/time monitor failed (%s): no new resource, no further test" % e, EXIT_GUARD)
    if rep["accrued_usd"] >= lim["stop_all"]:
        raise Stop("accrued cost US$%.2f >= US$%.2f: stop, keep evidence, tear down this run's resources"
                   % (rep["accrued_usd"], lim["stop_all"]), EXIT_GUARD, teardown=True)
    if rep["elapsed_hours"] >= lim["max_hours"]:
        raise Stop("elapsed %.2fh >= %.2fh: stop and tear down this run's resources"
                   % (rep["elapsed_hours"], lim["max_hours"]), EXIT_GUARD, teardown=True)
    if rep["overrun"]:
        raise Stop("node over its planned time by more than 50%%: %s: stop and tear down this run's resources"
                   % ", ".join(rep["overrun"]), EXIT_GUARD, teardown=True)
    if creating and rep["projected_usd"] >= lim["stop_new"]:
        raise Stop("projected cost US$%.2f >= US$%.2f: no new resource" % (rep["projected_usd"], lim["stop_new"]),
                   EXIT_GUARD)
    return rep


# ---------------------------------------------------------------- approval --
def owner_statement(rid):
    return "I, the Owner, approve the Stage 6-1 GCE operations listed here for run %s in %s/%s." % (rid, PROJECT, ZONE)


def harness_sha256():
    with open(os.path.abspath(__file__), "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))


def check_approval_file(path, state_dir=None):
    """What the harness can check about who could have written the approval.
    It cannot tell the Owner from another process of the same OS user; that
    part stays procedural (README)."""
    try:
        st = os.lstat(path)
    except OSError as e:
        raise Stop("approval file unreadable: %s" % e)
    if stat.S_ISLNK(st.st_mode):
        raise Stop("approval file is a symbolic link: refused")
    if not stat.S_ISREG(st.st_mode):
        raise Stop("approval file is not a regular file: refused")
    if st.st_uid != os.getuid():
        raise Stop("approval file is owned by another user: refused")
    if st.st_mode & 0o022:
        raise Stop("approval file is writable by group or others: refused")
    # judge the place the kernel will actually open, not the spelling of the path
    parent = os.path.dirname(os.path.realpath(path))
    pst = os.lstat(parent)
    if stat.S_ISLNK(pst.st_mode) or pst.st_mode & 0o022 or pst.st_uid != os.getuid():
        raise Stop("the directory holding the approval file must be the user's own, not a link, and not "
                   "writable by group or others")
    if st.st_nlink != 1:
        raise Stop("approval file has more than one hard link: refused")
    if _inside(path, repo_root()):
        raise Stop("approval file is inside the repository: refused (keep it where only the Owner writes)")
    if state_dir and os.path.isdir(state_dir) and _inside(path, state_dir):
        raise Stop("approval file is inside the run's state directory: refused")


def _inside(path, directory):
    """Is path below directory? Compared by device and inode of every parent,
    so letter case or links in the spelling do not matter."""
    try:
        target = os.stat(directory)
    except OSError:
        return False
    d = os.path.dirname(os.path.realpath(path))
    while True:
        try:
            st = os.stat(d)
        except OSError:
            return False
        if (st.st_dev, st.st_ino) == (target.st_dev, target.st_ino):
            return True
        parent = os.path.dirname(d)
        if parent == d:
            return False
        d = parent


def _read_checked(path):
    """The bytes of an approval or signature file, read once through a
    descriptor that is checked to be the file that was inspected."""
    check_approval_file(path)
    try:
        before = os.lstat(path)
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(fd, "rb") as f:
            st = os.fstat(f.fileno())
            if (st.st_dev, st.st_ino) != (before.st_dev, before.st_ino) or st.st_nlink != 1 or st.st_mode & 0o022:
                raise Stop("approval file changed while it was being read: refused")
            data = f.read(1 << 16)
    except OSError as e:
        raise Stop("approval file unreadable: %s" % e)
    return data


def owner_signing_keys():
    """The public keys an approval signature must verify against. The test hook
    HS6_OWNER_SIGNERS works only in test mode (an .invalid account)."""
    hook = os.environ.get("HS6_OWNER_SIGNERS")
    if hook and _TEST_MODE["on"]:
        with open(hook) as f:
            return tuple(x.strip() for x in f if x.strip() and not x.startswith("#"))
    return OWNER_SIGNING_KEYS


def ssh_keygen():
    for p in SSH_KEYGEN_PATHS:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    raise Stop("ssh-keygen not found at %s: cannot verify the Owner's signature" % " or ".join(SSH_KEYGEN_PATHS))


def verify_owner_signature(data, sig):
    """Raises Stop unless sig is the Owner's SSH signature of exactly data."""
    keys = owner_signing_keys()
    if not keys:
        raise Stop("no Owner signing key is pinned in hs6.py (OWNER_SIGNING_KEYS): nothing can be executed. "
                   "See README, 'Approving a run'.")
    for k in keys:
        if not re.fullmatch(r"(ssh-ed25519|sk-ssh-ed25519@openssh\.com) [A-Za-z0-9+/=]+( [^\n]*)?", k):
            raise Stop("a pinned Owner signing key is not an ed25519 public key line: refused")
    tmp = tempfile.mkdtemp(prefix="hs6-verify-")
    try:
        signers = os.path.join(tmp, "allowed_signers")
        sigf = os.path.join(tmp, "approval.sig")
        with open(signers, "w") as f:
            for k in keys:
                f.write('%s namespaces="%s" %s\n' % (SIGNER_ID, SIG_NAMESPACE, " ".join(k.split()[:2])))
        with open(sigf, "wb") as f:
            f.write(sig)
        try:
            p = subprocess.run([ssh_keygen(), "-Y", "verify", "-f", signers, "-I", SIGNER_ID, "-n", SIG_NAMESPACE,
                                "-s", sigf], input=data, capture_output=True, timeout=30)
        except (OSError, subprocess.SubprocessError) as e:
            raise Stop("could not run ssh-keygen to verify the Owner's signature: %s" % e)
        if p.returncode != 0:
            raise Stop("the approval's .sig is not a valid Owner signature of exactly this file "
                       "(another key, another file, or a changed file): refused")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def load_approval(path, rid, op):
    """None => dry-run. A valid approval for this run and operation AND
    HS6_EXECUTE=<rid> => execute. Anything else stops. For cleanup operations
    an approval that has expired still counts, so a run can always be torn down.

    The approval is PATH (JSON) plus PATH.sig, the Owner's SSH signature of
    exactly those bytes. A file without a valid signature by a pinned Owner key
    is refused, whoever wrote it."""
    if not path:
        if os.environ.get("HS6_EXECUTE"):
            raise Stop("HS6_EXECUTE is set but no approval file was given")
        return None
    data = _read_checked(path)
    try:
        a = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as e:
        raise Stop("approval file unreadable: %s" % e)
    if not isinstance(a, dict):
        raise Stop("approval file is not a JSON object")
    _decide_test_mode(a.get("account"))
    if a.get("format") != APPROVAL_FORMAT:
        raise Stop("approval format must be %d (an Owner-signed approval from hs6_approve.py); "
                   "unsigned or chat-based approval records are refused" % APPROVAL_FORMAT)
    if not os.path.lexists(path + ".sig"):
        raise Stop("approval has no Owner signature (%s.sig is missing): refused" % os.path.basename(path))
    verify_owner_signature(data, _read_checked(path + ".sig"))
    problems = []
    if not isinstance(a.get("nonce"), str) or not re.fullmatch(r"[0-9a-f]{32,64}", a.get("nonce", "")):
        problems.append("nonce must be 32-64 lowercase hex digits")
    if a.get("run_id") != rid:
        problems.append("run_id is not %s" % rid)
    if a.get("project") != PROJECT or a.get("zone") != ZONE:
        problems.append("project/zone differ from %s/%s" % (PROJECT, ZONE))
    if a.get("owner_statement") != owner_statement(rid):
        problems.append("owner_statement does not match the required text")
    if a.get("harness_sha256") != harness_sha256():
        if op in CLEANUP_OPS:
            # a run must always be cleanable: a harness fixed after init can still
            # tear the run down and check it, under the Owner's signed approval
            print("WARNING: hs6.py differs from the approved harness; allowed for %s only" % op,
                  file=sys.stderr)
        else:
            problems.append("harness_sha256 is not this harness (re-approve after any change)")
    ops = a.get("operations")
    if not isinstance(ops, list) or not ops or any(o not in OPERATIONS for o in ops):
        problems.append("operations must be a non-empty subset of %s" % (OPERATIONS,))
    elif "teardown" not in ops:
        problems.append("operations must include teardown (a run must always be able to clean up)")
    elif op not in ops:
        problems.append("operation %s is not approved" % op)
    try:
        b = float(a.get("budget_usd"))
        h = float(a.get("max_hours"))
        if not (0 < b <= COST_STOP_ALL) or not (0 < h <= MAX_HOURS):
            problems.append("budget_usd must be <= %.0f and max_hours <= %.0f" % (COST_STOP_ALL, MAX_HOURS))
    except (TypeError, ValueError):
        problems.append("budget_usd and max_hours must be numbers")
    try:
        t0, t1 = parse_ts(a.get("approved_at", "")), parse_ts(a.get("expires_at", ""))
        if (t1 - t0) / 3600.0 > MAX_APPROVAL_HOURS or t1 <= t0:
            problems.append("approval validity must be positive and at most %.0fh" % MAX_APPROVAL_HOURS)
        elif now() < t0 or (now() >= t1 and op not in CLEANUP_OPS):
            problems.append("approval not valid now (approved_at <= now < expires_at)")
    except (AttributeError, ValueError):
        problems.append("approved_at / expires_at must be timestamps")
    if not isinstance(a.get("account"), str) or "@" not in a.get("account", ""):
        problems.append("account must be the gcloud account to use")
    if problems:
        raise Stop("approval refused: " + "; ".join(problems))
    a["_sha256"] = hashlib.sha256(data).hexdigest()
    if os.environ.get("HS6_EXECUTE") != rid:
        raise Stop("approval found, but HS6_EXECUTE is not set to the run id: refusing to execute")
    bad_env = [k for k in FORBIDDEN_ENV if os.environ.get(k)]
    if bad_env:
        raise Stop("environment overrides gcloud identity or target (%s): unset them" % ", ".join(bad_env))
    return a


# ------------------------------------------------------------------- locks --
class Lock:
    def __init__(self, path):
        self.path = path
        self.fd = None

    def __enter__(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        try:
            self.fd = os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError:
            raise Stop("another operation holds %s (or a crashed one left it): remove it only after checking"
                       % self.path, EXIT_LOCK)
        os.write(self.fd, ("%d %s\n" % (os.getpid(), iso(now()))).encode())
        return self

    def __exit__(self, *exc):
        os.close(self.fd)
        os.unlink(self.path)
        return False


def registry_dir():
    return os.environ.get("HS6_REGISTRY") or os.path.join(os.path.expanduser("~"), ".config", "hagistack-stage6")


# --------------------------------------------------------------- inventory --
INVENTORY = (
    ("instances", ["compute", "instances", "list"]),
    ("disks", ["compute", "disks", "list"]),
    ("networks", ["compute", "networks", "list"]),
    ("subnets", ["compute", "networks", "subnets", "list"]),
    ("firewalls", ["compute", "firewall-rules", "list"]),
    ("routers", ["compute", "routers", "list"]),
    ("addresses", ["compute", "addresses", "list"]),
)


def inventory(g):
    inv = {}
    for key, args in INVENTORY:
        items = g.read_json(args + [P()]) or []
        inv[key] = sorted({(i.get("name"), str(i.get("id"))) for i in items})
    return inv


def project_metadata(g):
    """Fingerprint and ssh-keys digest of the project-wide metadata, shared by
    every VM of the project (Sinter's too)."""
    d = g.read_json(["compute", "project-info", "describe", P()]) or {}
    md = d.get("commonInstanceMetadata") or {}
    keys = [i.get("value", "") for i in md.get("items", []) if i.get("key") == "ssh-keys"]
    return {"fingerprint": md.get("fingerprint"), "ssh_keys_sha256": hashlib.sha256("".join(keys).encode()).hexdigest()}


def ssh_keys_of(md):
    """Only the project-wide ssh-keys matter here: other metadata may change by
    other products' work without affecting this run."""
    return md.get("ssh_keys_sha256")


def check_unexpected(g, rid, recs, baseline):
    """Our namespace: anything not in the ledger stops. Other names: anything not
    in the baseline is reported (another product's work), never touched."""
    inv = inventory(g)
    own_ips = own_nat_ips(g, rid)
    known = {(r.get("name"), str(r.get("gce_id"))) for r in recs[1:] if r.get("gce_id")}
    known |= {(r.get("disk_name"), str(r.get("disk_id"))) for r in recs[1:] if r.get("disk_id")}
    foreign = []
    for key, items in inv.items():
        base = {tuple(x) for x in baseline.get(key, [])}
        for name, rid_ in items:
            if name.startswith(PREFIX):
                if (name, rid_) not in known:
                    raise Stop("unexpected resource in the stage 6 namespace: %s %s (id %s)" % (key, name, rid_))
            elif (name, rid_) not in base and not (key == "addresses" and (name, rid_) in own_ips):
                foreign.append("%s %s" % (key, name))
    for name, rid_ in inv["addresses"]:
        if (name, rid_) in own_ips:
            continue  # this run's Cloud NAT allocated it (checked by name and by its user)
        if (name, rid_) not in {tuple(x) for x in baseline.get("addresses", [])}:
            raise Stop("unexpected external address appeared: %s" % name)
    return foreign


def own_nat_ips(g, rid):
    """External addresses that Cloud NAT allocated automatically for this run's
    router: named nat-auto-ip-*, and every user of the address is the run's own
    router. They appear when a node first sends traffic out, and they are
    released when the NAT is deleted. Anything else stays unexpected."""
    router = "https://www.googleapis.com/compute/v1/projects/%s/regions/%s/routers/%s" % (
        PROJECT, REGION, name_of(rid, "router"))
    out = set()
    for a in g.read_json(["compute", "addresses", "list", P()]) or []:
        users = a.get("users") or []
        if str(a.get("name", "")).startswith("nat-auto-ip-") and str(a.get("region", "")).endswith("/regions/" + REGION) \
                and users and all(u == router for u in users):
            out.add((a.get("name"), str(a.get("id"))))
    return out


# ------------------------------------------------------------------ runner --
class Run:
    def __init__(self, args):
        self.rid = args.run_id
        if not RUN_ID_RE.fullmatch(self.rid or ""):
            raise Stop("run id must match %s" % RUN_ID_RE.pattern)
        self.state_dir = os.path.abspath(args.state_dir)
        self.args = args
        self.ledger = Ledger(self.state_dir)
        self.logf = os.path.join(self.state_dir, "operations.log")
        self.lockf = os.path.join(self.state_dir, "run.lock")
        self.appr = None

    def log(self, msg):
        if os.path.isdir(self.state_dir):
            with open(self.logf, "a") as f:
                f.write("%s %s\n" % (iso(now()), msg))

    def gcloud(self, op):
        if self.args.approval:
            check_approval_file(self.args.approval, self.state_dir)
        appr = load_approval(self.args.approval, self.rid, op)
        self.appr = appr
        execute = appr is not None
        g = Gcloud(self.rid, execute, self.log, appr["account"] if appr else None)
        if execute:
            try:
                self.check_account(g, appr["account"])
            except (RuntimeError, NotFound, ValueError) as e:
                raise Stop("could not check the gcloud account (%s)" % e, EXIT_UNKNOWN)
        return g, appr

    def limits(self):
        return limits_from(self.appr)

    def check_account(self, g, want):
        cfg = (g.read(["config", "get-value", "account"], with_account=False) or "").strip()
        imp = (g.read(["config", "get-value", "auth/impersonate_service_account"], with_account=False) or "").strip()
        cred = (g.read(["config", "get-value", "auth/credential_file_override"], with_account=False) or "").strip()
        active = (g.read(["auth", "list", "--filter=status:ACTIVE", "--format=value(account)"],
                         with_account=False) or "").split()
        if cfg != want or active != [want]:
            raise Stop("gcloud account mismatch: the configured and the only active account must be the approved one")
        if imp or cred:
            raise Stop("gcloud is set to impersonate a service account or to use a credential file override: refused")

    def load(self):
        recs = self.ledger.load()
        h = recs[0]
        if h.get("run_id") != self.rid or h.get("project") != PROJECT or h.get("zone") != ZONE:
            raise Stop("ledger belongs to another run/project/zone", EXIT_LEDGER)
        try:
            with open(os.path.join(self.state_dir, "baseline.json"), "rb") as f:
                raw = f.read()
        except OSError:
            raise Stop("baseline.json missing", EXIT_LEDGER)
        if hashlib.sha256(raw).hexdigest() != h.get("baseline_sha256"):
            raise Stop("baseline.json does not match the ledger header", EXIT_LEDGER)
        if self.appr and hashlib.sha256(self.appr["account"].encode()).hexdigest() != h.get("account_sha256"):
            raise Stop("the approved account is not the account this run started with", EXIT_LEDGER)
        return recs, json.loads(raw)

    # ---- init: read-only preflight, baseline, ledger header, run-id registry
    def init(self):
        g, appr = self.gcloud("init")
        if not g.execute:
            print("DRY-RUN: would check the account, record every existing resource as the protected baseline,")
            print("         check name collisions, quotas (%s) and the %s image, then write the ledger header."
                  % (REGION, IMAGE_FAMILY))
            for _key, args in INVENTORY:
                g.read_json(args + [P()])
            return 0
        os.makedirs(self.state_dir, exist_ok=True)
        reg = registry_dir()
        with Lock(os.path.join(reg, "registry.lock")), Lock(self.lockf):
            if self.ledger.exists():
                raise Stop("this state directory already has a ledger: one run id, one ledger, never reused")
            used_path = os.path.join(reg, "used-run-ids")
            used = open(used_path).read().split() if os.path.exists(used_path) else []
            if self.rid in used:
                raise Stop("run id %s was used before: a run id is never reused" % self.rid)
            used_appr_path = os.path.join(reg, "used-approvals")
            used_appr = open(used_appr_path).read().split() if os.path.exists(used_appr_path) else []
            if appr["_sha256"] in used_appr:
                raise Stop("this approval has already started a run: an approval starts one run only")
            inv = inventory(g)
            ours = [n for items in inv.values() for n, _ in items if n.startswith(PREFIX)]
            if ours:
                raise Stop("resources already exist in the stage 6 namespace: %s" % ", ".join(sorted(ours)))
            region = g.read_json(["compute", "regions", "describe", REGION, P()])
            proj = g.read_json(["compute", "project-info", "describe", P()])
            need = {("region", "N2_CPUS"): 20, ("region", "CPUS"): 20, ("region", "DISKS_TOTAL_GB"): 320,
                    ("region", "INSTANCES"): 4, ("region", "IN_USE_ADDRESSES"): 1,
                    ("project", "NETWORKS"): 1, ("project", "CPUS_ALL_REGIONS"): 20,
                    ("project", "FIREWALLS"): 2, ("project", "ROUTERS"): 1}
            quotas = {}
            for scope, doc in (("region", region), ("project", proj)):
                for q in doc.get("quotas", []):
                    quotas[(scope, q["metric"])] = q["limit"] - q["usage"]
            short = ["%s %s free %s < %s" % (s, m, quotas.get((s, m)), v)
                     for (s, m), v in need.items() if quotas.get((s, m), -1) < v]
            if short:
                raise Stop("quota insufficient: " + "; ".join(short), EXIT_QUOTA)
            img = g.read_json(["compute", "images", "describe-from-family", IMAGE_FAMILY,
                               "--project=" + IMAGE_PROJECT])
            if img.get("status") != "READY" or img.get("architecture") != "X86_64":
                raise Stop("image %s is not READY x86_64" % img.get("name"))
            raw = json.dumps(inv, sort_keys=True, indent=1).encode()
            with open(os.path.join(self.state_dir, "baseline.json"), "wb") as f:
                f.write(raw)
            hdr = {"kind": "header", "run_id": self.rid, "project": PROJECT, "zone": ZONE,
                   "account_sha256": hashlib.sha256(appr["account"].encode()).hexdigest(),
                   "baseline_sha256": hashlib.sha256(raw).hexdigest(),
                   "project_metadata": project_metadata(g),
                   "image": {"project": IMAGE_PROJECT, "name": img["name"], "id": str(img["id"])},
                   "quota_free": {"%s/%s" % k: v for k, v in quotas.items() if k in need},
                   "harness_sha256": harness_sha256(),
                   "approval_sha256": appr["_sha256"], "approval_nonce": appr["nonce"]}
            self.ledger.append(hdr, [])
            with open(used_path, "a") as f:
                f.write(self.rid + "\n")
            with open(used_appr_path, "a") as f:
                f.write(appr["_sha256"] + "\n")
        print("init: baseline of %d existing resources recorded; image %s (%s)"
              % (sum(len(v) for v in inv.values()), img["name"], img["id"]))
        return 0

    # ---- identity of a part in GCE now
    def identity(self, g, part):
        """What GCE says about a part now: id, creationTimestamp, labels, raw.
        Raises NotFound. A Cloud NAT has no resource id of its own: it is
        identified by its router's id and its name."""
        d = g.read_json(self.describe_args(part))
        if part == "nat":
            r = g.read_json(self.describe_args("router"))
            return {"id": "router-%s/nat/%s" % (r["id"], d.get("name")), "creationTimestamp": None,
                    "labels": {}, "raw": d}
        return {"id": str(d["id"]), "creationTimestamp": d["creationTimestamp"], "labels": d.get("labels") or {},
                "raw": d}

    def _plausible(self, part, idn, intent):
        """Does what GCE shows look like the resource this run asked for? The
        namespace was empty at init (checked), so a resource of ours created
        after our request, with our label for nodes, is ours."""
        created = idn["creationTimestamp"] or intent["recorded_at"]
        ok = parse_ts(created) >= parse_ts(intent["recorded_at"]) - 300
        if part in NODES:
            ok = ok and idn["labels"].get("run-id") == self.rid
        return ok

    def _adopt(self, g, recs, part, idn, intent, note):
        """Record a resource of this run as created, with its GCE identity."""
        name = name_of(self.rid, part)
        d = idn["raw"]
        rec = {"kind": "resource", "part": part, "name": name, "event": "created", "gce_id": idn["id"],
               "created_at": idn["creationTimestamp"] or intent["recorded_at"], "self_link": d.get("selfLink"),
               "labels": idn["labels"], "note": note}
        problems = []
        if part in NODES:
            ac = [c for ni in d.get("networkInterfaces", []) for c in
                  (ni.get("accessConfigs") or []) + (ni.get("ipv6AccessConfigs") or [])]
            if ac:
                rec["external_ip"] = True
                problems.append("%s has an external address although --no-address was given" % name)
            disks = d.get("disks") or []
            rec["disk_name"] = (disks[0].get("source", "") if disks else "").rsplit("/", 1)[-1]
            rec["machine_type"] = d.get("machineType", "").rsplit("/", 1)[-1]
            try:
                disk = g.read_json(["compute", "disks", "describe", rec["disk_name"], "--zone=" + ZONE, P()])
                rec.update({"disk_id": str(disk["id"]), "disk_type": disk["type"].rsplit("/", 1)[-1],
                            "disk_gb": int(disk["sizeGb"])})
            except (NotFound, RuntimeError, KeyError, ValueError, TypeError) as e:
                problems.append("boot disk of %s could not be read (%s)" % (name, e))
            if len(disks) != 1:
                problems.append("%s has %d disks, expected only its boot disk" % (name, len(disks)))
            if rec.get("disk_type") not in (None, DISK_TYPE) or rec.get("disk_gb") not in (None, NODES[part][2]) \
                    or rec["machine_type"] != NODES[part][0]:
                problems.append("%s does not have the planned machine type/disk" % name)
        self.ledger.append(rec, recs)
        return rec, problems

    # ---- generic create with ledger intent and reconciliation
    def _create(self, g, recs, part, create_args, describe_args):
        name = name_of(self.rid, part)
        st = state_of(recs).get(part)
        if st and st["event"] == "create-failed":
            raise Stop("%s failed to create earlier: no automatic retry (Owner decision)" % name)
        if st:
            raise Stop("%s already has a ledger entry (%s): no second creation" % (name, st["event"]))
        try:
            g.read_json(describe_args)
            raise Stop("name collision: %s already exists in GCE" % name)
        except NotFound:
            pass
        except RuntimeError as e:
            raise Stop("could not check %s before creating it (%s): stop" % (name, e), EXIT_UNKNOWN)
        intent = self.ledger.append({"kind": "resource", "part": part, "name": name, "event": "create-requested",
                                     "run_id": self.rid, "project": PROJECT, "zone": ZONE,
                                     "command": create_args}, recs)
        err, rejected = None, False
        try:
            g.mutate(create_args, name)
        except Stop as e:
            err, rejected = e, e.code in (EXIT_IAM, EXIT_QUOTA)
        except (RuntimeError, NotFound) as e:
            err = Stop("create call failed: %s" % e, EXIT_UNKNOWN)
        try:
            idn = self.identity(g, part)
        except NotFound:
            if rejected:
                # the API refused the request outright: nothing was made
                self.ledger.append({"kind": "resource", "part": part, "name": name, "event": "create-failed",
                                    "error": str(err)}, recs)
                raise err
            # a timeout or an unclassified error: the operation may still finish
            self.ledger.append({"kind": "resource", "part": part, "name": name, "event": "unknown",
                                "error": "absent right after the call (%s); may still appear" % (err or "no error")},
                               recs)
            raise Stop("%s: state unknown after create (%s); teardown reconciles it later" % (name, err),
                       EXIT_UNKNOWN)
        except (Stop, RuntimeError, KeyError, ValueError) as e:
            self.ledger.append({"kind": "resource", "part": part, "name": name, "event": "unknown",
                                "error": str(e)}, recs)
            raise Stop("state of %s unknown after create (%s): teardown reconciles it later" % (name, e),
                       EXIT_UNKNOWN)
        if not self._plausible(part, idn, intent):
            self.ledger.append({"kind": "resource", "part": part, "name": name, "event": "unknown",
                                "error": "exists but does not look created by this call", "gce_id": idn["id"]}, recs)
            raise Stop("%s exists but its identity does not match this creation: manual check" % name, EXIT_UNKNOWN)
        rec, problems = self._adopt(g, recs, part, idn, intent, "created by this call")
        if err:
            raise Stop("%s was created but the create call reported an error (%s): stop" % (name, err), EXIT_UNKNOWN)
        if problems:
            raise Stop("; ".join(problems) + ": stop and tear down")
        return rec

    def describe_args(self, part):
        name = name_of(self.rid, part)
        return {
            "net": ["compute", "networks", "describe", name, P()],
            "subnet": ["compute", "networks", "subnets", "describe", name, "--region=" + REGION, P()],
            "fw-iap": ["compute", "firewall-rules", "describe", name, P()],
            "fw-int": ["compute", "firewall-rules", "describe", name, P()],
            "router": ["compute", "routers", "describe", name, "--region=" + REGION, P()],
            "nat": ["compute", "routers", "nats", "describe", name, "--router=" + name_of(self.rid, "router"),
                    "--region=" + REGION, P()],
        }.get(part) or ["compute", "instances", "describe", name, "--zone=" + ZONE, P()]

    def create_args(self, part, image=None, run_hours=None):
        n = lambda p: name_of(self.rid, p)  # noqa: E731
        if part == "net":
            return ["compute", "networks", "create", n("net"), "--subnet-mode=custom", P()]
        if part == "subnet":
            return ["compute", "networks", "subnets", "create", n("subnet"), "--network=" + n("net"),
                    "--region=" + REGION, "--range=" + SUBNET_RANGE, P()]
        if part == "fw-iap":
            return ["compute", "firewall-rules", "create", n("fw-iap"), "--network=" + n("net"),
                    "--direction=INGRESS", "--allow=tcp:22", "--source-ranges=" + IAP_RANGE, P()]
        if part == "fw-int":
            return ["compute", "firewall-rules", "create", n("fw-int"), "--network=" + n("net"),
                    "--direction=INGRESS", "--allow=tcp,udp,icmp", "--source-ranges=" + SUBNET_RANGE, P()]
        if part == "router":
            return ["compute", "routers", "create", n("router"), "--network=" + n("net"), "--region=" + REGION, P()]
        if part == "nat":
            return ["compute", "routers", "nats", "create", n("nat"), "--router=" + n("router"),
                    "--region=" + REGION, "--auto-allocate-nat-external-ips", "--nat-all-subnet-ip-ranges", P()]
        mt, _cpu, gb, hours = NODES[part]
        max_run = run_hours if run_hours is not None else hours * NODE_OVERRUN
        return ["compute", "instances", "create", n(part), "--zone=" + ZONE, "--machine-type=" + mt,
                "--image-project=" + IMAGE_PROJECT, "--image=" + (image or "IMAGE-FROM-INIT"),
                "--boot-disk-type=" + DISK_TYPE, "--boot-disk-size=%dGB" % gb, "--boot-disk-auto-delete",
                "--subnet=" + n("subnet"), "--no-address", "--enable-nested-virtualization",
                "--no-service-account", "--no-scopes", "--metadata=block-project-ssh-keys=TRUE",
                "--max-run-duration=" + duration(max_run), "--instance-termination-action=DELETE",
                "--labels=purpose=hagistack-verify,temporary=true,run-id=%s,hs-node=%s" % (self.rid, part), P()]

    def _refuse_new_work(self, recs):
        if recorded_stops(self.state_dir):
            raise Stop("a limit or monitor failure was recorded earlier (stops.jsonl): nothing new is created and "
                       "no test step runs; run teardown")
        if unresolved(recs):
            raise Stop("unresolved resources %s: nothing new is created and no test step runs; run teardown"
                       % unresolved(recs))

    def create_network(self):
        g, _ = self.gcloud("network")
        if not g.execute:
            for p in NETWORK_PARTS:
                g.mutate(self.create_args(p), name_of(self.rid, p))
            return 0
        with Lock(self.lockf):
            recs, base = self.load()
            guard(recs, now(), limits=self.limits())   # limits that tear down come first
            self._refuse_new_work(recs)
            guard(recs, now(), creating=True, limits=self.limits())
            self.report_foreign(check_unexpected(g, self.rid, recs, base))
            for p in NETWORK_PARTS:
                self._create(g, recs, p, self.create_args(p), self.describe_args(p))
        print("network created")
        return 0

    def create_node(self, part):
        if part not in NODES:
            raise Stop("node must be one of %s" % ", ".join(NODES))
        g, _ = self.gcloud(part)
        if not g.execute:
            g.mutate(self.create_args(part), name_of(self.rid, part))
            return 0
        with Lock(self.lockf):
            recs, base = self.load()
            guard(recs, now(), limits=self.limits())   # limits that tear down come first
            self._refuse_new_work(recs)
            st = state_of(recs)
            for p in NETWORK_PARTS:
                if st.get(p, {}).get("event") != "created":
                    raise Stop("the network is not complete (%s): no node" % p)
            if part in ("n3", "n4") and st.get("n1", {}).get("event") != "created":
                raise Stop("%s is a remote compute node: the controller n1 must exist first" % part)
            if part == "u1":
                if st.get("n4", {}).get("event") not in (None, "deleted", "create-failed"):
                    raise Stop("u1 is created only after n4 is deleted (peak 20 vCPUs)")
                try:
                    g.read_json(self.describe_args("n4"))
                    raise Stop("n4 still exists in GCE: u1 is not created")
                except NotFound:
                    pass
                except RuntimeError as e:
                    raise Stop("could not confirm that n4 is gone (%s): u1 is not created" % e, EXIT_UNKNOWN)
            running = [n for n in NODES if st.get(n, {}).get("event") not in (None, "deleted", "create-failed")]
            if sum(NODES[n][1] for n in running) + NODES[part][1] > 20:
                raise Stop("more than 20 vCPUs would run at once")
            rep = guard(recs, now(), creating=True, limits=self.limits())
            # GCE deletes the node by itself at the earlier of: its planned hours x 1.5, or
            # the end of the run's time limit. That holds even if nobody runs this harness.
            run_hours = min(NODES[part][3] * NODE_OVERRUN, self.limits()["max_hours"] - rep["elapsed_hours"])
            if run_hours < MIN_NODE_HOURS:
                raise Stop("less than %.1fh left before the run's time limit: no new node" % MIN_NODE_HOURS, EXIT_GUARD)
            self.report_foreign(check_unexpected(g, self.rid, recs, base))
            self._create(g, recs, part, self.create_args(part, recs[0]["image"]["name"], run_hours),
                         self.describe_args(part))
        print("%s created" % name_of(self.rid, part))
        return 0

    # ---- delete: ledger + same GCE id + creation time (+ run-id label)
    def _reconcile(self, g, recs, part):
        """For a part whose creation outcome is unknown (or requested and never
        reconciled, or refused): look at GCE. A plausible resource of ours is
        adopted so it can be deleted; one absent past the settle time is taken
        as never made; anything else stops for a manual check."""
        name = name_of(self.rid, part)
        intent = last_event(recs, part, "create-requested")
        if intent is None:
            raise Stop("%s has no creation request in the ledger: manual check" % name, EXIT_CLEANUP)
        try:
            idn = self.identity(g, part)
        except NotFound:
            if state_of(recs)[part]["event"] == "create-failed":
                return "absent"
            if now() - parse_ts(intent["recorded_at"]) >= SETTLE_SECONDS:
                self.ledger.append({"kind": "resource", "part": part, "name": name, "event": "create-failed",
                                    "error": "absent %d s after the request" % (now() - parse_ts(intent["recorded_at"]))},
                                   recs)
                return "absent"
            raise Stop("%s is absent but its creation may still finish: run teardown again after %d minutes"
                       % (name, SETTLE_SECONDS // 60), EXIT_CLEANUP)
        except (Stop, RuntimeError, KeyError, ValueError) as e:
            raise Stop("could not read %s (%s): manual check, not deleted" % (name, e), EXIT_CLEANUP)
        if not self._plausible(part, idn, intent):
            raise Stop("%s exists but does not look like this run's resource: manual check, not deleted" % name,
                       EXIT_CLEANUP)
        self._adopt(g, recs, part, idn, intent, "adopted by teardown after an unknown outcome")
        return "adopted"

    def _delete(self, g, recs, part):
        name = name_of(self.rid, part)
        st = state_of(recs).get(part)
        if not st or st["event"] == "deleted":
            return "absent"
        if st["event"] in ("unknown", "create-requested", "create-failed"):
            if self._reconcile(g, recs, part) == "absent":
                return "absent"
            st = state_of(recs)[part]
        created = last_event(recs, part, "created")
        if created is None:
            raise Stop("%s has no creation record: manual check" % name, EXIT_CLEANUP)
        if part in NODES and not created.get("disk_name"):
            raise Stop("%s has no recorded boot disk: manual check, not deleted" % name, EXIT_CLEANUP)
        try:
            idn = self.identity(g, part)
        except NotFound:
            if part in NODES:
                self._check_disk_gone(g, recs, part, created)
            self.ledger.append({"kind": "resource", "part": part, "name": name, "event": "deleted",
                                "deleted_at": iso(now()), "gce_id": created["gce_id"],
                                "note": "already absent (for nodes: max run duration, or deleted earlier)"}, recs)
            return "absent"
        except (Stop, RuntimeError, KeyError, ValueError) as e:
            raise Stop("could not read %s before deleting it (%s): not deleted" % (name, e), EXIT_CLEANUP)
        same_time = part == "nat" or idn["creationTimestamp"] == created["created_at"]
        if idn["id"] != created["gce_id"] or not same_time:
            raise Stop("%s in GCE is not the resource this run created (id/creation time differ): not deleted"
                       % name, EXIT_CLEANUP)
        if part in NODES:
            if idn["labels"].get("run-id") != self.rid:
                raise Stop("%s lost its run-id label: not deleted" % name, EXIT_CLEANUP)
            disks = [x.get("source", "").rsplit("/", 1)[-1] for x in idn["raw"].get("disks") or []]
            if disks != [created["disk_name"]]:
                raise Stop("%s has disks %s, not only its recorded boot disk: not deleted" % (name, disks),
                           EXIT_CLEANUP)
        try:
            g.mutate(self.delete_args(part), name)
        except (Stop, RuntimeError, NotFound) as e:
            self.ledger.append({"kind": "resource", "part": part, "name": name, "event": "delete-failed",
                                "error": str(e)}, recs)
            raise Stop("deleting %s failed (%s): stop; nothing new is created" % (name, e), EXIT_CLEANUP)
        try:
            g.read_json(self.describe_args(part))
            present = True
        except NotFound:
            present = False
        except (Stop, RuntimeError, ValueError) as e:
            self.ledger.append({"kind": "resource", "part": part, "name": name, "event": "delete-failed",
                                "error": "could not confirm deletion: %s" % e}, recs)
            raise Stop("could not confirm that %s is gone: stop" % name, EXIT_CLEANUP)
        if present:
            self.ledger.append({"kind": "resource", "part": part, "name": name, "event": "delete-failed",
                                "error": "still present after delete"}, recs)
            raise Stop("%s is still present after delete" % name, EXIT_CLEANUP)
        if part in NODES:
            self._check_disk_gone(g, recs, part, created)
        self.ledger.append({"kind": "resource", "part": part, "name": name, "event": "deleted",
                            "deleted_at": iso(now()), "gce_id": created["gce_id"],
                            "disk_deleted": created.get("disk_name")}, recs)
        return "deleted"

    def _check_disk_gone(self, g, recs, part, created):
        name = name_of(self.rid, part)
        try:
            g.read_json(["compute", "disks", "describe", created["disk_name"], "--zone=" + ZONE, P()])
            left = "still present"
        except NotFound:
            return
        except (Stop, RuntimeError, ValueError) as e:
            left = "unreadable (%s)" % e
        self.ledger.append({"kind": "resource", "part": part, "name": name, "event": "delete-failed",
                            "error": "boot disk %s %s" % (created["disk_name"], left)}, recs)
        raise Stop("boot disk %s of %s %s after delete" % (created["disk_name"], name, left), EXIT_CLEANUP)

    def delete_args(self, part):
        name = name_of(self.rid, part)
        return {
            "net": ["compute", "networks", "delete", name, "--quiet", P()],
            "subnet": ["compute", "networks", "subnets", "delete", name, "--region=" + REGION, "--quiet", P()],
            "fw-iap": ["compute", "firewall-rules", "delete", name, "--quiet", P()],
            "fw-int": ["compute", "firewall-rules", "delete", name, "--quiet", P()],
            "router": ["compute", "routers", "delete", name, "--region=" + REGION, "--quiet", P()],
            "nat": ["compute", "routers", "nats", "delete", name, "--router=" + name_of(self.rid, "router"),
                    "--region=" + REGION, "--quiet", P()],
        }.get(part) or ["compute", "instances", "delete", name, "--zone=" + ZONE, "--delete-disks=boot",
                        "--quiet", P()]

    def delete_node(self, part):
        if part not in NODES:
            raise Stop("node must be one of %s" % ", ".join(NODES))
        g, _ = self.gcloud("teardown")
        if not g.execute:
            g.mutate(self.delete_args(part), name_of(self.rid, part))
            return 0
        with Lock(self.lockf):
            recs, _base = self.load()
            print("%s: %s" % (name_of(self.rid, part), self._delete(g, recs, part)))
        return 0

    def teardown(self, reason=None):
        """Never refused by the cost or time guards: cleaning up is always allowed."""
        g, _ = self.gcloud("teardown")
        order = list(NODES) + ["nat", "router", "fw-int", "fw-iap", "subnet", "net"]
        if not g.execute:
            for p in order:
                g.mutate(self.delete_args(p), name_of(self.rid, p))
            return 0
        failures = []
        with Lock(self.lockf):
            recs, _base = self.load()
            if reason:
                self.ledger.append({"kind": "event", "event": "guard-stop", "reason": reason}, recs)
            self.ledger.append({"kind": "event", "event": "teardown-started", "reason": reason or "requested"}, recs)
            for p in order:
                if p == "nat" and failures:
                    break  # the network cannot go while a node may remain
                try:
                    print("%s: %s" % (name_of(self.rid, p), self._delete(g, recs, p)))
                except Exception as e:  # noqa: BLE001 - any failure leaves this part for the residual check
                    failures.append("%s: %s" % (p, e))
                    if p not in NODES:
                        break
            left = [p for p, r in state_of(recs).items() if r["event"] not in ("deleted", "create-failed")]
            self.ledger.append({"kind": "event", "event": "teardown-incomplete" if failures else "teardown-complete",
                                "remaining": left, "failures": failures}, recs)
        if failures:
            raise Stop("teardown incomplete; still recorded as present or unresolved: %s; reasons: %s; "
                       "run residual and remove what is left by hand" % (", ".join(left) or "none", " | ".join(failures)),
                       EXIT_CLEANUP)
        print("teardown complete")
        return 0

    def residual(self):
        g, _ = self.gcloud("residual")
        inv = inventory(g)
        if not g.execute:
            return 0
        left = ["%s %s" % (k, n) for k, items in inv.items() for n, _ in items if n.startswith(PREFIX + self.rid + "-")]
        left += ["address %s (Cloud NAT IP of this run's router)" % n for n, _ in sorted(own_nat_ips(g, self.rid))]
        try:
            g.read_json(self.describe_args("nat"))
            left.append("nat " + name_of(self.rid, "nat"))
        except NotFound:
            pass
        except RuntimeError:
            pass  # the router is gone (listed above if not)
        if left:
            print("RESIDUAL: " + ", ".join(left))
            return EXIT_CLEANUP
        print("residual: none of run %s left" % self.rid)
        return 0

    def status(self):
        recs, _base = self.load()
        st = state_of(recs)
        for p in ALL_PARTS:
            if p in st:
                print("%-8s %-17s %s" % (p, st[p]["event"], st[p].get("gce_id", "")))
        rep = cost_report(recs, now())
        print(cost_text(rep, recs, now()))
        print(json.dumps(rep, sort_keys=True))
        try:
            guard(recs, now())
            print("guard: OK")
        except Stop as e:
            print("guard: STOP — %s" % e)
            return e.code
        return 0

    def remote(self, part, cmd_args, op):
        if part not in NODES:
            raise Stop("node must be one of %s" % ", ".join(NODES))
        g, _ = self.gcloud(op)
        name = name_of(self.rid, part)
        timeout = float(os.environ.get("HS6_REMOTE_TIMEOUT", "14400"))
        part_file = final_file = None
        if op == "ssh":
            args = ["compute", "ssh", name, "--zone=" + ZONE, "--tunnel-through-iap", P(),
                    "--command=" + " ".join(cmd_args)]
        elif op == "download":
            remote, fname = cmd_args
            if not re.fullmatch(DOWNLOAD_REMOTE_RE, remote) or ".." in remote.split("/"):
                raise Stop("download: the remote path must be absolute and plain: %r" % remote)
            if not re.fullmatch(DOWNLOAD_NAME_RE, fname) or fname.endswith(".part"):
                raise Stop("download: the local name must be a plain file name: %r" % fname)
            ddir = os.path.join(self.state_dir, "downloads")
            final_file = os.path.join(ddir, fname)
            part_file = final_file + ".part"
            for f in (final_file, part_file):
                if os.path.lexists(f):
                    raise Stop("download: %s exists already (nothing is overwritten)" % f)
            args = ["compute", "scp", name + ":" + remote, part_file, "--zone=" + ZONE, "--tunnel-through-iap", P()]
        else:
            local, remote = cmd_args
            if not os.path.isfile(local):
                raise Stop("no such local file: %s" % local)
            args = ["compute", "scp", local, name + ":" + remote, "--zone=" + ZONE, "--tunnel-through-iap", P()]
        if not g.execute:
            g.remote(args, name, timeout)
            return 0
        # Checks under the lock; the (possibly hours-long) command runs without it,
        # so a teardown is never blocked by a running test step.
        with Lock(self.lockf):
            recs, _b = self.load()
            guard(recs, now(), limits=self.limits())   # limits that tear down come first
            self._refuse_new_work(recs)
            if state_of(recs).get(part, {}).get("event") != "created":
                raise Stop("%s is not a created node of this run" % name)
            want_keys = ssh_keys_of(recs[0]["project_metadata"])
            if ssh_keys_of(project_metadata(g)) != want_keys:
                raise Stop("project-wide ssh-keys differ from the baseline before %s: stop" % op)
        logdir = os.path.join(self.state_dir, "remote")
        os.makedirs(logdir, exist_ok=True)
        if op == "download":
            ddir = os.path.dirname(final_file)
            os.makedirs(ddir, mode=0o700, exist_ok=True)
            st = os.lstat(ddir)
            if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
                raise Stop("download: %s is not a directory of this user (a link?)" % ddir)
            os.chmod(ddir, 0o700)
        stamp = "%s-%s-%s" % (iso(now()).replace(":", ""), part, op)
        rc, out, err = 0, "", ""
        status = EXIT_REMOTE
        stopped = None
        interval = watch_interval()

        def monitor():
            # the same guards as everywhere, re-evaluated while the step runs
            guard(self.load_retry()[0], now(), limits=self.limits())

        try:
            try:
                rc, out, err = g.remote(args, name, timeout, monitor, interval)
            except Stop as e:
                if not hasattr(e, "partial"):
                    raise
                rc, out, err = e.partial
                err = (err or "") + "\n# stopped while running: %s\n" % e
                stopped = e
                if e.code == EXIT_GUARD and not e.teardown:
                    record_stop(self.state_dir, {"event": "monitor-failed", "reason": str(e), "by": op})
            if op == "upload" and rc == 0 and stopped is None:
                with open(cmd_args[0], "rb") as f:
                    want = hashlib.sha256(f.read()).hexdigest()
                rc2, out2, err2 = g.remote(["compute", "ssh", name, "--zone=" + ZONE, "--tunnel-through-iap", P(),
                                            "--command=sha256sum " + shlex.quote(cmd_args[1])], name, timeout)
                got = out2.split()
                if rc2 != 0 or not got or got[0] != want:
                    err += "\nSHA-256 check failed after the transfer (%s): %s" % (rc2, err2.strip())
                    rc = rc or 1
                else:
                    out += "upload verified: %s %s\n" % (want, cmd_args[1])
            if op == "download":
                verified = False
                if rc == 0 and stopped is None and os.path.isfile(part_file) and not os.path.islink(part_file):
                    h = hashlib.sha256()
                    with open(part_file, "rb") as f:
                        for chunk in iter(lambda: f.read(1 << 20), b""):
                            h.update(chunk)
                    got_local = h.hexdigest()
                    rc2, out2, err2 = g.remote(["compute", "ssh", name, "--zone=" + ZONE, "--tunnel-through-iap", P(),
                                                "--command=sha256sum " + shlex.quote(cmd_args[0])], name, timeout)
                    got = out2.split()
                    if rc2 == 0 and got and got[0] == got_local:
                        try:
                            os.link(part_file, final_file)     # fails if NAME appeared meanwhile
                        except FileExistsError:
                            err += "\n%s appeared during the transfer: not overwritten" % final_file
                        else:
                            verified = True
                        out += "download verified: %s %s -> downloads/%s\n" % (got_local, cmd_args[0], cmd_args[1])
                    else:
                        err += "\nSHA-256 check failed after the transfer (%s): %s" % (rc2, err2.strip())
                if not verified:
                    rc = rc or 1
            status = 0 if rc == 0 else EXIT_REMOTE
        finally:
            if part_file and os.path.lexists(part_file):
                os.remove(part_file)     # an unverified or partial download is not kept
            with open(os.path.join(logdir, stamp + ".log"), "w") as f:
                f.write("# %s %s rc=%s\n# command: %s\n%s\n# stderr\n%s\n" % (op, name, rc, " ".join(args), out, err))
            self.log("remote %s %s rc=%s log=remote/%s.log" % (op, name, rc, stamp))
            sys.stdout.write(out)
            sys.stderr.write(err)
            also = "; the step was also stopped: %s" % stopped if stopped else ""
            try:
                keys_now = ssh_keys_of(project_metadata(g))
            except (Stop, RuntimeError, NotFound, ValueError) as e:
                raise Stop("could not check the project ssh-keys after %s (%s): stop and check; the step's "
                           "result (rc=%s) is in remote/%s.log%s" % (op, e, rc, stamp, also), EXIT_UNKNOWN,
                           teardown=bool(stopped and stopped.teardown))
            if keys_now != want_keys:
                raise Stop("project-wide ssh-keys changed during %s (a key was written to the project?): "
                           "stop and check; Sinter's VMs share them%s" % (op, also), EXIT_REFUSED,
                           teardown=bool(stopped and stopped.teardown))
        if stopped is not None:
            raise stopped
        if status:
            print("STOP: %s on %s exited %s (output kept in remote/%s.log)" % (op, name, rc, stamp), file=sys.stderr)
        return status

    def load_retry(self):
        """Read the ledger without the lock (monitoring). Another process may be
        appending at that moment, so a failed read is retried briefly before it
        counts as a monitor failure."""
        last = None
        for _ in range(5):
            try:
                return self.load()
            except Stop as e:
                last = e
                time.sleep(0.2)
        raise Stop("ledger unreadable while monitoring (%s)" % last, EXIT_GUARD)

    def watch(self):
        """Watch the run's limits from a second terminal; tear down when a limit
        is reached, and keep retrying until the teardown is complete. It holds
        no lock while it waits and calls GCE only to check the account at start
        and to tear down. A failure is recorded in stops.jsonl (which blocks new
        work) and retried at the next interval; watch does not give up. If this
        process is killed, nothing watches any more: GCE still deletes each node
        at its max run duration, but the NAT, router, firewall rules, subnet and
        network stay until removed by hand."""
        g, _ = self.gcloud("teardown")
        interval = watch_interval()
        loops = int(os.environ.get("HS6_WATCH_MAX_LOOPS", "0")) if _TEST_MODE["on"] else 0
        if not g.execute:
            print("DRY-RUN: would check the cost and time limits every %.0fs and tear down when one is reached"
                  % interval)
            return 0
        n, tripped, seen = 0, False, set()

        def note(event, reason):
            # print every time, record each kind of event once (stops.jsonl only needs to exist)
            print("watch: %s: %s" % (event, reason))
            if event not in seen:
                record_stop(self.state_dir, {"event": event, "reason": reason, "by": "watch"})
                seen.add(event)

        while True:
            try:
                recs = self.load_retry()[0]
            except Stop as e:
                note("monitor-failed", str(e))
            else:
                alive = [p for p, r in state_of(recs).items() if r["event"] not in ("deleted", "create-failed")]
                if not alive and any(r.get("event") == "teardown-complete" for r in recs):
                    print("watch: the run has been torn down; nothing of it is recorded as present")
                    return EXIT_GUARD if tripped else 0
                try:
                    guard(recs, now(), limits=self.limits())
                except Stop as e:
                    if not e.teardown:
                        note("monitor-failed", str(e))
                    else:
                        tripped = True
                        note("limit", str(e))
                        try:
                            self.teardown(reason=str(e))
                        except Exception as t:  # noqa: BLE001 - retried at the next interval
                            note("teardown-retry", str(t))
            n += 1
            if loops and n >= loops:
                print("watch: %s after %d check(s)" % ("limit reached" if tripped else "within limits", n))
                return EXIT_GUARD if tripped else 0
            time.sleep(interval)

    def remaining_text(self):
        try:
            recs = self.ledger.load()
        except Stop as e:
            return "the ledger is unreadable (%s); run residual" % e
        left = [p for p, r in state_of(recs).items() if r["event"] not in ("deleted", "create-failed")]
        return "recorded as present or unresolved: %s; run residual" % (", ".join(left) or "nothing")

    def report_foreign(self, foreign):
        for f in foreign:
            print("NOTE: changed outside this run (not touched): " + f)
            self.log("foreign change: " + f)

    def plan(self):
        print("run %s, project %s, zone %s — dry-run plan (nothing is called)" % (self.rid, PROJECT, ZONE))
        g = Gcloud(self.rid, False, lambda m: None)
        for p in NETWORK_PARTS:
            g.mutate(self.create_args(p), name_of(self.rid, p))
        for p in ("n1", "n2", "n3", "n4"):
            g.mutate(self.create_args(p), name_of(self.rid, p))
        g.mutate(self.delete_args("n4"), name_of(self.rid, "n4"))
        g.mutate(self.create_args("u1"), name_of(self.rid, "u1"))
        for p in ["n1", "n2", "n3", "u1", "nat", "router", "fw-int", "fw-iap", "subnet", "net"]:
            g.mutate(self.delete_args(p), name_of(self.rid, p))
        rep = cost_report([{"kind": "header"}], now())
        print("cost (USD, Tokyo list prices; an estimate, NOT the Google Cloud bill):")
        print("  projection for the planned run: US$%.2f" % rep["projected_usd"])
        print("  assumed, not verified: %s" % "; ".join(UNPRICED))
        print("  if the harness stops entirely after creating the nodes: GCE deletes each node at its max run")
        print("    duration. Estimate up to then: about US$%.2f, assuming all five nodes at their longest possible"
              % unattended_bound())
        print("    duration, list prices, the assumed egress and NAT data volumes, and 6 h of NAT IP. It is an")
        print("    estimate, not a guarantee; US$8 is then NOT guaranteed, and the NAT IP keeps costing")
        print("    US$%.3f/h after that until the network is removed by hand." % PRICE_NAT_IP_HOUR)
        print("  actual billing: not known to the harness; check Cloud Billing")
        return 0


def _interrupt(signum, _frame):
    raise KeyboardInterrupt("signal %d" % signum)


def main(argv=None):
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, _interrupt)
    ap = argparse.ArgumentParser(description="Hagistack stage 6 GCE harness (dry-run unless approved)")
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--state-dir", required=True)
    ap.add_argument("--approval")
    ap.add_argument("command", choices=["plan", "init", "create-network", "create-node", "delete-node",
                                        "teardown", "status", "residual", "ssh", "upload", "download", "watch"])
    ap.add_argument("rest", nargs=argparse.REMAINDER)
    a = ap.parse_args(argv)
    r = None
    try:
        r = Run(a)
        rest = [x for x in a.rest if x != "--"]
        if a.command == "plan":
            return r.plan()
        if a.command == "init":
            return r.init()
        if a.command == "create-network":
            return r.create_network()
        if a.command in ("create-node", "delete-node"):
            if len(rest) != 1:
                raise Stop("%s takes one node name" % a.command)
            return r.create_node(rest[0]) if a.command == "create-node" else r.delete_node(rest[0])
        if a.command == "teardown":
            return r.teardown()
        if a.command == "status":
            return r.status()
        if a.command == "residual":
            return r.residual()
        if a.command == "watch":
            return r.watch()
        if a.command == "ssh":
            if len(rest) < 2:
                raise Stop("ssh NODE -- COMMAND")
            return r.remote(rest[0], rest[1:], "ssh")
        if a.command == "upload":
            if len(rest) != 3:
                raise Stop("upload NODE LOCAL REMOTE")
            return r.remote(rest[0], rest[1:], "upload")
        if a.command == "download":
            if len(rest) != 3:
                raise Stop("download NODE REMOTE NAME")
            return r.remote(rest[0], rest[1:], "download")
    except Stop as e:
        print("STOP: %s" % e, file=sys.stderr)
        if e.teardown and r is not None and r.appr is not None:
            record_stop(r.state_dir, {"event": "limit", "reason": str(e), "by": a.command})
            print("limit reached: tearing down this run's resources", file=sys.stderr)
            try:
                r.teardown(reason=str(e))
            except Stop as t:
                print("STOP: teardown did not complete: %s" % t, file=sys.stderr)
                print("STOP: %s" % r.remaining_text(), file=sys.stderr)
                return t.code if t.code != EXIT_GUARD else EXIT_CLEANUP
            except Exception as t:  # noqa: BLE001
                print("STOP: teardown could not run (%s: %s)" % (type(t).__name__, t), file=sys.stderr)
                print("STOP: %s" % r.remaining_text(), file=sys.stderr)
                return EXIT_CLEANUP
        return e.code
    except KeyboardInterrupt:
        print("STOP: interrupted; check status and the ledger before going on", file=sys.stderr)
        return EXIT_UNKNOWN
    except Exception as e:  # noqa: BLE001 - fail closed: an unexpected error is a stop
        print("STOP: unexpected error (%s: %s); state is unknown, check the ledger" % (type(e).__name__, e),
              file=sys.stderr)
        return EXIT_UNKNOWN
    return EXIT_REFUSED


if __name__ == "__main__":
    sys.exit(main())
