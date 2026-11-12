#!/usr/bin/env python3
"""Local tests for hs6.py against mock_gcloud.py. No Google API, no credentials.

    python3 test_hs6.py        (set TMPDIR to put the small scratch files elsewhere)

A sentinel `gcloud` first on PATH fails and leaves a marker if anything ever
calls the real gcloud; every test checks the marker is absent.
"""
import calendar
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
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
        self.mockbin = os.path.join(self.tmp, "gcloud-mock")
        with open(self.mockbin, "w") as f:
            f.write("#!/bin/sh\nexec '%s' -I '%s' \"$@\"\n" % (sys.executable, MOCK))
        os.chmod(self.mockbin, 0o755)
        self.t = T0
        self.approval = os.path.join(self.tmp, "approval.json")
        self.write_approval()
        self.env = {"PATH": bindir + os.pathsep + "/usr/bin:/bin", "HOME": self.tmp,
                    "CLOUDSDK_CONFIG": os.path.join(self.tmp, "gcloudcfg"), "MOCK_STATE": self.state,
                    "HS6_GCLOUD": self.mockbin, "HS6_TIMEOUT": "3",
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

    def write_approval(self, **over):
        a = {"format": 1, "run_id": RID, "project": hs6.PROJECT, "zone": hs6.ZONE, "account": ACCOUNT,
             "owner_statement": hs6.owner_statement(RID), "harness_sha256": hs6.harness_sha256(),
             "operations": list(hs6.OPERATIONS), "budget_usd": 8, "max_hours": 6,
             "approved_at": hs6.iso(T0 - 60), "expires_at": hs6.iso(T0 + 20 * 3600)}
        a.update(over)
        with open(self.approval, "w") as f:
            json.dump(a, f)

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
                 dict(format=2)]
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

    def test_node_overrun(self):
        with self.assertRaises(hs6.Stop) as c:
            hs6.guard(self.recs({"n4": 3.8}), self.t)
        self.assertIn("50%", str(c.exception))

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
        rc, out = self.hs("create-node", "n3")
        self.assertEqual(rc, hs6.EXIT_GUARD, out)
        rc, out = self.hs("ssh", "n1", "--", "true")
        self.assertEqual(rc, hs6.EXIT_GUARD, out)
        rc, out = self.hs("status", approval=False)
        self.assertEqual(rc, hs6.EXIT_GUARD, out)
        rc, out = self.hs("teardown")  # cleanup is always allowed
        self.assertEqual(rc, 0, out)

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
