"""Tests for s67-cluster.sh: step order and roles, the one-shot handoff, and the
checks that do not need OpenStack.

    PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest test_s67_cluster

The script and s66-node.sh are copied into a temporary directory with BASE
pointing there and the root check removed; systemd-run, systemctl and hostname
are stand-ins. Steps are replaced by stubs, so nothing is installed.
"""
import os
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(HERE, "s67-cluster.sh")) as _f:
    SRC = _f.read()
with open(os.path.join(HERE, "s66-node.sh")) as _f:
    SRC66 = _f.read()
CTRL = SRC.split('CTRL_STEPS="', 1)[1].split('"', 1)[0].split()
COMP = SRC.split('COMP_STEPS="', 1)[1].split('"', 1)[0].split()


def body(name, src=SRC):
    return src.split("\n%s() {" % name, 1)[1].split("\n}\n", 1)[0]


def py_block(name):
    return SRC.split("%s='" % name, 1)[1].split("\n'\n", 1)[0]


class Flow(unittest.TestCase):
    def node(self, host):
        self.tmp = tempfile.mkdtemp(prefix="s67-", dir=os.environ.get("TMPDIR"))
        base = os.path.join(self.tmp, "hs6")
        os.makedirs(os.path.join(base, "out"))
        os.makedirs(os.path.join(base, "tree", "rocky10.2"))
        d = os.path.join(self.tmp, "scripts")
        os.makedirs(d)
        s66 = SRC66.replace("BASE=/var/tmp/hs6\n", "BASE='%s'\n" % base).replace('[ "$(id -u)" -eq 0 ] || ', ': || ')
        s67 = SRC.replace('[ "$(id -u)" -eq 0 ] || ', ': || ')
        stubs = "".join('s_%s() { [ -e "$BASE/FAIL_%s" ] && fail "stub %s" || pass "stub %s"; }\n'
                        % (s.replace("-", "_"), s, s, s) for s in CTRL + COMP)
        marker = 's67_main "$@" 2>&1 | tee -a "$OUT/$STEP.log"'
        self.assertEqual(s67.count(marker), 1)
        s67 = s67.replace(marker, stubs + marker)
        with open(os.path.join(d, "s66-node.sh"), "w") as f:
            f.write(s66)
        self.script = os.path.join(d, "s67-cluster.sh")
        with open(self.script, "w") as f:
            f.write(s67)
        self.bin = os.path.join(self.tmp, "bin")
        os.makedirs(self.bin)
        for name, text in (("systemd-run", 'while [ "${1#-}" != "$1" ]; do shift; done\nexec "$@"\n'),
                           ("systemctl", "exit 0\n"),
                           ("hostname", "echo %s\n" % host)):
            p = os.path.join(self.bin, name)
            with open(p, "w") as f:
                f.write("#!/bin/bash\n" + text)
            os.chmod(p, 0o755)
        self.out = os.path.join(base, "out")
        self.base = base

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_(self, *args):
        env = dict(os.environ, PATH=self.bin + os.pathsep + "/usr/bin:/bin")
        p = subprocess.run(["/bin/bash", self.script] + list(args), capture_output=True, text=True, timeout=60, env=env)
        return p.returncode, p.stdout + p.stderr

    def mark(self, *names):
        for n in names:
            open(os.path.join(self.out, n), "w").close()


class Roles(Flow):
    def test_a_compute_step_refuses_on_the_controller(self):
        self.node("hagistack-s6-abc-n1")
        rc, out = self.run_("run", "compute")
        self.assertEqual(rc, 2, out)
        self.assertIn("is not a step of this node", out)

    def test_a_controller_step_refuses_on_the_compute_node(self):
        self.node("hagistack-s6-abc-n2")
        rc, out = self.run_("run", "cluster")
        self.assertEqual(rc, 2, out)

    def test_another_host_has_no_role(self):
        self.node("somewhere-else")
        rc, out = self.run_("controller")
        self.assertEqual(rc, 2, out)
        self.assertIn("neither", out)


class Order(Flow):
    def test_the_controller_needs_the_build_of_s66(self):
        self.node("hagistack-s6-abc-n1")
        rc, out = self.run_("run", "controller")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("pack has not passed", out)
        self.assertFalse(os.path.isdir(os.path.join(self.out, "controller.started")))   # a refusal uses nothing up
        self.mark("pack.passed")
        rc, out = self.run_("run", "controller")
        self.assertEqual(rc, 0, out)
        self.assertIn("controller: PASSED", out)

    def test_each_step_runs_once_and_needs_the_one_before(self):
        self.node("hagistack-s6-abc-n1")
        self.mark("pack.passed")
        rc, out = self.run_("run", "cluster")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("step controller has not passed", out)
        self.assertEqual(self.run_("run", "controller")[0], 0)
        rc, out = self.run_("run", "controller")
        self.assertEqual(rc, 3, out)
        self.assertIn("already been started", out)
        for s in ("cluster", "after-reboot", "final"):
            rc, out = self.run_("run", s)
            self.assertEqual(rc, 0, s + out)

    def test_a_failed_step_blocks_the_next_but_not_the_evidence(self):
        self.node("hagistack-s6-abc-n1")
        self.mark("pack.passed", "../FAIL_controller")
        rc, out = self.run_("run", "controller")
        self.assertEqual(rc, 1, out)
        rc, out = self.run_("run", "cluster")
        self.assertNotEqual(rc, 0, out)
        rc, out = self.run_("run", "evidence-c")
        self.assertEqual(rc, 0, out)

    def test_the_compute_node_must_not_have_built_a_set(self):
        self.node("hagistack-s6-abc-n2")
        rc, out = self.run_("run", "compute")
        self.assertIn("preflight has not passed", out)
        self.mark("preflight.passed")
        os.mkdir(os.path.join(self.out, "build.started"))
        rc, out = self.run_("run", "compute")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("installs the controller's", out)

    def test_status_lists_the_steps_of_the_role(self):
        self.node("hagistack-s6-abc-n2")
        rc, out = self.run_("status")
        self.assertEqual(rc, 0, out)
        self.assertIn("role compute", out)
        for s in COMP:
            self.assertIn(s, out)
        self.assertNotIn("after-reboot", out)


class Handoff(unittest.TestCase):
    """The server and client blocks, run on loopback. shred and firewall-cmd are
    stand-ins that log what they were asked."""

    def setUp(self):
        self.d = tempfile.mkdtemp(prefix="s67-handoff-", dir=os.environ.get("TMPDIR"))
        self.bin = os.path.join(self.d, "bin")
        os.makedirs(self.bin)
        for name in ("shred", "firewall-cmd"):
            p = os.path.join(self.bin, name)
            with open(p, "w") as f:
                f.write('#!/bin/bash\necho "%s $*" >> "%s/calls"\n[ "$1" = -u ] && rm -f "$2"\nexit 0\n' % (name, self.d))
            os.chmod(p, 0o755)
        self.env = dict(os.environ, PATH=self.bin + os.pathsep + "/usr/bin:/bin")
        self.src = os.path.join(self.d, "handoff.tar")
        with open(self.src, "wb") as f:
            f.write(os.urandom(300000))
        with open(self.src, "rb") as f:
            self.data = f.read()
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        self.port = s.getsockname()[1]
        s.close()
        self.res = os.path.join(self.d, "result")

    def tearDown(self):
        shutil.rmtree(self.d)

    def server(self, peer):
        p = subprocess.Popen(["python3", "-I", "-c", py_block("HANDOFF_SERVER"), "127.0.0.1", str(self.port), peer,
                              self.src, self.res], env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(1.5)       # no probe: any connection from the peer is the one transfer
        return p

    def client(self, path):
        return subprocess.run(["python3", "-I", "-c", py_block("HANDOFF_CLIENT"), "127.0.0.1", str(self.port), path],
                              capture_output=True, text=True, timeout=60, env=self.env)

    def result(self):
        with open(self.res) as f:
            return f.read()

    def test_one_transfer_to_the_peer_then_the_file_and_the_rule_are_gone(self):
        p = self.server("127.0.0.1")
        got = os.path.join(self.d, "got.tar")
        r = self.client(got)
        rc = p.wait(timeout=30)
        res = self.result()
        self.assertEqual(rc, 0, res)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("the sender answered MATCH", r.stdout)
        with open(got, "rb") as f:
            self.assertEqual(f.read(), self.data)
        self.assertIn("SENT 300000 bytes; the receiver's SHA-256 matches", res)
        self.assertIn("DONE rc=0", res)
        self.assertFalse(os.path.exists(self.src))
        with open(os.path.join(self.d, "calls")) as f:
            calls = f.read()
        self.assertIn("firewall-cmd --remove-rich-rule rule family=ipv4 source address=127.0.0.1/32 port port=%d" % self.port, calls)
        self.assertNotIn(self.data.hex()[:16], res)

    def test_another_address_gets_nothing_and_a_stop_still_cleans_up(self):
        p = self.server("192.0.2.7")
        got = os.path.join(self.d, "got.tar")
        r = subprocess.Popen(["python3", "-I", "-c", py_block("HANDOFF_CLIENT"), "127.0.0.1", str(self.port), got],
                             env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(1.5)
        p.send_signal(signal.SIGTERM)
        rc = p.wait(timeout=30)
        r.kill()
        r.wait()
        self.assertEqual(rc, 3)
        res = self.result()
        self.assertIn("REFUSED a connection from another address", res)
        self.assertNotIn("SENT", res)
        self.assertIn("DONE rc=3", res)
        self.assertFalse(os.path.exists(self.src))
        self.assertFalse(os.path.exists(got) and os.path.getsize(got) > 0)


class Helpers(unittest.TestCase):
    def bash(self, script, *args):
        return subprocess.run(["bash", "-c", script, "_"] + list(args), capture_output=True, text=True,
                              env={"PATH": os.environ["PATH"], "LC_ALL": "C"})

    def test_ini_active_ignores_comments_and_other_sections(self):
        f = "ini_active() {" + body("ini_active") + "\n}\n"
        with tempfile.NamedTemporaryFile("w", suffix=".conf", delete=False) as t:
            t.write("[DEFAULT]\nconnection = x\n[database]\n#connection = mysql://a\n"
                    "# compute-only node\n  connection=mysql://b\n[api_database]\nslave_connection = c\n"
                    "[ database ]\nconnection_debug = 1\n")
        try:
            r = self.bash(f + 'ini_active "$1" database "connection|slave_connection"', t.name)
            self.assertEqual(r.stdout.split(), ["6"])
            r = self.bash(f + 'ini_active "$1" api_database "connection|slave_connection"', t.name)
            self.assertEqual(r.stdout.split(), ["8"])
            r = self.bash(f + 'ini_active "$1" placement "connection"', t.name)
            self.assertEqual(r.stdout, "")
        finally:
            os.remove(t.name)

    def test_secret_names_lists_names_only(self):
        f = "secret_names(){" + SRC.split("\nsecret_names(){", 1)[1].split("\n", 1)[0] + "\n"
        with tempfile.NamedTemporaryFile("w", delete=False) as t:
            t.write("# hagistack\n\nRABBIT_PASS=synthetic-a\nRPM_SET_SHA256=%s\nNOVA_SERVICE_PASS=synthetic-b\n" % ("0" * 64))
        try:
            r = self.bash(f + 'secret_names "$1"', t.name)
            self.assertEqual(r.stdout.strip(), "NOVA_SERVICE_PASS RABBIT_PASS RPM_SET_SHA256")
            self.assertNotIn("synthetic", r.stdout)
        finally:
            os.remove(t.name)

    def test_times_saved_by_one_step_are_read_back_by_the_next(self):
        # s66r5b: '%s=%s' wrote "T_CLUSTER_END=1794759665=", and after-reboot stopped on the arithmetic
        f = "\n".join(l for l in SRC.splitlines() if l.startswith(("save_times(){", "load_times(){"))) + "\n"
        out = tempfile.mkdtemp(prefix="s67t-", dir=os.environ.get("TMPDIR"))
        try:
            script = f + ('OUT="$1"; save_times T_RESTART=11 T_RECOVERED=22; save_times T_CLUSTER_END=33\n'
                          'unset T_RESTART T_RECOVERED T_CLUSTER_END; load_times\n'
                          'echo "$T_RESTART|$T_RECOVERED|$T_CLUSTER_END|$(( 100 - T_CLUSTER_END ))"')
            r = self.bash(script, out)
            self.assertEqual(r.stdout.strip(), "11|22|33|67", r.stderr)
            with open(os.path.join(out, "cluster-times.env")) as t:
                self.assertEqual(t.read(), "T_RESTART=11\nT_RECOVERED=22\nT_CLUSTER_END=33\n")
        finally:
            shutil.rmtree(out)

    def test_the_expected_names_are_hagistacks_compute_keys(self):
        with open(os.path.join(HERE, "..", "..", "rocky10.2", "hagistack")) as f:
            hs = f.read()
        keys = hs.split('COMPUTE_SECRET_KEYS="', 1)[1].split('"', 1)[0].split()
        want = SRC.split('COMPUTE_SECRET_NAMES="', 1)[1].split('"', 1)[0].split()
        self.assertEqual(want, sorted(keys + ["RPM_SET_SHA256"]))


class Text(unittest.TestCase):
    """What the steps do that only a real node can run, checked in the text."""

    def test_bash_syntax(self):
        r = subprocess.run(["bash", "-n", os.path.join(HERE, "s67-cluster.sh")], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_the_controller_ports_are_readme_and_hagistack(self):
        ports = SRC.split('CONTROLLER_PORTS="', 1)[1].split('"', 1)[0].split()
        with open(os.path.join(HERE, "..", "..", "rocky10.2", "hagistack")) as f:
            pre = f.read().split("\nphase_compute_preflight() {", 1)[1].split("\n}\n", 1)[0]
        with open(os.path.join(HERE, "..", "..", "rocky10.2", "README.md")) as f:
            readme = f.read()
        for p in ports:
            self.assertIn('"%s ' % p, pre)
            self.assertIn("- %s (" % p, readme)
        self.assertIn("{%s}/tcp --add-port=6081/udp" % ",".join(ports), readme)

    def test_the_credentials_never_reach_the_output(self):
        c = body("s_controller")
        self.assertIn('> "$HANDOFF/secrets.env"', c)
        self.assertIn('shred -u "$HANDOFF/secrets.env"', c)
        self.assertNotIn('"$OUT/secrets', c)
        n = body("s_compute")
        self.assertIn('install -o root -g root -m 0600 "$HANDOFF/secrets.env" /etc/hagistack/secrets.env && shred -u', n)
        self.assertIn("umask 077", n)
        snap = body("rerun_snapshot")
        self.assertIn('"$BASE/rerun', body("s_rerun"))
        self.assertNotIn("$OUT", snap)
        self.assertIn('rm -f "$BASE/rerun-before" "$BASE/rerun-after"', body("s_rerun"))
        self.assertIn("sha256sum", snap)
        self.assertNotIn("cp ", snap)                          # digests only, never a copy of secrets.env
        # neither the handoff nor the snapshots are under out/, which is all the evidence copies
        self.assertEqual(SRC.count('HANDOFF="$BASE/handoff"'), 1)

    def test_the_handoff_is_limited_to_the_peer_and_an_hour(self):
        c = body("s_controller")
        self.assertIn('firewall-cmd --add-rich-rule "rule family=ipv4 source address=$pip/32 port port=$HANDOFF_PORT protocol=tcp accept"', c)
        self.assertNotIn("--permanent --add-rich-rule", c)
        self.assertIn("-p RuntimeMaxSec=3600", c)
        srv = py_block("HANDOFF_SERVER")
        self.assertIn("if ip != peer:", srv)
        self.assertIn("signal.signal(signal.SIGTERM, stop)", srv)
        self.assertNotIn("print(", srv)                       # nothing to the journal but the result lines

    def test_multi_node_chassis_checks_name_both_nodes(self):
        r = body("registration_checks")
        for s in ("chassis_pair", "enable-chassis-as-gw", "peer_encap_ip", '"OVN Metadata agent"',
                  '"OVN Controller agent"', '"OVN Controller Gateway agent"', "hypervisor_on_peer", "compute_up"):
            self.assertIn(s, r)
        self.assertNotIn("chassis_named", SRC)                # the single-node check is not reused

    def test_restart_reboot_and_rerun_are_covered(self):
        cl = body("s_cluster")
        self.assertLess(cl.index("registration_checks before-restart"), cl.index('systemctl restart "$u"'))
        self.assertLess(cl.index('systemctl restart "$u"'), cl.index("registration_checks after-restart"))
        self.assertIn("fip_ping after-restart s67-g3 s67-g1", cl)
        self.assertIn("head -c 2000000 /dev/zero", cl)
        self.assertIn('traceback_windows "$t_restart" "$t_recovered" cluster', cl)
        self.assertIn('--on-active=20 /usr/bin/systemctl reboot', body("s_reboot"))
        self.assertIn("/proc/sys/kernel/random/boot_id", body("s_reboot"))
        self.assertIn("/proc/sys/kernel/random/boot_id", body("s_rerun"))
        ar = body("s_after_reboot")
        self.assertIn("registration_checks after-reboot", ar)
        self.assertIn("os_ server start", ar)
        self.assertIn("os_ server reboot --hard", ar)
        self.assertLess(ar.index("wait_until 600 peer_gone"), ar.index("registration_checks after-reboot"))
        self.assertIn("/proc/uptime", ar)
        self.assertIn("T_CLUSTER_END", ar)
        self.assertNotIn("power_state", SRC)                   # -f value gives a number, and a stale one
        rr = body("s_rerun")
        self.assertIn("compute_add compute-add-rerun.out", rr)
        self.assertIn("the re-run changed no configuration", rr)
        self.assertIn("has rebooted since the reboot step", rr)
        self.assertIn('tracebacks_between "$t_back" ""', rr)
        self.assertLess(rr.index("compute_local_checks after-rerun"), rr.index("t_back=$(date +%s)"))
        pg = body("peer_gone")
        self.assertIn('[ -n "$f" ] || return 1', pg)
        self.assertIn("cluster_guest after-rerun s67-g4", body("s_final"))

    def test_helper_units_never_take_a_step_unit_name(self):
        helpers = [SRC.split(k + "=", 1)[1].split()[0] for k in ("HANDOFF_UNIT", "REBOOT_UNIT")]
        for h in helpers:
            self.assertNotIn(h, ["hs6-" + st for st in CTRL + COMP], h)
        self.assertIn('--unit="$REBOOT_UNIT"', body("s_reboot"))
        self.assertNotIn("--unit=hs6-", SRC.replace('--unit="hs6-$step"', ""))

    def test_empty_answers_count_only_when_the_call_succeeded(self):
        f = "answers_empty(){" + SRC.split("\nanswers_empty(){", 1)[1].split("\n", 1)[0] + "\n"
        for os_body, rc in (("return 0", 0), ("echo x", 1), ("return 1", 1)):
            r = subprocess.run(["bash", "-c", "os_(){ %s; }\n%s answers_empty a b" % (os_body, f)], capture_output=True)
            self.assertEqual(r.returncode, rc, os_body)
        self.assertIn('[ -n "$eip" -a "$eip" = "$pip" ]', body("registration_checks"))

    def test_the_handoff_needs_a_controller_that_passed(self):
        c = body("s_controller")
        self.assertLess(c.index('[ "$FAILS" -eq 0 ] || { note "the handoff is not offered'), c.index("compute-secrets )"))
        self.assertLess(c.index('if [ "$FAILS" -ne 0 ]; then'), c.index('tar -cf "$HANDOFF/handoff.tar"'))

    def test_the_controller_checks_what_it_must_not_do(self):
        c = body("s_controller")
        for s in ("not rpm -q", "No valid host", "no hypervisor", "no nova-compute service is registered",
                  "global_physnet_mtu", "mtu - 58", "refusing to overwrite", "time_check"):
            self.assertIn(s, c)


if __name__ == "__main__":
    unittest.main()
