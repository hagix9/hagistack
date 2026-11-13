#!/usr/bin/env python3
"""Local tests for hs6.py against mock_gcloud.py. No Google API, no credentials.

    python3 test_hs6.py        (set TMPDIR to put the small scratch files elsewhere)

A sentinel `gcloud` first on PATH fails and leaves a marker if anything ever
calls the real gcloud; every test checks the marker is absent.
"""
import calendar
import hashlib
import stat
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
HS6 = os.path.join(HERE, "hs6.py")
MOCK = os.path.join(HERE, "mock_gcloud.py")
sys.path.insert(0, HERE)
import hs6  # noqa: E402

RID = "t6abc"
ACCOUNT = "tester@example.invalid"
T0 = calendar.timegm((2026, 11, 20, 1, 0, 0))
SINTER_INSTANCE = "sinter-v180-gate-o6s1a"

# Test signing keys, made once per test run in a temporary directory: OWNER stands
# for the Owner's approval key (pinned through the HS6_OWNER_SIGNERS test hook),
# OTHER for a key anyone else, such as the AI agent, could make.
KEYDIR = tempfile.mkdtemp(prefix="hs6keys-")
SSH_KEYGEN = "/usr/bin/ssh-keygen"


def _make_key(name):
    k = os.path.join(KEYDIR, name)
    subprocess.run([SSH_KEYGEN, "-q", "-t", "ed25519", "-N", "", "-C", name, "-f", k], check=True)
    return k


OWNER_KEY = _make_key("owner")
OTHER_KEY = _make_key("other")
SIGNERS = os.path.join(KEYDIR, "signers")
with open(OWNER_KEY + ".pub") as _f, open(SIGNERS, "w") as _g:
    _g.write(_f.read())


def tearDownModule():
    shutil.rmtree(KEYDIR, ignore_errors=True)


def sign(path, key=OWNER_KEY, namespace=hs6.SIG_NAMESPACE):
    if os.path.lexists(path + ".sig"):
        os.unlink(path + ".sig")
    subprocess.run([SSH_KEYGEN, "-q", "-Y", "sign", "-f", key, "-n", namespace, path], check=True,
                   capture_output=True)
    os.chmod(path + ".sig", 0o600)


def base_state():
    q = lambda m, lim, use: {"metric": m, "limit": lim, "usage": use}  # noqa: E731
    return {
        "account": ACCOUNT, "active": [ACCOUNT],
        "res": {
            "instances": {SINTER_INSTANCE: {"name": SINTER_INSTANCE, "id": "1", "creationTimestamp": "2026-10-01T00:00:00.000-00:00",
                                            "labels": {"run-id": RID}}},
            "disks": {SINTER_INSTANCE: {"name": SINTER_INSTANCE, "id": "2"}},
            "networks": {"default": {"name": "default", "id": "3"}, "mkg-proto-vpc": {"name": "mkg-proto-vpc", "id": "4"},
                         "sinter-v180-relv-net": {"name": "sinter-v180-relv-net", "id": "5"}},
            "subnets": {}, "firewalls": {}, "routers": {"sinter-v180-relv-router": {"name": "sinter-v180-relv-router", "id": "6"}},
            "nats": {}, "addresses": {"sinter-p8-gateway-ip": {"name": "sinter-p8-gateway-ip", "id": "7"}},
        },
        "quotas": {"region": [q("N2_CPUS", 200, 0), q("CPUS", 100, 0), q("DISKS_TOTAL_GB", 4096, 0),
                              q("SSD_TOTAL_GB", 500, 330), q("INSTANCES", 24, 13), q("IN_USE_ADDRESSES", 8, 0)],
                   "project": [q("NETWORKS", 5, 3), q("CPUS_ALL_REGIONS", 32, 0), q("FIREWALLS", 100, 9),
                               q("ROUTERS", 10, 1)]},
        "image": {"name": "rocky-linux-10-v20261110", "id": "4057710101549472031", "status": "READY",
                  "architecture": "X86_64"},
        "fail": [],
    }


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="hs6test-")
        self.state = os.path.join(self.tmp, "mock.json")
        self.sdir = os.path.join(self.tmp, "run")
        os.makedirs(self.sdir)
        with open(self.state, "w") as f:
            json.dump(base_state(), f)
        bindir = os.path.join(self.tmp, "bin")
        os.makedirs(bindir)
        self.marker = os.path.join(self.tmp, "REAL_GCLOUD_CALLED")
        with open(os.path.join(bindir, "gcloud"), "w") as f:
            f.write("#!/bin/sh\ntouch '%s'\nexit 99\n" % self.marker)
        os.chmod(os.path.join(bindir, "gcloud"), 0o755)
        # the mock is run as "python3 -I mock_gcloud.py" (an existing file): creating a new
        # executable per test made macOS stall on its first execution
        self.mockbin = MOCK
        self.t = T0
        self.approval = os.path.join(self.tmp, "approval.json")
        self.write_approval()
        self.env = {"PATH": bindir + os.pathsep + "/usr/bin:/bin", "HOME": self.tmp,
                    "HS6_OWNER_SIGNERS": SIGNERS,
                    "CLOUDSDK_CONFIG": os.path.join(self.tmp, "gcloudcfg"), "MOCK_STATE": self.state,
                    "HS6_GCLOUD": self.mockbin, "HS6_TIMEOUT": "10",
                    "HS6_REGISTRY": os.path.join(self.tmp, "registry")}
        # in-process calls (Protection tests) must not reach the real gcloud either
        self._saved_env = {k: os.environ.get(k) for k in ("HS6_GCLOUD", "PATH")}
        os.environ["HS6_GCLOUD"] = os.path.join(bindir, "gcloud")
        os.environ["PATH"] = bindir + os.pathsep + "/usr/bin:/bin"

    def tearDown(self):
        for k, v in self._saved_env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.assertFalse(os.path.exists(self.marker), "the real gcloud was called")
        shutil.rmtree(self.tmp)

    def write_approval(self, key=OWNER_KEY, **over):
        """An approval as the Owner would sign it (key=None: no signature)."""
        a = {"format": 2, "run_id": RID, "project": hs6.PROJECT, "zone": hs6.ZONE, "account": ACCOUNT,
             "owner_statement": hs6.owner_statement(RID), "harness_sha256": hs6.harness_sha256(),
             "operations": list(hs6.OPERATIONS), "budget_usd": 8, "max_hours": 6,
             "approved_at": hs6.iso(T0 - 60), "expires_at": hs6.iso(T0 + 20 * 3600), "nonce": "ab" * 16}
        a.update(over)
        a = {k: v for k, v in a.items() if v is not None}
        with open(self.approval, "w") as f:
            json.dump(a, f)
        os.chmod(self.approval, 0o600)
        if os.path.lexists(self.approval + ".sig"):
            os.unlink(self.approval + ".sig")
        if key:
            sign(self.approval, key)

    def hs(self, *args, approval=True, env=None, rid=RID):
        e = dict(self.env, HS6_NOW=str(self.t))
        if approval:
            e["HS6_EXECUTE"] = rid
        e.update(env or {})
        e = {k: v for k, v in e.items() if v is not None}
        cmd = [sys.executable, "-I", HS6, "--run-id", rid, "--state-dir", self.sdir]
        if approval:
            cmd += ["--approval", self.approval]
        p = subprocess.run(cmd + list(args), capture_output=True, text=True, env=e, timeout=120)
        return p.returncode, p.stdout + p.stderr

    def mock(self):
        with open(self.state) as f:
            return json.load(f)

    def set_mock(self, fn):
        s = self.mock()
        fn(s)
        with open(self.state, "w") as f:
            json.dump(s, f)

    def inject(self, match, mode, times=1, skip=0):
        self.set_mock(lambda s: s["fail"].append({"match": match, "mode": mode, "times": times, "skip": skip}))

    def mutations(self):
        return [c for c in self.mock().get("calls", []) if any(v in c for v in ("create", "delete"))]

    def ledger(self):
        with open(os.path.join(self.sdir, "ledger.jsonl")) as f:
            return [json.loads(x) for x in f]

    def events(self, part):
        return [r["event"] for r in self.ledger() if r.get("part") == part]

    def up(self, *nodes):
        rc, out = self.hs("init")
        self.assertEqual(rc, 0, out)
        rc, out = self.hs("create-network")
        self.assertEqual(rc, 0, out)
        for n in nodes:
            rc, out = self.hs("create-node", n)
            self.assertEqual(rc, 0, out)


# 1, 2 — run ids
class RunIds(Base):
    def test_valid_run_id_plan_calls_nothing(self):
        rc, out = self.hs("plan", approval=False)
        self.assertEqual(rc, 0, out)
        self.assertIn("hagistack-s6-%s-n1" % RID, out)
        self.assertNotIn("calls", self.mock())

    def test_invalid_run_ids(self):
        for bad in ("A1234", "ab", "abcdefghi", "t6-ab", "1abcd", "t6ab;rm", "abcd\n"):
            rc, out = self.hs("plan", approval=False, rid=bad)
            self.assertEqual(rc, hs6.EXIT_REFUSED, bad + out)
        self.assertNotIn("calls", self.mock())


# 3, 4, 5 and the approval gate
class ApprovalAndIdentity(Base):
    def assert_refused_no_calls(self, *args, **kw):
        rc, out = self.hs(*args, **kw)
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertEqual(self.mutations(), [])
        return out

    def test_project_mismatch(self):
        self.write_approval(project="other-project")
        self.assertIn("project/zone", self.assert_refused_no_calls("init"))
        self.assertNotIn("calls", self.mock())

    def test_zone_mismatch(self):
        self.write_approval(zone="asia-northeast1-b")
        self.assertIn("project/zone", self.assert_refused_no_calls("init"))

    def test_account_mismatch(self):
        self.set_mock(lambda s: s.update(account="someone@example.invalid", active=["someone@example.invalid"]))
        self.assertIn("account mismatch", self.assert_refused_no_calls("init"))
        self.set_mock(lambda s: s.update(account=ACCOUNT, active=[ACCOUNT, "other@example.invalid"]))
        self.assertIn("account mismatch", self.assert_refused_no_calls("init"))

    def test_dry_run_is_the_default(self):
        for args in (("init",), ("create-network",), ("create-node", "n1"), ("delete-node", "n1"), ("teardown",)):
            rc, out = self.hs(*args, approval=False)
            self.assertEqual(rc, 0, out)
            self.assertIn("DRY-RUN", out)
        self.assertNotIn("calls", self.mock())

    def test_execute_needs_both_approval_and_hs6_execute(self):
        self.assertIn("HS6_EXECUTE", self.assert_refused_no_calls("init", env={"HS6_EXECUTE": ""}))
        self.assertIn("HS6_EXECUTE", self.assert_refused_no_calls("init", env={"HS6_EXECUTE": "other1"}))
        self.assertNotIn("calls", self.mock())

    def test_approval_fields(self):
        cases = [dict(harness_sha256="0" * 64), dict(run_id="zz999"), dict(owner_statement="ok"),
                 dict(budget_usd=9), dict(max_hours=7), dict(operations=["n1"]), dict(operations=["n1", "rm"]),
                 dict(expires_at=hs6.iso(T0 - 1)), dict(approved_at=hs6.iso(T0 + 60)),
                 dict(approved_at=hs6.iso(T0 - 60), expires_at=hs6.iso(T0 + 30 * 3600)), dict(account="nobody"),
                 dict(format=1), dict(nonce="short"), dict(nonce=None)]
        for c in cases:
            self.write_approval(**c)
            self.assert_refused_no_calls("init")
        self.assertNotIn("calls", self.mock())


# 6, 7, 20, 23 — collisions, unexpected and foreign resources, external IP
class Inventory(Base):
    def test_name_collision_at_init(self):
        self.set_mock(lambda s: s["res"]["networks"].update({"hagistack-s6-%s-net" % RID: {"name": "hagistack-s6-%s-net" % RID, "id": "9"}}))
        rc, out = self.hs("init")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("already exist", out)
        self.assertFalse(os.path.exists(os.path.join(self.sdir, "ledger.jsonl")))

    def test_unexpected_resource_in_namespace_stops(self):
        self.hs("init")
        n = "hagistack-s6-%s-n1" % RID
        self.set_mock(lambda s: s["res"]["instances"].update({n: {"name": n, "id": "77"}}))
        rc, out = self.hs("create-network")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("unexpected resource", out)
        self.assertEqual(self.mutations(), [])

    def test_name_collision_at_create(self):
        self.up()
        n = "hagistack-s6-%s-n1" % RID
        # the name appears between the inventory check and the create: the per-name describe catches it
        self.inject("instances describe " + n, "FAKE_EXISTS")
        rc, out = self.hs("create-node", "n1")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("name collision", out)
        self.assertEqual([c for c in self.mutations() if n in c], [])
        self.assertEqual(self.events("n1"), [])

    def test_second_create_refused_by_ledger(self):
        self.up()
        n = "hagistack-s6-%s-n1" % RID
        rc, out = self.hs("create-node", "n1")
        self.assertEqual(rc, 0, out)
        rc, out = self.hs("create-node", "n1")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("already has a ledger entry", out)
        self.assertEqual(sum(1 for c in self.mutations() if "create" in c and n in c), 1)

    def test_foreign_change_is_reported_not_touched(self):
        self.hs("init")
        self.set_mock(lambda s: s["res"]["instances"].update({"sinter-new-x": {"name": "sinter-new-x", "id": "88"}}))
        rc, out = self.hs("create-network")
        self.assertEqual(rc, 0, out)
        self.assertIn("NOTE: changed outside this run (not touched): instances sinter-new-x", out)
        self.assertIn("sinter-new-x", self.mock()["res"]["instances"])

    def test_new_external_address_stops(self):
        self.hs("init")
        self.set_mock(lambda s: s["res"]["addresses"].update({"some-ip": {"name": "some-ip", "id": "99"}}))
        rc, out = self.hs("create-network")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("external address", out)

    def test_instance_with_external_ip_stops_and_is_torn_down(self):
        self.up()
        self.set_mock(lambda s: s.update(external_ip=True))
        rc, out = self.hs("create-node", "n1")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("external address", out)
        self.assertEqual(self.events("n1"), ["create-requested", "created"])
        rc, out = self.hs("teardown")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.events("n1")[-1], "deleted")


# 8, 9 — resource id and ledger integrity
class LedgerAndIds(Base):
    def test_resource_id_mismatch_blocks_delete(self):
        self.up("n1")
        n = "hagistack-s6-%s-n1" % RID
        self.set_mock(lambda s: s["res"]["instances"][n].update(id="424242"))
        rc, out = self.hs("delete-node", "n1")
        self.assertEqual(rc, hs6.EXIT_CLEANUP, out)
        self.assertIn("not the resource this run created", out)
        self.assertIn(n, self.mock()["res"]["instances"])

    def test_creation_time_mismatch_blocks_delete(self):
        self.up("n1")
        n = "hagistack-s6-%s-n1" % RID
        self.set_mock(lambda s: s["res"]["instances"][n].update(creationTimestamp="2026-11-20T00:00:00.000-00:00"))
        rc, out = self.hs("delete-node", "n1")
        self.assertEqual(rc, hs6.EXIT_CLEANUP, out)

    def test_label_lost_blocks_delete(self):
        self.up("n1")
        n = "hagistack-s6-%s-n1" % RID
        self.set_mock(lambda s: s["res"]["instances"][n].update(labels={}))
        rc, out = self.hs("delete-node", "n1")
        self.assertEqual(rc, hs6.EXIT_CLEANUP, out)
        self.assertIn(n, self.mock()["res"]["instances"])

    def _break_and_check(self, breaker):
        self.up("n1")
        breaker()
        before = len(self.mutations())
        for args in (("create-node", "n2"), ("delete-node", "n1"), ("teardown",)):
            rc, out = self.hs(*args)
            self.assertEqual(rc, hs6.EXIT_LEDGER, out)
        self.assertEqual(len(self.mutations()), before)
        self.assertIn("hagistack-s6-%s-n1" % RID, self.mock()["res"]["instances"])

    def test_ledger_missing(self):
        self._break_and_check(lambda: os.unlink(os.path.join(self.sdir, "ledger.jsonl")))

    def test_ledger_head_missing(self):
        self._break_and_check(lambda: os.unlink(os.path.join(self.sdir, "ledger.head")))

    def test_ledger_edited(self):
        p = os.path.join(self.sdir, "ledger.jsonl")

        def edit():
            lines = open(p).read().splitlines()
            self.assertIn('"create-requested"', lines[1])
            lines[1] = lines[1].replace('"create-requested"', '"created"')
            open(p, "w").write("\n".join(lines) + "\n")
        self._break_and_check(edit)

    def test_ledger_truncated(self):
        p = os.path.join(self.sdir, "ledger.jsonl")
        self._break_and_check(lambda: open(p, "w").write("".join(open(p).readlines()[:-1])))

    def test_ledger_not_json(self):
        p = os.path.join(self.sdir, "ledger.jsonl")
        self._break_and_check(lambda: open(p, "a").write("garbage\n"))

    def test_baseline_tampered(self):
        p = os.path.join(self.sdir, "baseline.json")
        self._break_and_check(lambda: open(p, "a").write(" "))

    def test_state_dir_reuse_refused(self):
        self.up()
        rc, out = self.hs("init")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)


# 10–15, 18, 28 — errors
class Errors(Base):
    def test_iam_error_stops_at_once(self):
        self.hs("init")
        self.inject("networks create", "PERMISSION")
        rc, out = self.hs("create-network")
        self.assertEqual(rc, hs6.EXIT_IAM, out)
        self.assertEqual(self.events("net"), ["create-requested", "create-failed"])
        self.assertEqual(self.events("subnet"), [])

    def test_quota_error(self):
        self.up()
        self.inject("instances create", "QUOTA")
        rc, out = self.hs("create-node", "n1")
        self.assertEqual(rc, hs6.EXIT_QUOTA, out)
        self.assertEqual(self.events("n1"), ["create-requested", "create-failed"])

    def test_quota_shortfall_at_init(self):
        self.set_mock(lambda s: s["quotas"]["region"].__setitem__(0, {"metric": "N2_CPUS", "limit": 16, "usage": 0}))
        rc, out = self.hs("init")
        self.assertEqual(rc, hs6.EXIT_QUOTA, out)
        self.assertFalse(os.path.exists(os.path.join(self.sdir, "ledger.jsonl")))

    def test_api_timeout_on_create(self):
        self.up()
        self.inject("instances create", "TIMEOUT")
        rc, out = self.hs("create-node", "n1")
        self.assertEqual(rc, hs6.EXIT_UNKNOWN, out)
        self.assertEqual(self.events("n1"), ["create-requested", "unknown"])
        rc, out = self.hs("status", approval=False)
        self.assertIn('"running_nodes": 1', out)  # counted as running while unknown
        rc, out = self.hs("teardown")
        self.assertEqual(rc, hs6.EXIT_CLEANUP, out)
        self.assertIn("may still finish", out)
        self.t += hs6.SETTLE_SECONDS + 60
        rc, out = self.hs("teardown")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.events("n1")[-1], "create-failed")

    def test_late_creation_after_timeout_is_adopted_and_deleted(self):
        self.up()
        n = "hagistack-s6-%s-n1" % RID
        self.inject("instances create", "CREATE_DEFERRED")
        rc, out = self.hs("create-node", "n1")
        self.assertEqual(rc, hs6.EXIT_UNKNOWN, out)
        self.assertEqual(self.events("n1"), ["create-requested", "unknown"])
        rc, out = self.hs("create-node", "n2")
        self.assertIn("unresolved", out)
        self.assertIn(n, self.mock()["res"]["instances"])  # GCE finished it meanwhile
        rc, out = self.hs("teardown")
        self.assertEqual(rc, 0, out)
        self.assertNotIn(n, self.mock()["res"]["instances"])
        self.assertNotIn(n, self.mock()["res"]["disks"])
        self.assertEqual(self.events("n1")[-2:], ["created", "deleted"])

    def test_gcloud_crash_is_not_taken_as_absent(self):
        self.up("n1")
        n = "hagistack-s6-%s-n1" % RID
        self.inject("instances describe", "CRASH", times=5)
        rc, out = self.hs("teardown")
        self.assertEqual(rc, hs6.EXIT_CLEANUP, out)
        self.assertIn(n, self.mock()["res"]["instances"])
        self.assertNotEqual(self.events("n1")[-1], "deleted")

    def test_timeout_when_reconciling_is_unknown_and_never_auto_deleted(self):
        self.up()
        self.inject("instances create", "CREATE_THEN_ERROR")
        self.inject("instances describe", "TIMEOUT", times=3, skip=1)  # skip the collision check
        rc, out = self.hs("create-node", "n1")
        self.assertEqual(rc, hs6.EXIT_UNKNOWN, out)
        self.assertEqual(self.events("n1")[-1], "unknown")
        rc, out = self.hs("teardown")
        self.assertEqual(rc, hs6.EXIT_CLEANUP, out)
        self.assertIn("manual check", out)
        self.assertIn("hagistack-s6-%s-n1" % RID, self.mock()["res"]["instances"])
        self.assertIn("hagistack-s6-%s-net" % RID, self.mock()["res"]["networks"])  # network kept

    def test_partial_creation_is_recorded_and_torn_down(self):
        self.hs("init")
        self.inject("subnets create", "CREATE_THEN_ERROR")
        rc, out = self.hs("create-network")
        self.assertEqual(rc, hs6.EXIT_UNKNOWN, out)
        self.assertEqual(self.events("net"), ["create-requested", "created"])
        self.assertEqual(self.events("subnet"), ["create-requested", "created"])
        self.assertEqual(self.events("fw-iap"), [])
        rc, out = self.hs("teardown")
        self.assertEqual(rc, 0, out)
        self.assertNotIn("hagistack-s6-%s-subnet" % RID, self.mock()["res"]["subnets"])
        self.assertNotIn("hagistack-s6-%s-net" % RID, self.mock()["res"]["networks"])

    def test_network_failure_midway_then_no_retry(self):
        self.hs("init")
        self.inject("firewall-rules create hagistack-s6-%s-fw-int" % RID, "ERROR")
        rc, out = self.hs("create-network")
        self.assertEqual(rc, hs6.EXIT_UNKNOWN, out)
        self.assertEqual(self.events("fw-int"), ["create-requested", "unknown"])
        rc, out = self.hs("create-network")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        rc, out = self.hs("create-node", "n1")
        self.assertIn("unresolved", out)
        self.t += hs6.SETTLE_SECONDS + 60
        rc, out = self.hs("teardown")
        self.assertEqual(rc, 0, out)
        self.assertEqual([n for n in self.mock()["res"]["networks"] if n.startswith("hagistack")], [])

    def test_create_failure_no_retry(self):
        self.up()
        self.inject("instances create", "QUOTA")
        rc, out = self.hs("create-node", "n1")
        self.assertEqual(rc, hs6.EXIT_QUOTA, out)
        rc, out = self.hs("create-node", "n1")
        self.assertIn("no automatic retry", out)
        self.assertEqual(sum(1 for c in self.mutations() if "instances" in c and "create" in c), 1)

    def test_delete_failure_noop(self):
        self.up("n1")
        self.inject("instances delete", "DELETE_NOOP")
        rc, out = self.hs("teardown")
        self.assertEqual(rc, hs6.EXIT_CLEANUP, out)
        self.assertEqual(self.events("n1")[-1], "delete-failed")
        self.assertIn("hagistack-s6-%s-net" % RID, self.mock()["res"]["networks"])
        rc, out = self.hs("create-node", "n2")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("unresolved", out)
        rc, out = self.hs("ssh", "n1", "--", "true")
        self.assertIn("unresolved", out)
        rc, out = self.hs("teardown")  # a failed deletion is checked again and retried by the next teardown
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.events("n1")[-1], "deleted")

    def test_delete_permission_error(self):
        self.up("n1")
        self.inject("instances delete", "PERMISSION")
        rc, out = self.hs("delete-node", "n1")
        self.assertEqual(rc, hs6.EXIT_CLEANUP, out)
        self.assertEqual(self.events("n1")[-1], "delete-failed")

    def test_boot_disk_left_behind(self):
        self.up("n1")
        self.inject("instances delete", "KEEP_DISK")
        rc, out = self.hs("delete-node", "n1")
        self.assertEqual(rc, hs6.EXIT_CLEANUP, out)
        self.assertIn("boot disk", out)


# 16 — double execution and ordering
class Concurrency(Base):
    def test_lock_held(self):
        self.up()
        open(os.path.join(self.sdir, "run.lock"), "w").close()
        rc, out = self.hs("create-node", "n1")
        self.assertEqual(rc, hs6.EXIT_LOCK, out)
        self.assertEqual(self.events("n1"), [])

    def test_ordering(self):
        self.up()
        rc, out = self.hs("create-node", "n3")
        self.assertIn("controller n1 must exist", out)
        self.hs("create-node", "n1")
        self.hs("create-node", "n4")
        rc, out = self.hs("create-node", "u1")
        self.assertIn("only after n4 is deleted", out)
        self.assertEqual(rc, hs6.EXIT_REFUSED)


# 17, 19, 21, 22 — cost and time (in-process on synthetic ledgers, and end to end)
class CostGuards(Base):
    def recs(self, created):
        r = [{"kind": "header"}]
        for part, hours_ago in created.items():
            ts = hs6.iso(self.t - hours_ago * 3600)
            r.append({"part": part, "event": "create-requested", "recorded_at": ts})
            r.append({"part": part, "event": "created", "created_at": ts})
        return r

    def test_projected_7_blocks_new_resources_only(self):
        recs = self.recs({"nat": 5.0, "n1": 5.0, "n2": 4.4, "n3": 4.4, "n4": 3.7})
        rep = hs6.cost_report(recs, self.t)
        self.assertGreaterEqual(rep["projected_usd"], 7.0)
        self.assertLess(rep["accrued_usd"], 8.0)
        hs6.guard(recs, self.t)  # tests may continue
        with self.assertRaises(hs6.Stop) as c:
            hs6.guard(recs, self.t, creating=True)
        self.assertEqual(c.exception.code, hs6.EXIT_GUARD)
        self.assertIn("projected", str(c.exception))

    def test_accrued_8_stops(self):
        recs = self.recs({"nat": 8, "n1": 8, "n2": 8, "n3": 8, "n4": 8})
        with self.assertRaises(hs6.Stop) as c:
            hs6.guard(recs, self.t)
        self.assertIn("accrued", str(c.exception))
        self.assertIn("tear down", str(c.exception))

    def test_six_hours(self):
        with self.assertRaises(hs6.Stop) as c:
            hs6.guard(self.recs({"nat": 6.0, "n1": 5.5}), self.t)
        self.assertIn("elapsed", str(c.exception))
        self.assertTrue(c.exception.teardown)

    def test_node_overrun(self):
        with self.assertRaises(hs6.Stop) as c:
            hs6.guard(self.recs({"n4": 3.8}), self.t)
        self.assertIn("50%", str(c.exception))
        self.assertTrue(c.exception.teardown)

    def test_monitor_failure_does_not_tear_down(self):
        r = self.recs({"n1": 1.0})
        r[-1]["created_at"] = "not a time"
        with self.assertRaises(hs6.Stop) as c:
            hs6.guard(r, self.t)
        self.assertFalse(c.exception.teardown)  # cost unknown: stop new work, never act on a broken view

    def test_unknown_and_failed_resources_in_cost(self):
        r = self.recs({"n1": 1.0})
        r.append({"part": "n2", "event": "create-requested", "recorded_at": hs6.iso(self.t - 3600)})
        r.append({"part": "n2", "event": "unknown"})
        r.append({"part": "n3", "event": "create-requested", "recorded_at": hs6.iso(self.t - 3600)})
        r.append({"part": "n3", "event": "create-failed"})
        rep = hs6.cost_report(r, self.t)
        self.assertEqual(rep["running_nodes"], 2)  # n1 and the unknown n2
        self.assertFalse(rep["final"])

    def test_monitor_failure_stops(self):
        r = self.recs({"n1": 1.0})
        r[-1]["created_at"] = "not a time"
        with self.assertRaises(hs6.Stop) as c:
            hs6.guard(r, self.t)
        self.assertIn("monitor failed", str(c.exception))

    def test_guards_end_to_end(self):
        self.up("n1", "n2")
        self.t += 4.6 * 3600  # n2 is more than 50 % over its 3 h
        rc, out = self.hs("status", approval=False)  # status only reports
        self.assertEqual(rc, hs6.EXIT_GUARD, out)
        self.assertIn("NOT the Google Cloud bill", out)
        self.assertIn("hagistack-s6-%s-n1" % RID, self.mock()["res"]["instances"])
        rc, out = self.hs("teardown")  # an explicit teardown is never refused by the guards
        self.assertEqual(rc, 0, out)
        self.assertEqual([n for k, v in self.mock()["res"].items() for n in v if n.startswith("hagistack")], [])

    def test_plan_estimate_within_budget(self):
        rep = hs6.cost_report([{"kind": "header"}], self.t)
        self.assertLess(rep["projected_usd"], hs6.COST_STOP_NEW)


# 24 — other products are never touched
class Protection(Base):
    def test_mutate_refuses_foreign_names(self):
        g = hs6.Gcloud(RID, True, lambda m: None)
        self.assertNotEqual(g.bin, "gcloud")  # the sentinel, not the real CLI
        for name in (SINTER_INSTANCE, "mkg-proto-vpc", "default", "hagistack-s6-other-n1",
                     "hagistack-s6-%s-n1x" % RID, "hagistack-s6-%s-" % RID):
            with self.assertRaises(hs6.Stop):
                g.mutate(["compute", "instances", "delete", name, "--zone=" + hs6.ZONE, "--project=" + hs6.PROJECT], name)
        n1 = "hagistack-s6-%s-n1" % RID
        for bad in (["compute", "instances", "delete", "x"], ["compute", "instances", "add-metadata", n1],
                    ["auth", "revoke"], ["compute", "project-info", "add-metadata"], ["config", "set", "account", "x"]):
            with self.assertRaises(hs6.Stop):
                g.read(bad)
        for bad in (["compute", "instances", "delete", n1, SINTER_INSTANCE, "--project=" + hs6.PROJECT],
                    ["compute", "instances", "delete", n1, "--project=" + hs6.PROJECT, "--project=other"],
                    ["compute", "instances", "delete", n1],
                    ["compute", "instances", "add-metadata", n1, "--project=" + hs6.PROJECT],
                    ["compute", "project-info", "add-metadata", n1, "--project=" + hs6.PROJECT]):
            with self.assertRaises(hs6.Stop):
                g.mutate(bad, n1)
        with self.assertRaises(hs6.Stop):  # target must be in the command
            n = "hagistack-s6-%s-n1" % RID
            g.mutate(["compute", "instances", "delete", SINTER_INSTANCE, "--project=" + hs6.PROJECT], n)
        self.assertNotIn("calls", self.mock())

    def test_cli_takes_no_foreign_name(self):
        rc, out = self.hs("delete-node", SINTER_INSTANCE)
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)

    def test_full_run_touches_only_its_own_resources(self):
        before = self.mock()["res"]
        self.up("n1", "n2", "n3", "n4")
        rc, out = self.hs("delete-node", "n4")
        self.assertEqual(rc, 0, out)
        rc, out = self.hs("create-node", "u1")
        self.assertEqual(rc, 0, out)
        rc, out = self.hs("status", approval=False)
        self.assertEqual(rc, 0, out)
        rc, out = self.hs("teardown")
        self.assertEqual(rc, 0, out)
        rc, out = self.hs("residual")
        self.assertEqual(rc, 0, out)
        after = self.mock()["res"]
        for kind in before:
            self.assertEqual({k: v for k, v in after.get(kind, {}).items()}, before[kind], kind)
        for c in self.mutations():
            names = [a for a in c if not a.startswith("-")]
            self.assertTrue(any(a.startswith("hagistack-s6-%s-" % RID) for a in names), c)
            self.assertFalse(any(a.startswith(("sinter", "mkg")) for a in names), c)
        recs = self.ledger()
        for r in recs[1:]:
            if r["event"] == "created" and r["part"] in hs6.NODES:
                self.assertEqual(r["disk_type"], "pd-standard")
                self.assertEqual(r["disk_gb"], hs6.NODES[r["part"]][2])
                self.assertTrue(r["gce_id"])
        hs6.Ledger(self.sdir).load()  # still a valid chain


class Upload(Base):
    def test_upload_checksum(self):
        self.up("n1")
        f = os.path.join(self.tmp, "a.bin")
        with open(f, "wb") as fh:
            fh.write(b"x" * 100)
        rc, out = self.hs("upload", "n1", f, "/tmp/a.bin")
        self.assertEqual(rc, hs6.EXIT_REMOTE, out)
        self.assertIn("SHA-256 check failed", out)
        want = hashlib.sha256(b"x" * 100).hexdigest()
        self.set_mock(lambda s: s.update(remote_sha={"/tmp/a.bin": want}))
        rc, out = self.hs("upload", "n1", f, "/tmp/a.bin")
        self.assertEqual(rc, 0, out)


class Download(Base):
    def test_download_is_kept_only_when_the_checksum_matches(self):
        self.up("n1")
        self.set_mock(lambda s: s.update(remote_files={"/root/out.tar": "payload"}))
        rc, out = self.hs("download", "n1", "/root/out.tar", "out.tar")
        self.assertEqual(rc, hs6.EXIT_REMOTE, out)
        self.assertIn("SHA-256 check failed", out)
        ddir = os.path.join(self.sdir, "downloads")
        self.assertEqual(os.listdir(ddir), [], "an unverified download is not kept")
        want = hashlib.sha256(b"payload").hexdigest()
        self.set_mock(lambda s: s.update(remote_sha={"/root/out.tar": want}))
        rc, out = self.hs("download", "n1", "/root/out.tar", "out.tar")
        self.assertEqual(rc, 0, out)
        self.assertIn("download verified", out)
        with open(os.path.join(ddir, "out.tar")) as f:
            self.assertEqual(f.read(), "payload")
        self.assertEqual(stat.S_IMODE(os.stat(ddir).st_mode), 0o700)

    def test_download_never_overwrites(self):
        self.up("n1")
        want = hashlib.sha256(b"payload").hexdigest()
        self.set_mock(lambda s: s.update(remote_files={"/root/out.tar": "payload"},
                                         remote_sha={"/root/out.tar": want}))
        self.assertEqual(self.hs("download", "n1", "/root/out.tar", "out.tar")[0], 0)
        self.set_mock(lambda s: s.update(remote_files={"/root/out.tar": "other"}))
        rc, out = self.hs("download", "n1", "/root/out.tar", "out.tar")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("exists already", out)
        with open(os.path.join(self.sdir, "downloads", "out.tar")) as f:
            self.assertEqual(f.read(), "payload")

    def test_download_refuses_a_linked_downloads_directory(self):
        self.up("n1")
        elsewhere = os.path.join(self.tmp, "elsewhere")
        os.makedirs(elsewhere)
        os.symlink(elsewhere, os.path.join(self.sdir, "downloads"))
        want = hashlib.sha256(b"payload").hexdigest()
        self.set_mock(lambda s: s.update(remote_files={"/root/out.tar": "payload"},
                                         remote_sha={"/root/out.tar": want}))
        rc, out = self.hs("download", "n1", "/root/out.tar", "out.tar")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("not a directory of this user", out)
        self.assertEqual(os.listdir(elsewhere), [])

    def test_download_refuses_odd_paths_and_names(self):
        self.up("n1")
        for remote, name in (("relative/x", "x"), ("/root/../etc/x", "x"), ("/root/x;rm", "x"),
                             ("/root/x", "../x"), ("/root/x", "a/b"), ("/root/x", ".hidden"),
                             ("/root/x", "x.part"), ("/root/x", "")):
            with self.subTest(remote=remote, name=name):
                rc, out = self.hs("download", "n1", remote, name)
                self.assertNotEqual(rc, 0, out)
                self.assertIn("download:", out)

    def test_download_needs_the_operation_in_the_approval(self):
        self.write_approval(operations=["init", "network", "n1", "ssh", "upload", "teardown", "residual"])
        self.up("n1")
        self.set_mock(lambda s: s.update(remote_files={"/root/out.tar": "payload"},
                                         remote_sha={"/root/out.tar": hashlib.sha256(b"payload").hexdigest()}))
        rc, out = self.hs("download", "n1", "/root/out.tar", "out.tar")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("download", out)
        self.assertFalse(os.path.exists(os.path.join(self.sdir, "downloads", "out.tar")))


class GateHardening(Base):
    def refused(self, *args, **kw):
        rc, out = self.hs(*args, **kw)
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertEqual(self.mutations(), [])
        return out

    def test_stubs_refused_with_a_real_account(self):
        self.write_approval(account="owner@example.com")
        self.assertIn("tests only", self.refused("init"))
        self.assertIn("tests only", self.refused("init", env={"HS6_GCLOUD": None}))  # HS6_NOW alone
        self.assertNotIn("calls", self.mock())

    def test_test_account_needs_the_stub(self):
        self.assertIn("test account", self.refused("init", env={"HS6_GCLOUD": None, "HS6_NOW": None}))

    def test_hs6_execute_without_approval(self):
        self.assertIn("no approval file", self.refused("init", approval=False, env={"HS6_EXECUTE": RID}))

    def test_identity_overrides_refused(self):
        for k in ("CLOUDSDK_CORE_ACCOUNT", "CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT"):
            self.assertIn(k, self.refused("init", env={k: "x@example.invalid"}))
        self.set_mock(lambda s: s.update(config={"auth/impersonate_service_account": "sa@example.invalid"}))
        self.assertIn("impersonate", self.refused("init"))

    def test_every_call_carries_the_account(self):
        self.up("n1")
        for c in self.mock()["calls"]:
            if c[:2] in (["config", "get-value"], ["auth", "list"]):
                # the account check reads gcloud's own configuration, so not overridden
                self.assertNotIn("--account=" + ACCOUNT, c)
            else:
                self.assertIn("--account=" + ACCOUNT, c)

    def test_credential_file_override_refused(self):
        self.set_mock(lambda s: s.update(config={"auth/credential_file_override": "/x.json"}))
        self.assertIn("credential file", self.refused("init"))
        self.assertIn("CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE",
                      self.refused("init", env={"CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE": "/x.json"}))

    def test_registry_override_refused_with_a_real_account(self):
        self.write_approval(account="owner@example.com")
        self.assertIn("tests only", self.refused("init", env={"HS6_GCLOUD": None, "HS6_NOW": None}))

    def test_teardown_must_be_approved(self):
        self.write_approval(operations=["init", "network", "n1"])
        self.assertIn("must include teardown", self.refused("init"))

    def test_remote_failure_keeps_output_and_status(self):
        self.up("n1")
        self.inject("compute ssh", "SSH_FAIL")
        rc, out = self.hs("ssh", "n1", "--", "false")
        self.assertEqual(rc, hs6.EXIT_REMOTE, out)
        logs = os.listdir(os.path.join(self.sdir, "remote"))
        self.assertEqual(len(logs), 1)
        text = open(os.path.join(self.sdir, "remote", logs[0])).read()
        self.assertIn("rc=3", text)
        self.assertIn("x" * 1000, text)
        self.assertIn("step failed", text)

    def test_lock_not_held_while_the_remote_command_runs(self):
        self.up("n1")
        rc, out = self.hs("ssh", "n1", "--", "true", env={"MOCK_LOCKFILE": os.path.join(self.sdir, "run.lock")})
        self.assertEqual(rc, 0, out)
        self.assertIs(self.mock()["lock_seen_during_ssh"], False)

    def test_max_run_duration_shrinks_with_the_run_time_left(self):
        self.up("n1")
        self.t += 3.0 * 3600
        rc, out = self.hs("create-node", "n2")
        self.assertEqual(rc, 0, out)
        cmd = [r for r in self.ledger() if r.get("part") == "n2" and r["event"] == "create-requested"][0]["command"]
        self.assertIn("--max-run-duration=3h", cmd)  # 6 h limit - 3 h elapsed, below 3 h x 1.5

    def test_create_flags(self):
        self.up("n1")
        cmd = [r for r in self.ledger() if r.get("part") == "n1" and r["event"] == "create-requested"][0]["command"]
        for f in ("--no-address", "--no-service-account", "--no-scopes", "--metadata=block-project-ssh-keys=TRUE",
                  "--max-run-duration=6h", "--instance-termination-action=DELETE", "--boot-disk-type=pd-standard",
                  "--boot-disk-size=100GB", "--enable-nested-virtualization", "--image=rocky-linux-10-v20261110"):
            self.assertIn(f, cmd)
        delete = [c for c in self.mutations() if "delete" in c]
        self.assertEqual(delete, [])

    def test_approval_budget_lowers_the_limits(self):
        self.write_approval(budget_usd=0.5)
        self.hs("init")
        rc, out = self.hs("create-network")
        self.assertEqual(rc, hs6.EXIT_GUARD, out)

    def test_approval_max_hours_lowers_the_limit(self):
        self.write_approval(max_hours=1)
        self.up("n1")
        self.t += 1.1 * 3600
        rc, out = self.hs("ssh", "n1", "--", "true")
        self.assertEqual(rc, hs6.EXIT_GUARD, out)
        self.assertIn("1.00h", out)

    def test_teardown_works_after_the_approval_expired(self):
        self.up("n1")
        self.t = T0 + 21 * 3600
        rc, out = self.hs("create-node", "n2")
        self.assertIn("not valid now", out)
        rc, out = self.hs("teardown")
        self.assertEqual(rc, 0, out)
        self.assertEqual([n for n in self.mock()["res"]["instances"] if n.startswith("hagistack")], [])

    def test_run_id_never_reused(self):
        self.up()
        self.assertEqual(self.hs("teardown")[0], 0)
        self.sdir = os.path.join(self.tmp, "run2")
        os.makedirs(self.sdir)
        rc, out = self.hs("init")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("never reused", out)

    def test_ssh_that_writes_project_metadata_stops(self):
        self.up("n1")
        self.inject("compute ssh", "METADATA_CHANGE")
        rc, out = self.hs("ssh", "n1", "--", "true")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("ssh-keys changed", out)
        rc, out = self.hs("ssh", "n1", "--", "true")
        self.assertIn("differ from the baseline", out)

    def test_unrelated_project_metadata_change_does_not_stop(self):
        self.up("n1")
        self.set_mock(lambda s: s.update(project_metadata={"fingerprint": "other", "items": [{"key": "x", "value": "y"}]}))
        rc, out = self.hs("ssh", "n1", "--", "true")
        self.assertEqual(rc, 0, out)

    def test_accrued_limit_tears_down_automatically(self):
        self.up("n1", "n2", "n3", "n4")
        self.t += 8 * 3600
        rc, out = self.hs("ssh", "n1", "--", "true")
        self.assertEqual(rc, hs6.EXIT_GUARD, out)
        self.assertIn("tearing down", out)
        res = self.mock()["res"]
        self.assertEqual([n for k in res for n in res[k] if n.startswith("hagistack")], [])
        self.assertIn(SINTER_INSTANCE, res["instances"])

    def test_dry_run_of_remote_and_residual(self):
        f = os.path.join(self.tmp, "x")
        open(f, "w").close()
        for args in (("ssh", "n1", "--", "true"), ("upload", "n1", f, "/tmp/x"), ("residual",)):
            rc, out = self.hs(*args, approval=False)
            self.assertEqual(rc, 0, out)
            self.assertIn("DRY-RUN", out)
        self.assertNotIn("calls", self.mock())

    def test_nat_identity_checked_on_delete(self):
        self.up()
        r = "hagistack-s6-%s-router" % RID
        self.set_mock(lambda s: s["res"]["routers"][r].update(id="999999"))
        rc, out = self.hs("teardown")
        self.assertEqual(rc, hs6.EXIT_CLEANUP, out)
        self.assertIn("hagistack-s6-%s-nat" % RID, self.mock()["res"]["nats"])


class R2Teardown(Base):
    def gone(self):
        return [n for k, v in self.mock()["res"].items() for n in v if n.startswith("hagistack")] == []

    def events_kind(self):
        return [r["event"] for r in self.ledger() if r.get("kind") == "event"]

    def test_six_hours_stops_and_tears_down(self):
        self.up()
        self.t += 2 * 3600
        self.assertEqual(self.hs("create-node", "n1")[0], 0)
        self.t += 4.05 * 3600  # elapsed 6.05 h, n1 only 4.05 h (no overrun)
        rc, out = self.hs("ssh", "n1", "--", "true")
        self.assertEqual(rc, hs6.EXIT_GUARD, out)
        self.assertIn("elapsed", out)
        self.assertTrue(self.gone())
        self.assertEqual(self.events_kind(), ["guard-stop", "teardown-started", "teardown-complete"])

    def test_node_overrun_stops_and_tears_down(self):
        self.up("n1", "n4")
        self.t += 3.8 * 3600
        rc, out = self.hs("create-node", "n2")
        self.assertEqual(rc, hs6.EXIT_GUARD, out)
        self.assertIn("50%", out)
        self.assertTrue(self.gone())
        self.assertEqual(self.events("n2"), [])

    def test_accrued_limit_records_stop_and_completion_separately(self):
        self.up("n1", "n2", "n3", "n4")
        self.t += 8 * 3600
        rc, out = self.hs("ssh", "n2", "--", "true")
        self.assertEqual(rc, hs6.EXIT_GUARD, out)
        ev = [r for r in self.ledger() if r.get("kind") == "event"]
        self.assertEqual([e["event"] for e in ev], ["guard-stop", "teardown-started", "teardown-complete"])
        self.assertIn("accrued", ev[0]["reason"])
        self.assertEqual(ev[-1]["remaining"], [])

    def test_failed_auto_teardown_is_not_success_and_keeps_the_network(self):
        self.up("n1")
        self.inject("instances delete", "DELETE_NOOP")
        self.t += 6.1 * 3600
        rc, out = self.hs("ssh", "n1", "--", "true")
        self.assertEqual(rc, hs6.EXIT_CLEANUP, out)
        self.assertIn("teardown incomplete", out)
        self.assertIn("n1", out)
        self.assertIn("hagistack-s6-%s-net" % RID, self.mock()["res"]["networks"])
        self.assertEqual(self.events_kind()[-1], "teardown-incomplete")

    def test_auto_teardown_refuses_a_foreign_id(self):
        self.up("n1")
        n = "hagistack-s6-%s-n1" % RID
        self.set_mock(lambda s: s["res"]["instances"][n].update(id="555"))
        self.t += 6.1 * 3600
        rc, out = self.hs("ssh", "n1", "--", "true")
        self.assertEqual(rc, hs6.EXIT_CLEANUP, out)
        self.assertIn(n, self.mock()["res"]["instances"])
        self.assertIn("hagistack-s6-%s-net" % RID, self.mock()["res"]["networks"])

    def test_vm_deleted_by_gce_leaves_the_network_until_teardown(self):
        self.up("n1")
        n = "hagistack-s6-%s-n1" % RID

        def gce_max_run(s):
            s["res"]["instances"].pop(n)
            s["res"]["disks"].pop(n)
        self.set_mock(gce_max_run)
        rc, out = self.hs("residual")
        self.assertEqual(rc, hs6.EXIT_CLEANUP, out)
        self.assertIn("nat hagistack-s6-%s-nat" % RID, out)
        self.assertIn("networks hagistack-s6-%s-net" % RID, out)
        rc, out = self.hs("status", approval=False)
        self.assertIn("never deleted by GCE itself", out)
        rc, out = self.hs("teardown")
        self.assertEqual(rc, 0, out)
        self.assertIn("%s: absent" % n, out)
        self.assertEqual(self.hs("residual")[0], 0)

    def _popen(self, args, extra):
        e = dict(self.env, HS6_EXECUTE=RID, HS6_WATCH_INTERVAL="1")
        e.update(extra)
        return subprocess.Popen([sys.executable, "-I", HS6, "--run-id", RID, "--state-dir", self.sdir,
                                 "--approval", self.approval] + args,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=e)

    def test_ssh_is_monitored_and_stopped_while_it_runs(self):
        self.up("n1")
        clock = os.path.join(self.tmp, "clock")
        with open(clock, "w") as f:
            f.write(str(self.t))
        self.inject("compute ssh", "SLEEP")
        start = time.monotonic()
        p = self._popen(["ssh", "n1", "--", "long-step"], {"HS6_CLOCK_FILE": clock, "MOCK_SLEEP": "30"})
        time.sleep(3)
        with open(clock, "w") as f:
            f.write(str(self.t + 7 * 3600))
        out, _ = p.communicate(timeout=60)
        self.assertLess(time.monotonic() - start, 25, out)
        self.assertEqual(p.returncode, hs6.EXIT_GUARD, out)
        self.assertNotIn("ssh_finished", self.mock())  # the step was killed
        logs = os.listdir(os.path.join(self.sdir, "remote"))
        with open(os.path.join(self.sdir, "remote", logs[0])) as f:
            self.assertIn("stopped while running", f.read())
        self.assertTrue(self.gone())

    def test_watch_tears_down_on_a_limit(self):
        self.up("n1")
        rc, out = self.hs("watch", env={"HS6_WATCH_MAX_LOOPS": "1", "HS6_WATCH_INTERVAL": "0"})
        self.assertEqual(rc, 0, out)
        self.assertIn("within limits", out)
        self.t += 6.1 * 3600
        rc, out = self.hs("watch", env={"HS6_WATCH_INTERVAL": "0"})
        self.assertEqual(rc, hs6.EXIT_GUARD, out)
        self.assertTrue(self.gone())
        rc, out = self.hs("watch", env={"HS6_WATCH_INTERVAL": "0"})
        self.assertEqual(rc, 0, out)
        self.assertIn("has been torn down", out)

    def test_watch_killed_leaves_no_lock_and_teardown_still_works(self):
        self.up("n1")
        p = self._popen(["watch"], {"HS6_NOW": str(self.t), "HS6_WATCH_INTERVAL": "30"})
        time.sleep(3)
        p.kill()
        p.communicate()
        self.assertFalse(os.path.exists(os.path.join(self.sdir, "run.lock")))
        rc, out = self.hs("teardown")
        self.assertEqual(rc, 0, out)
        self.assertTrue(self.gone())

    def test_sigterm_during_ssh_stops_the_step(self):
        self.up("n1")
        self.inject("compute ssh", "SLEEP")
        p = self._popen(["ssh", "n1", "--", "long-step"], {"HS6_NOW": str(self.t), "MOCK_SLEEP": "20"})
        time.sleep(3)
        p.terminate()
        out, _ = p.communicate(timeout=60)
        time.sleep(1)
        self.assertNotIn("ssh_finished", self.mock())  # the step did not keep running
        self.assertIn("interrupted", out)

    def test_harness_killed_during_ssh_leaves_no_lock(self):
        self.up("n1")
        self.inject("compute ssh", "SLEEP")
        p = self._popen(["ssh", "n1", "--", "long-step"], {"HS6_NOW": str(self.t), "MOCK_SLEEP": "20"})
        time.sleep(3)
        p.kill()
        p.communicate()
        self.assertFalse(os.path.exists(os.path.join(self.sdir, "run.lock")))
        rc, out = self.hs("teardown")
        self.assertEqual(rc, 0, out)


class R2Approval(Base):
    def test_symlinked_approval_refused(self):
        link = os.path.join(self.tmp, "link.json")
        os.symlink(self.approval, link)
        e = dict(self.env, HS6_EXECUTE=RID, HS6_NOW=str(self.t))
        p = subprocess.run([sys.executable, "-I", HS6, "--run-id", RID, "--state-dir", self.sdir, "--approval", link,
                            "init"], capture_output=True, text=True, env=e)
        self.assertEqual(p.returncode, hs6.EXIT_REFUSED, p.stderr)
        self.assertIn("symbolic link", p.stderr)
        self.assertNotIn("calls", self.mock())

    def test_writable_approval_refused(self):
        os.chmod(self.approval, 0o664)
        rc, out = self.hs("init")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("writable by group or others", out)
        os.chmod(self.approval, 0o644)
        os.chmod(self.tmp, 0o777)
        try:
            rc, out = self.hs("init")
            self.assertEqual(rc, hs6.EXIT_REFUSED, out)
            self.assertIn("directory holding the approval", out)
        finally:
            os.chmod(self.tmp, 0o700)
        self.assertNotIn("calls", self.mock())

    def test_approval_inside_repository_or_state_dir_refused(self):
        with self.assertRaises(hs6.Stop) as c:
            hs6.check_approval_file(HS6)  # any file in the repository
        self.assertIn("inside the repository", str(c.exception))
        inside = os.path.join(self.sdir, "approval.json")
        shutil.copy(self.approval, inside)
        os.chmod(inside, 0o644)
        e = dict(self.env, HS6_EXECUTE=RID, HS6_NOW=str(self.t))
        p = subprocess.run([sys.executable, "-I", HS6, "--run-id", RID, "--state-dir", self.sdir, "--approval", inside,
                            "init"], capture_output=True, text=True, env=e)
        self.assertEqual(p.returncode, hs6.EXIT_REFUSED, p.stderr)
        self.assertIn("state directory", p.stderr)

    def test_hard_linked_or_case_variant_approval_refused(self):
        os.link(self.approval, os.path.join(self.tmp, "second-name.json"))
        rc, out = self.hs("init")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("hard link", out)
        variant = HS6.replace("acceptance", "ACCEPTANCE")
        with self.assertRaises(hs6.Stop) as c:
            hs6.check_approval_file(variant)
        if os.path.exists(variant):  # a case-insensitive volume: must be caught as inside the repository
            self.assertIn("inside the repository", str(c.exception))
        # a path that walks through a link into the repository and back out
        lnk = os.path.join(self.tmp, "lnk")
        os.symlink(os.path.dirname(HS6), lnk)
        dotted = os.path.join(lnk, "..", "stage6", "hs6.py")
        if os.path.exists(dotted):
            with self.assertRaises(hs6.Stop) as c:
                hs6.check_approval_file(dotted)
            self.assertIn("inside the repository", str(c.exception))

    def test_watch_loop_hook_refused_with_a_real_account(self):
        self.write_approval(account="owner@example.com")
        rc, out = self.hs("watch", env={"HS6_GCLOUD": None, "HS6_NOW": None, "HS6_REGISTRY": None,
                                        "HS6_WATCH_MAX_LOOPS": "1"})
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)

    def test_clock_file_refused_with_a_real_account(self):
        self.write_approval(account="owner@example.com")
        rc, out = self.hs("init", env={"HS6_GCLOUD": None, "HS6_NOW": None, "HS6_REGISTRY": None,
                                       "HS6_CLOCK_FILE": "/x"})
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("tests only", out)

    def test_harness_change_after_approval_refused(self):
        self.write_approval(harness_sha256=hashlib.sha256(b"an older harness").hexdigest())
        rc, out = self.hs("init")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("harness_sha256", out)


class R2Fixes(R2Teardown):
    def test_forking_ssh_is_killed_promptly_by_the_monitor(self):
        self.up("n1")
        clock = os.path.join(self.tmp, "clock")
        with open(clock, "w") as f:
            f.write(str(self.t))
        self.inject("compute ssh", "SLEEP")
        start = time.monotonic()
        p = self._popen(["ssh", "n1", "--", "long-step"],
                        {"HS6_CLOCK_FILE": clock, "MOCK_SLEEP": "40", "MOCK_FORK": "1"})
        time.sleep(3)
        with open(clock, "w") as f:
            f.write(str(self.t + 7 * 3600))
        out, _ = p.communicate(timeout=90)
        self.assertLess(time.monotonic() - start, 25, out)
        self.assertEqual(p.returncode, hs6.EXIT_GUARD, out)
        self.assertTrue(self.gone())

    def test_forking_ssh_step_timeout_returns_promptly(self):
        self.up("n1")
        self.inject("compute ssh", "SLEEP")
        start = time.monotonic()
        rc, out = self.hs("ssh", "n1", "--", "long-step",
                          env={"MOCK_SLEEP": "40", "MOCK_FORK": "1", "HS6_REMOTE_TIMEOUT": "3",
                               "HS6_WATCH_INTERVAL": "1"})
        self.assertLess(time.monotonic() - start, 25, out)
        self.assertEqual(rc, hs6.EXIT_REMOTE, out)
        self.assertIn("ran longer than", out)
        self.assertFalse(self.gone())  # a slow step is not a limit: nothing is torn down

    def test_monitor_failure_during_ssh_kills_the_step_and_deletes_nothing(self):
        self.up("n1")
        self.inject("compute ssh", "SLEEP")
        p = self._popen(["ssh", "n1", "--", "long-step"], {"HS6_NOW": str(self.t), "MOCK_SLEEP": "40"})
        time.sleep(3)
        with open(os.path.join(self.sdir, "ledger.head"), "w") as f:
            f.write("{}")
        out, _ = p.communicate(timeout=90)
        self.assertEqual(p.returncode, hs6.EXIT_GUARD, out)
        self.assertIn("ledger", out)
        self.assertNotIn("ssh_finished", self.mock())
        self.assertFalse(self.gone())
        self.assertTrue(hs6.recorded_stops(self.sdir))

    def test_watch_retries_while_the_lock_is_busy(self):
        self.up("n1")
        lock = os.path.join(self.sdir, "run.lock")
        open(lock, "w").close()
        self.t += 6.1 * 3600
        rc, out = self.hs("watch", env={"HS6_WATCH_MAX_LOOPS": "2", "HS6_WATCH_INTERVAL": "0"})
        self.assertEqual(rc, hs6.EXIT_GUARD, out)
        self.assertIn("teardown-retry", out)
        self.assertFalse(self.gone())
        stops = hs6.recorded_stops(self.sdir)
        self.assertTrue(any("teardown-retry" in x for x in stops))
        self.assertEqual(len(stops), 2)  # one "limit" and one "teardown-retry", not one per check
        os.unlink(lock)
        rc, out = self.hs("watch", env={"HS6_WATCH_INTERVAL": "0"})
        self.assertEqual(rc, hs6.EXIT_GUARD, out)
        self.assertTrue(self.gone())

    def test_auto_teardown_that_cannot_start_is_recorded_and_reported(self):
        self.up("n1")
        self.t += 6.1 * 3600
        self.inject("config get-value account", "CRASH", times=5, skip=1)
        rc, out = self.hs("ssh", "n1", "--", "true")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("teardown did not complete", out)
        self.assertIn("recorded as present or unresolved: net", out)
        self.assertIn("n1", out)
        self.assertTrue(any('"limit"' in x for x in hs6.recorded_stops(self.sdir)))
        self.assertFalse(self.gone())
        self.set_mock(lambda s: s.update(fail=[]))
        rc, out = self.hs("create-node", "n2")  # the limit still applies: this tears down
        self.assertEqual(rc, hs6.EXIT_GUARD, out)
        self.assertTrue(self.gone())

    def test_a_recorded_stop_blocks_new_work(self):
        self.up("n1")
        hs6.record_stop(self.sdir, {"event": "monitor-failed", "reason": "test"})
        for args in (("create-node", "n2"), ("ssh", "n1", "--", "true")):
            rc, out = self.hs(*args)
            self.assertEqual(rc, hs6.EXIT_REFUSED, out)
            self.assertIn("stops.jsonl", out)
        self.assertEqual(self.hs("teardown")[0], 0)

    def test_limit_in_create_node_is_recorded_and_torn_down(self):
        self.up("n1")
        self.t += 6.1 * 3600
        rc, out = self.hs("create-node", "n2")
        self.assertEqual(rc, hs6.EXIT_GUARD, out)
        self.assertTrue(any('"limit"' in x for x in hs6.recorded_stops(self.sdir)))
        self.assertTrue(self.gone())
        self.assertEqual(self.events("n2"), [])


class NatAutoIp(Base):
    """Cloud NAT allocates its external IP only when a node first sends traffic out
    (seen in the live run h6n121): the run's own NAT IP must not stop the run."""
    ROUTER = "https://www.googleapis.com/compute/v1/projects/<GCP_PROJECT>/regions/asia-northeast1/routers/"

    def add_ip(self, name, users, region="https://www.googleapis.com/compute/v1/projects/<GCP_PROJECT>/regions/asia-northeast1"):
        self.set_mock(lambda s: s["res"]["addresses"].update(
            {name: {"name": name, "id": "4242", "users": users, "region": region}}))

    def test_own_nat_ip_is_accepted_checked_and_released(self):
        self.up("n1")
        self.add_ip("nat-auto-ip-1-2-3", [self.ROUTER + "hagistack-s6-%s-router" % RID])
        rc, out = self.hs("create-node", "n2")
        self.assertEqual(rc, 0, out)
        self.assertNotIn("nat-auto-ip-1-2-3", out)  # not reported as a change by someone else
        rc, out = self.hs("residual")
        self.assertEqual(rc, hs6.EXIT_CLEANUP, out)
        self.assertIn("nat-auto-ip-1-2-3", out)
        self.assertEqual(self.hs("teardown")[0], 0)
        self.assertNotIn("nat-auto-ip-1-2-3", self.mock()["res"]["addresses"])
        self.assertEqual(self.hs("residual")[0], 0)
        self.assertIn("sinter-p8-gateway-ip", self.mock()["res"]["addresses"])

    def test_nat_ip_of_another_router_stops(self):
        self.up("n1")
        self.add_ip("nat-auto-ip-9-9-9", [self.ROUTER + "sinter-v180-relv-router"])
        rc, out = self.hs("create-node", "n2")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("unexpected external address", out)

    def test_nat_named_ip_without_our_router_as_only_user_stops(self):
        self.up("n1")
        for users in ([], [self.ROUTER + "hagistack-s6-%s-router" % RID, self.ROUTER + "other"],
                      [self.ROUTER + "hagistack-s6-%s-router-x" % RID]):
            self.set_mock(lambda s: s["res"]["addresses"].pop("nat-auto-ip-7", None))
            self.add_ip("nat-auto-ip-7", users)
            rc, out = self.hs("create-node", "n2")
            self.assertEqual(rc, hs6.EXIT_REFUSED, out)
            self.assertIn("unexpected external address", out)
        self.assertEqual(self.events("n2"), [])

    def test_own_router_ip_with_another_name_stops(self):
        self.up("n1")
        self.add_ip("manual-ip", [self.ROUTER + "hagistack-s6-%s-router" % RID])
        rc, out = self.hs("create-node", "n2")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("unexpected external address", out)

    def test_same_router_name_in_another_project_or_region_stops(self):
        self.up("n1")
        name = "hagistack-s6-%s-router" % RID
        for users, region in (
                (["https://www.googleapis.com/compute/v1/projects/evil/regions/asia-northeast1/routers/" + name], None),
                (["https://www.googleapis.com/compute/v1/projects/<GCP_PROJECT>/regions/us-east1/routers/" + name], None),
                ([self.ROUTER + name], "https://www.googleapis.com/compute/v1/projects/<GCP_PROJECT>/regions/us-east1"),
                (["/routers/" + name], None)):
            self.set_mock(lambda s: s["res"]["addresses"].pop("nat-auto-ip-8", None))
            if region:
                self.add_ip("nat-auto-ip-8", users, region)
            else:
                self.add_ip("nat-auto-ip-8", users)
            rc, out = self.hs("create-node", "n2")
            self.assertEqual(rc, hs6.EXIT_REFUSED, out)
            self.assertIn("unexpected external address", out)


# Stage 6-2: the approval is valid only with the Owner's SSH signature
class SignedApproval(Base):
    def refused(self, *args, want=None, **kw):
        rc, out = self.hs(*args, **kw)
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        if want:
            self.assertIn(want, out)
        self.assertEqual(self.mutations(), [])
        self.assertFalse(os.path.exists(os.path.join(self.sdir, "ledger.jsonl")), out)
        return out

    def test_no_approval_is_dry_run_and_execute_without_approval_is_refused(self):
        rc, out = self.hs("create-network", approval=False)
        self.assertEqual(rc, 0, out)
        self.assertIn("DRY-RUN", out)
        rc, out = self.hs("create-network", approval=False, env={"HS6_EXECUTE": RID})
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertNotIn("calls", self.mock())

    def test_unsigned_approval_refused(self):
        self.write_approval(key=None)
        self.refused("init", want="no Owner signature")
        self.assertNotIn("calls", self.mock())

    def test_ai_written_chat_record_refused(self):
        # the shape of the method-A records an AI agent wrote from a chat message
        self.write_approval(key=None, format=1, nonce=None, approval_basis="Owner said so in chat",
                            owner_message={"text": "承認します"}, written_by="AI agent")
        self.refused("init", want="format must be 2")
        # even with a .sig the AI made with its own key
        self.write_approval(key=OTHER_KEY, approval_basis="Owner said so in chat", written_by="AI agent")
        self.refused("init", want="not a valid Owner signature")
        self.assertNotIn("calls", self.mock())

    def test_signature_by_another_key_refused(self):
        self.write_approval(key=OTHER_KEY)
        self.refused("init", want="not a valid Owner signature")

    def test_signature_in_another_namespace_refused(self):
        self.write_approval(key=None)
        sign(self.approval, OWNER_KEY, namespace="file")
        self.refused("init", want="not a valid Owner signature")

    def test_tampered_after_signing_refused(self):
        for field, value in (("budget_usd", 7.5), ("operations", ["init", "n1", "teardown"]),
                             ("expires_at", hs6.iso(T0 + 23 * 3600))):
            self.write_approval()
            with open(self.approval) as f:
                a = json.load(f)
            a[field] = value
            with open(self.approval, "w") as f:
                json.dump(a, f)
            self.refused("init", want="not a valid Owner signature")
        # one byte of whitespace is enough
        self.write_approval()
        with open(self.approval, "a") as f:
            f.write(" ")
        self.refused("init", want="not a valid Owner signature")

    def test_signature_copied_from_another_approval_refused(self):
        self.write_approval(run_id="t6zzz", owner_statement=hs6.owner_statement("t6zzz"))
        with open(self.approval + ".sig", "rb") as f:
            other_sig = f.read()
        self.write_approval(key=None)
        with open(self.approval + ".sig", "wb") as f:
            f.write(other_sig)
        os.chmod(self.approval + ".sig", 0o600)
        self.refused("init", want="not a valid Owner signature")

    def test_signed_for_another_run_id_refused(self):
        self.write_approval(run_id="t6zzz", owner_statement=hs6.owner_statement("t6zzz"))
        self.refused("init", want="run_id is not %s" % RID)

    def test_expired_signed_approval_refused_for_new_work(self):
        self.write_approval(approved_at=hs6.iso(T0 - 25 * 3600), expires_at=hs6.iso(T0 - 3600))
        self.refused("init", want="not valid now")

    def test_operation_outside_the_signed_scope_refused(self):
        self.write_approval(operations=["init", "network", "n2", "ssh", "upload", "teardown", "residual"])
        self.up()
        rc, out = self.hs("create-node", "n1")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("operation n1 is not approved", out)
        self.assertFalse([c for c in self.mutations() if "hagistack-s6-%s-n1" % RID in " ".join(c)])

    def test_budget_or_hours_over_the_limit_refused_even_if_signed(self):
        for over in (dict(budget_usd=8.01), dict(max_hours=6.5)):
            self.write_approval(**over)
            self.refused("init", want="budget_usd must be")

    def test_approval_starts_one_run_only(self):
        self.write_approval()
        rc, out = self.hs("init")
        self.assertEqual(rc, 0, out)
        hdr = self.ledger()[0]
        with open(self.approval, "rb") as f:
            self.assertEqual(hdr["approval_sha256"], hashlib.sha256(f.read()).hexdigest())
        # a second init with the same approval, even if the run-id registry entry were removed
        reg = os.path.join(self.tmp, "registry", "used-run-ids")
        with open(reg, "w") as f:
            f.write("")
        self.sdir = os.path.join(self.tmp, "run2")
        os.makedirs(self.sdir)
        self.refused("init", want="already started a run")

    def test_no_pinned_key_means_nothing_executes(self):
        empty = os.path.join(self.tmp, "no-signers")
        open(empty, "w").close()
        self.write_approval()
        self.refused("init", env={"HS6_OWNER_SIGNERS": empty}, want="no Owner signing key is pinned")
        self.assertEqual(hs6.OWNER_SIGNING_KEYS, ())   # until the Owner's key is pinned
        self.refused("init", env={"HS6_OWNER_SIGNERS": None}, want="no Owner signing key is pinned")

    def test_signers_hook_refused_with_a_real_account(self):
        self.write_approval(account="owner@example.com")
        self.refused("init", env={"HS6_GCLOUD": None, "HS6_NOW": None, "HS6_REGISTRY": None}, want="tests only")

    def test_symlinked_or_writable_signature_refused(self):
        self.write_approval()
        real = self.approval + ".real-sig"
        os.rename(self.approval + ".sig", real)
        os.symlink(real, self.approval + ".sig")
        self.refused("init", want="symbolic link")
        os.unlink(self.approval + ".sig")
        os.rename(real, self.approval + ".sig")
        os.chmod(self.approval + ".sig", 0o666)
        self.refused("init", want="writable by group or others")

    def test_owner_signed_approval_runs(self):
        # what hs6_approve.py builds, signed with the Owner's key
        import datetime
        import hs6_approve
        doc = hs6_approve.build_approval(RID, ["init", "network", "n2", "ssh", "upload", "teardown", "residual"],
                                         8.0, 6.0, 12.0, ACCOUNT, hs6.harness_sha256(),
                                         datetime.datetime.fromtimestamp(T0 - 60, datetime.timezone.utc), "cd" * 16)
        with open(self.approval, "wb") as f:
            f.write((json.dumps(doc, indent=1, ensure_ascii=False) + "\n").encode())
        os.chmod(self.approval, 0o600)
        sign(self.approval)
        for args in (("init",), ("create-network",), ("create-node", "n2"), ("teardown",), ("residual",)):
            rc, out = self.hs(*args)
            self.assertEqual(rc, 0, (args, out))
        self.assertTrue(any("instances create hagistack-s6-%s-n2" % RID in " ".join(c) for c in self.mutations()))


    def test_cleanup_still_works_after_a_harness_change(self):
        self.write_approval()
        self.up()
        self.write_approval(harness_sha256=hashlib.sha256(b"the harness before a fix").hexdigest(),
                            nonce="ef" * 16)
        rc, out = self.hs("create-node", "n2")
        self.assertEqual(rc, hs6.EXIT_REFUSED, out)
        self.assertIn("harness_sha256", out)
        rc, out = self.hs("teardown")
        self.assertEqual(rc, 0, out)
        self.assertIn("allowed for teardown only", out)
        rc, out = self.hs("residual")
        self.assertEqual(rc, 0, out)


class ApproveTool(unittest.TestCase):
    """hs6_approve.py's own guards (the signing step itself needs the Owner)."""
    def tool(self, *args, env=None):
        e = {"PATH": "/usr/bin:/bin", "HOME": tempfile.gettempdir()}
        e.update(env or {})
        p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "hs6_approve.py")] + list(args),
                           capture_output=True, text=True, env=e, stdin=subprocess.DEVNULL, timeout=60)
        return p.returncode, p.stdout + p.stderr

    def test_refuses_without_isolated_mode(self):
        e = {"PATH": "/usr/bin:/bin", "HOME": tempfile.gettempdir()}
        p = subprocess.run([sys.executable, os.path.join(HERE, "hs6_approve.py"), "--run-id", "t6abc"],
                           capture_output=True, text=True, env=e, stdin=subprocess.DEVNULL, timeout=60)
        self.assertEqual(p.returncode, 2, p.stderr)
        self.assertIn("python3 -I", p.stderr)

    def test_refuses_without_a_terminal(self):
        rc, out = self.tool("--run-id", "t6abc")
        self.assertEqual(rc, 2, out)
        self.assertIn("terminal", out)
        rc, out = self.tool("--setup")
        self.assertEqual(rc, 2, out)

    def test_trusts_only_the_owners_key_and_reads_hs6_from_source(self):
        import hs6_approve
        owner = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOwnerOwnerOwnerOwnerOwnerOwnerOwnerOwner0"
        other = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOtherOtherOtherOtherOtherOtherOtherOther0"
        hs6_approve.pinned_ok(owner, (owner + " comment",))
        for pinned in ((), (other,), (owner, other)):
            with self.assertRaises(hs6_approve.Refused):
                hs6_approve.pinned_ok(owner, pinned)
        self.assertEqual(hs6_approve.hs6.__name__, "hs6_from_source")
        self.assertEqual(hs6_approve.hs6.harness_sha256(), hs6.harness_sha256())

    def test_refuses_in_an_agent_shell_even_with_a_terminal(self):
        import hs6_approve
        saved = (sys.stdin.isatty, sys.stdout.isatty, os.environ.get("CLAUDECODE"))
        try:
            sys.stdin.isatty = sys.stdout.isatty = lambda: True
            os.environ["CLAUDECODE"] = "1"
            with self.assertRaises(hs6_approve.Refused) as c:
                hs6_approve.need_terminal()
            self.assertIn("AI agent", str(c.exception))
        finally:
            sys.stdin.isatty, sys.stdout.isatty = saved[0], saved[1]
            if saved[2] is None:
                os.environ.pop("CLAUDECODE", None)
            else:
                os.environ["CLAUDECODE"] = saved[2]

    def test_missing_program_is_a_refusal_not_a_traceback(self):
        import hs6_approve
        with self.assertRaises(hs6_approve.Refused):
            hs6_approve.run(["/nonexistent/gcloud", "config", "get-value", "account"])

    def test_build_refuses_out_of_range_conditions(self):
        import datetime
        import hs6_approve
        now = datetime.datetime(2026, 11, 20, tzinfo=datetime.timezone.utc)
        ok = dict(rid=RID, ops=["init", "teardown"], budget=8.0, max_hours=6.0, valid_hours=12.0, account=ACCOUNT,
                  harness_sha="0" * 64, now=now, nonce="ab" * 16)
        hs6_approve.build_approval(**ok)
        for bad in (dict(rid="X"), dict(ops=["init"]), dict(ops=["init", "rm", "teardown"]),
                    dict(ops=["init", "init", "teardown"]), dict(budget=9.0), dict(max_hours=7.0),
                    dict(valid_hours=25.0), dict(account="")):
            with self.assertRaises(hs6_approve.Refused):
                hs6_approve.build_approval(**dict(ok, **bad))


if __name__ == "__main__":
    unittest.main(verbosity=2)
