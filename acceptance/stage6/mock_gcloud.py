#!/usr/bin/env python3
"""A stand-in for gcloud, for test_hs6.py only. It never contacts Google and
reads no credentials. State is a JSON file named by MOCK_STATE.

State keys:
  account, active          the configured and the active accounts
  res[kind][name]          resources; kind is instances, disks, networks, subnets,
                           firewalls, routers, nats, addresses
  quotas                   {"region": [...], "project": [...]} as GCE returns them
  image                    describe-from-family result
  fail                     [{"match": "<substring of the joined args>", "mode": M, "times": N}]
                           optional "skip": let that many matching calls through first
                           M: PERMISSION, QUOTA, TIMEOUT, ERROR, CRASH, CREATE_THEN_ERROR,
                              CREATE_DEFERRED (create errors, the resource appears on the next
                              call after the following one), DELETE_NOOP, KEEP_DISK,
                              FAKE_EXISTS (describe returns a resource), METADATA_CHANGE (ssh
                              writes a key into the project metadata), SLEEP (ssh runs for
                              MOCK_SLEEP seconds, then records ssh_finished)
  external_ip              instances get an access config (an external IP)
  calls                    every call, appended
"""
import datetime
import json
import os
import sys
import time

STATE = os.environ["MOCK_STATE"]


def now():
    t = float(os.environ.get("HS6_NOW") or time.time())
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000-00:00")


def load():
    with open(STATE) as f:
        return json.load(f)


def save(s):
    with open(STATE, "w") as f:
        json.dump(s, f, indent=1)


def die(msg, code=1):
    sys.stderr.write("ERROR: (gcloud) " + msg + "\n")
    sys.exit(code)


def notfound(kind, name):
    die("The resource 'projects/p/%s/%s' was not found" % (kind, name))


def flag(args, key):
    for a in args:
        if a.startswith("--" + key + "="):
            return a.split("=", 1)[1]
    return None


def main():
    args = sys.argv[1:]
    s = load()
    s.setdefault("calls", []).append(args)
    d = s.get("deferred")
    if d:
        d["after"] -= 1
        if d["after"] < 0:
            s["res"][d["kind"]][d["name"]] = d["obj"]
            if d.get("disk"):
                s["res"]["disks"][d["name"]] = d["disk"]
            s.pop("deferred")
    joined = " ".join(args)
    mode = None
    for f in s.get("fail", []):
        if f["match"] in joined and f.get("times", 1) != 0:
            if f.get("skip", 0) > 0:
                f["skip"] -= 1
                continue
            f["times"] = f.get("times", 1) - 1
            mode = f["mode"]
            break
    save(s)
    if mode == "PERMISSION":
        die("PERMISSION_DENIED: Required 'compute.instances.create' permission for 'projects/p'")
    if mode == "QUOTA":
        die("Quota 'N2_CPUS' exceeded. Limit: 0.0 in region asia-northeast1. QUOTA_EXCEEDED")
    if mode == "TIMEOUT":
        time.sleep(30)
    if mode == "ERROR":
        die("Internal error (mock)")
    if mode == "CRASH":
        die("Traceback (most recent call last): FileNotFoundError: not found: hagistack-s6- (mock crash)")

    pos = [a for a in args if not a.startswith("-")]
    fmt_json = "--format=json" in args
    out = None

    if pos[:2] == ["config", "get-value"]:
        out = s.get("account", "") if pos[2] == "account" else s.get("config", {}).get(pos[2], "")
    elif pos[:2] == ["auth", "list"]:
        out = "\n".join(s.get("active", []))
    elif pos[:1] == ["compute"]:
        kind_map = {"instances": "instances", "disks": "disks", "networks": "networks",
                    "firewall-rules": "firewalls", "routers": "routers", "addresses": "addresses"}
        rest = pos[1:]
        if rest[:2] == ["networks", "subnets"]:
            kind, rest = "subnets", rest[2:]
        elif rest[:2] == ["routers", "nats"]:
            kind, rest = "nats", rest[2:]
        elif rest[0] in ("regions",):
            out = {"quotas": s["quotas"]["region"], "status": "UP"}
            rest = None
        elif rest[0] == "project-info":
            out = {"quotas": s["quotas"]["project"],
                   "commonInstanceMetadata": s.get("project_metadata", {"fingerprint": "fp0", "items": []})}
            rest = None
        elif rest[0] == "images":
            out = s["image"]
            rest = None
        elif rest[0] in ("ssh", "scp"):
            cmd = flag(args, "command") or ""
            if mode == "METADATA_CHANGE":
                md = s.setdefault("project_metadata", {"fingerprint": "fp0", "items": []})
                md["fingerprint"] = "fp1"
                md["items"].append({"key": "ssh-keys", "value": "tester:ssh-ed25519 AAAA"})
            if mode == "SLEEP":
                save(s)
                if os.environ.get("MOCK_FORK"):
                    # a child that keeps the output pipes open, as ssh under gcloud would
                    import subprocess
                    subprocess.Popen(["sleep", os.environ.get("MOCK_SLEEP", "15")])
                time.sleep(float(os.environ.get("MOCK_SLEEP", "15")))
                s2 = load()
                s2["ssh_finished"] = True
                save(s2)
                print("slept")
                return 0
            if os.environ.get("MOCK_LOCKFILE"):
                s["lock_seen_during_ssh"] = os.path.exists(os.environ["MOCK_LOCKFILE"])
            if mode == "SSH_FAIL":
                save(s)
                print("line 1 of the failing step\n" + "x" * 1000)
                sys.stderr.write("step failed\n")
                sys.exit(3)
            if cmd.startswith("sha256sum "):
                out = s.get("remote_sha", {}).get(cmd.split(" ", 1)[1], "0" * 64) + "  " + cmd.split(" ", 1)[1]
            else:
                out = "ran: " + cmd
            rest = None
        else:
            kind, rest = kind_map[rest[0]], rest[1:]
        if rest is not None:
            verb = rest[0]
            res = s.setdefault("res", {}).setdefault(kind, {})
            if verb == "list":
                out = list(res.values())
            elif verb == "describe":
                name = rest[1]
                if mode == "FAKE_EXISTS":
                    res = dict(res, **{name: {"name": name, "id": "31337", "creationTimestamp": now()}})
                if name not in res:
                    notfound(kind, name)
                out = res[name]
            elif verb == "create":
                name = rest[1]
                if name in res:
                    die("The resource '%s' already exists" % name)
                s["seq"] = s.get("seq", 1000) + 1
                r = {"name": name, "id": str(s["seq"]), "creationTimestamp": now(),
                     "selfLink": "https://mock/%s/%s" % (kind, name)}
                if kind == "instances":
                    labels = dict(kv.split("=", 1) for kv in (flag(args, "labels") or "").split(",") if kv)
                    r.update({"labels": labels, "status": "RUNNING",
                              "machineType": "zones/z/machineTypes/" + flag(args, "machine-type"),
                              "networkInterfaces": [{"accessConfigs": [{"natIP": "x"}] if s.get("external_ip") else []}],
                              "disks": [{"source": "https://mock/disks/" + name}]})
                    s["seq"] += 1
                    s["res"].setdefault("disks", {})[name] = {
                        "name": name, "id": str(s["seq"]), "creationTimestamp": now(),
                        "type": "zones/z/diskTypes/" + flag(args, "boot-disk-type"),
                        "sizeGb": flag(args, "boot-disk-size").rstrip("GB")}
                if kind == "nats":
                    r = {"name": name}
                if mode == "CREATE_DEFERRED":
                    s["deferred"] = {"kind": kind, "name": name, "obj": r, "after": 1}
                    if kind == "instances":
                        s["deferred"]["disk"] = s["res"]["disks"].pop(name)
                    save(s)
                    die("Operation still running (mock: the resource will appear later)")
                res[name] = r
                out = [r]
                if mode == "CREATE_THEN_ERROR":
                    save(s)
                    die("Operation timed out on the server side (mock: the resource was created)")
            elif verb == "delete":
                name = rest[1]
                if name not in res:
                    notfound(kind, name)
                if mode != "DELETE_NOOP":
                    del res[name]
                    if kind == "nats":
                        # Cloud NAT releases the IPs it allocated automatically
                        router = "/routers/" + (flag(args, "router") or "")
                        addrs = s["res"].setdefault("addresses", {})
                        for a in [a for a, v in addrs.items() if a.startswith("nat-auto-ip-")
                                  and any(str(u).endswith(router) for u in v.get("users", []))]:
                            addrs.pop(a)
                    if kind == "instances" and mode != "KEEP_DISK":
                        s["res"].get("disks", {}).pop(name, None)
                out = []
            else:
                die("mock: unsupported verb " + verb)
    else:
        die("mock: unsupported command " + joined)

    save(s)
    if out is None:
        return 0
    if fmt_json:
        print(json.dumps(out))
    else:
        print(out if isinstance(out, str) else json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
