"""Control flow of s66-node.sh (step order, one start per step, exit status),
run on a copy whose paths point into a temporary directory and whose step
bodies are stubs. The steps themselves need Rocky Linux and run only on the node.

    python3 -B -m unittest test_s66_node
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
STEPS = ["preflight", "build", "release", "nodocs", "pack", "install", "accept", "evidence"]


class NodeFlow(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="s66node-", dir=os.environ.get("TMPDIR"))
        base = os.path.join(self.tmp, "hs6")
        os.makedirs(os.path.join(base, "out"))
        os.makedirs(os.path.join(base, "tree", "rocky10.2"))
        with open(os.path.join(HERE, "s66-node.sh")) as f:
            src = f.read()
        self.assertEqual(src.count("BASE=/var/tmp/hs6\n"), 1)
        self.assertEqual(src.count('[ "$(id -u)" -eq 0 ] || '), 2)
        src = src.replace("BASE=/var/tmp/hs6\n", "BASE='%s'\n" % base)
        src = src.replace('[ "$(id -u)" -eq 0 ] || ', ': || ')
        # stand-ins: systemd-run runs the command in the foreground, systemctl knows no unit
        self.bin = os.path.join(self.tmp, "bin")
        os.makedirs(self.bin)
        with open(os.path.join(self.bin, "systemd-run"), "w") as f:
            f.write('#!/bin/bash\necho "systemd-run $*" >> "%s/calls"\n'
                    'while [ "${1#-}" != "$1" ]; do shift; done\nexec "$@"\n' % self.tmp)
        with open(os.path.join(self.bin, "systemctl"), "w") as f:
            f.write('#!/bin/bash\n[ -f "%s/busy" ] && [ "$1" = list-units ] && cat "%s/busy"\nexit 0\n'
                    % (self.tmp, self.tmp))
        for n in ("systemd-run", "systemctl"):
            os.chmod(os.path.join(self.bin, n), 0o755)
        # stubs: a step fails when a file FAIL_<step> exists
        stubs = "".join('s_%s(){ [ -e "$BASE/FAIL_%s" ] && fail "stub %s" || pass "stub %s"; }\n' % (s, s, s, s)
                        for s in STEPS)
        marker = 'main "$@" 2>&1 | tee -a "$OUT/$STEP.log"'
        self.assertEqual(src.count(marker), 1)
        src = src.replace(marker, stubs + marker)
        self.script = os.path.join(self.tmp, "node.sh")
        with open(self.script, "w") as f:
            f.write(src)
        self.base = base

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def step(self, *args):
        env = dict(os.environ, PATH=self.bin + os.pathsep + "/usr/bin:/bin")
        p = subprocess.run(["/bin/bash", self.script] + list(args), capture_output=True, text=True,
                           timeout=60, env=env)
        return p.returncode, p.stdout + p.stderr

    def test_steps_run_in_order_once_each(self):
        for s in STEPS:
            rc, out = self.step(s)
            self.assertEqual(rc, 0, out)
            self.assertTrue(os.path.exists(os.path.join(self.base, "out", s + ".passed")))
        rc, out = self.step("build")
        self.assertEqual(rc, 3, out)
        self.assertIn("already been started", out)

    def test_a_step_needs_the_previous_one_passed(self):
        rc, out = self.step("build")
        self.assertEqual(rc, 3, out)
        self.assertIn("preflight has not passed", out)
        open(os.path.join(self.base, "FAIL_preflight"), "w").close()
        rc, out = self.step("preflight")
        self.assertEqual(rc, 1, out)
        self.assertIn("FAIL  stub preflight", out)
        self.assertFalse(os.path.exists(os.path.join(self.base, "out", "preflight.passed")))
        rc, out = self.step("build")
        self.assertEqual(rc, 3, out)

    def test_evidence_runs_after_a_failed_install(self):
        for s in STEPS[:5]:
            self.assertEqual(self.step(s)[0], 0)
        open(os.path.join(self.base, "FAIL_install"), "w").close()
        self.assertEqual(self.step("install")[0], 1)
        rc, out = self.step("accept")
        self.assertEqual(rc, 3, out)
        rc, out = self.step("evidence")
        self.assertEqual(rc, 0, out)

    def test_unknown_steps_are_refused(self):
        for bad in ("", "extract", "build;id", "s_build", "../x"):
            rc, out = self.step(bad)
            self.assertEqual(rc, 2, out)
            rc, out = self.step("run", bad)
            self.assertEqual(rc, 2, out)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "calls")))

    def test_run_starts_a_transient_unit_and_reports_its_result(self):
        rc, out = self.step("run", "preflight")
        self.assertEqual(rc, 0, out)
        self.assertIn("---- preflight: PASSED ----", out)
        self.assertIn("PASS  stub preflight", out)
        with open(os.path.join(self.tmp, "calls")) as f:
            call = f.read()
        self.assertIn("--unit=hs6-preflight --collect --wait", call)
        self.assertTrue(call.rstrip().endswith("node.sh preflight"), call)
        open(os.path.join(self.base, "FAIL_build"), "w").close()
        rc, out = self.step("run", "build")
        self.assertEqual(rc, 1, out)
        self.assertIn("---- build: NOT PASSED ----", out)

    def test_run_refuses_while_a_step_is_running(self):
        with open(os.path.join(self.tmp, "busy"), "w") as f:
            f.write("hs6-build.service loaded active running /bin/bash node.sh build\n")
        rc, out = self.step("run", "preflight")
        self.assertEqual(rc, 3, out)
        self.assertIn("still running: hs6-build.service", out)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "calls")))

    def test_status_reports_every_step(self):
        self.step("run", "preflight")
        rc, out = self.step("status")
        self.assertEqual(rc, 0, out)
        self.assertIn("preflight  passed", out)
        self.assertIn("build      not started", out)
        self.assertIn("---- preflight.result ----", out)

    def test_evidence_is_not_taken_too_early(self):
        self.assertEqual(self.step("run", "preflight")[0], 0)
        rc, out = self.step("run", "evidence")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("evidence runs after accept has started or after a failed step", out)
        # the refusal did not use up the step
        self.assertFalse(os.path.isdir(os.path.join(self.base, "out", "evidence.started")))

    def test_a_second_run_of_a_step_is_refused_before_any_unit(self):
        self.assertEqual(self.step("run", "preflight")[0], 0)
        os.remove(os.path.join(self.tmp, "calls"))
        rc, out = self.step("run", "preflight")
        self.assertEqual(rc, 3, out)
        self.assertIn("REFUSED: step preflight has already been started", out)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "calls")))

    def test_evidence_after_an_early_failure(self):
        open(os.path.join(self.base, "FAIL_build"), "w").close()
        rc, out = self.step("evidence")
        self.assertEqual(rc, 3, out)
        self.assertIn("preflight has not started", out)
        self.assertEqual(self.step("run", "preflight")[0], 0)
        self.assertEqual(self.step("run", "build")[0], 1)
        rc, out = self.step("run", "evidence")
        self.assertEqual(rc, 0, out)

    def test_output_is_logged_per_step(self):
        self.step("preflight")
        with open(os.path.join(self.base, "out", "preflight.log")) as f:
            self.assertIn("PASS  stub preflight", f.read())
        with open(os.path.join(self.base, "out", "preflight.result")) as f:
            self.assertEqual(f.read(), "PASS  stub preflight\n")


class EvidenceDiag(NodeFlow):
    """The real s_evidence on a copy: diagnostic files with a secret are withheld,
    the others are packed. Other steps are stubs; no /etc/hagistack exists here."""
    def setUp(self):
        super().setUp()
        with open(self.script) as f:
            src = f.read()
        self.assertEqual(src.count("DL=/var/tmp/hs6-dl\n"), 1)
        src = src.replace("DL=/var/tmp/hs6-dl\n", "DL='%s/dl'\n" % self.tmp)
        # keep the real evidence step: drop its stub
        stub = 's_evidence(){ [ -e "$BASE/FAIL_evidence" ] && fail "stub evidence" || pass "stub evidence"; }\n'
        self.assertEqual(src.count(stub), 1)
        src = src.replace(stub, "")
        with open(self.script, "w") as f:
            f.write(src)
        for n in ("rpm", "timeout", "journalctl"):
            with open(os.path.join(self.bin, n), "w") as f:
                f.write("#!/bin/bash\nexit 0\n")
            os.chmod(os.path.join(self.bin, n), 0o755)

    def test_diagnostic_files_with_a_secret_are_withheld_and_the_rest_packed(self):
        diag = os.path.join(self.base, "out", "diag")
        os.makedirs(diag)
        with open(os.path.join(diag, "state-after-restart.txt"), "w") as f:
            f.write("agent list\n")
        with open(os.path.join(diag, "journal-after-restart-httpd.txt"), "w") as f:
            f.write("x\n-----BEGIN RSA PRIVATE KEY-----\nMIIE\n")
        self.assertEqual(self.step("preflight")[0], 0)
        open(os.path.join(self.base, "FAIL_build"), "w").close()
        self.assertEqual(self.step("build")[0], 1)
        rc, out = self.step("evidence")
        self.assertEqual(rc, 0, out)
        self.assertIn("1 withheld because a secret value appears in them", out)
        self.assertNotIn("MIIE", out)
        tar = os.path.join(self.tmp, "dl", "evidence-final.tar")
        names = subprocess.run(["tar", "-tf", tar], capture_output=True, text=True, check=True).stdout.split()
        self.assertIn("evidence-final/diag/state-after-restart.txt", names)
        self.assertIn("evidence-final/diag/WITHHELD.txt", names)
        self.assertNotIn("evidence-final/diag/journal-after-restart-httpd.txt", names)
        withheld = subprocess.run(["tar", "-xOf", tar, "evidence-final/diag/WITHHELD.txt"], capture_output=True,
                                  text=True, check=True).stdout
        self.assertEqual(withheld.split(), ["journal-after-restart-httpd.txt"])


class SecretScan(unittest.TestCase):
    """The evidence scan of s66-node.sh, run on its own."""

    def setUp(self):
        with open(os.path.join(HERE, "s66-node.sh")) as f:
            src = f.read()
        self.code = src.split("SECRET_SCAN='", 1)[1].split("\n'\n", 1)[0]
        self.tmp = tempfile.mkdtemp(prefix="s66scan-", dir=os.environ.get("TMPDIR"))
        self.etc = os.path.join(self.tmp, "etc")
        self.ev = os.path.join(self.tmp, "ev")
        os.makedirs(self.etc)
        os.makedirs(self.ev)
        with open(os.path.join(self.etc, "secrets.env"), "w") as f:
            f.write("DB_PASSWORD='Synthetic-DB-Pass-123'\nRPM_SET_SHA256=%s\nMGMT_IP=10.0.0.2\n" % ("a" * 64))
        with open(os.path.join(self.etc, "admin-openrc"), "w") as f:
            f.write("export OS_PASSWORD=Synthetic-Admin-456\n")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def scan(self, **files):
        for n, data in files.items():
            with open(os.path.join(self.ev, n), "w") as f:
                f.write(data)
        p = subprocess.run([sys.executable, "-I", "-B", "-c", self.code, self.ev, self.etc],
                           capture_output=True, text=True)
        return p.returncode, p.stdout

    def test_clean_evidence_passes_and_the_set_identity_is_not_a_secret(self):
        rc, out = self.scan(a="set RPM_SET_SHA256=%s on 10.0.0.2\n" % ("a" * 64))
        self.assertEqual(rc, 0, out)

    def test_passwords_keys_and_tokens_are_found_and_not_printed(self):
        for data in ("x Synthetic-DB-Pass-123 y", "pw=Synthetic-Admin-456",
                     "-----BEGIN OPENSSH PRIVATE KEY-----", "token gAAAA" + "B" * 80):
            with self.subTest(data=data[:20]):
                for n in os.listdir(self.ev):
                    os.remove(os.path.join(self.ev, n))
                rc, out = self.scan(log=data)
                self.assertEqual(rc, 1, out)
                self.assertEqual(out.strip(), "log")
                self.assertNotIn("Synthetic", out)


class NodeScriptText(unittest.TestCase):
    """Static properties of the real script."""

    def setUp(self):
        with open(os.path.join(HERE, "s66-node.sh")) as f:
            self.src = f.read()

    def test_it_parses(self):
        p = subprocess.run(["/bin/bash", "-n", os.path.join(HERE, "s66-node.sh")], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)

    def test_no_compound_test_is_passed_to_check(self):
        # `check "x" [ a ] && [ b ]` would run the second test outside check
        for n, line in enumerate(self.src.splitlines(), 1):
            if line.lstrip().startswith("check ") and "] && [" in line:
                self.fail("line %d: %s" % (n, line))

    def test_the_mark_is_genspec_mark(self):
        import ast
        with open(os.path.join(HERE, "..", "..", "rocky10.2", "packaging", "genspec.py")) as f:
            tree = ast.parse(f.read())
        want = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign)
                    and any(getattr(t, "id", None) == "MARK" for t in n.targets))
        self.assertIn('\nMARK="%s"\n' % want, self.src)
        # Sass files carry the same text after // (genspec MARK_SLASH), and the nodocs check counts both
        self.assertIn('\nMARK_SLASH="//${MARK#\\#}"', self.src)
        nd = self.src.split("s_nodocs() {", 1)[1].split("\n}\n", 1)[0]
        self.assertEqual(nd.count('grep -rlxF -e "$MARK" -e "$MARK_SLASH" usr etc'), 2)
        r = subprocess.run(["bash", "-c", 'MARK="%s"; MARK_SLASH="//${MARK#\\#}"; printf %%s "$MARK_SLASH"' % want],
                           capture_output=True, text=True)
        self.assertEqual(r.stdout, "//" + want[1:])

    def test_accept_waits_for_the_second_guest_and_keeps_diagnostics(self):
        acc = self.src.split("s_accept() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("diag before-restart", acc)
        self.assertIn("diag after-restart", acc)
        self.assertIn("asset_diag", acc)
        g = self.src.split("guest_checks() {", 1)[1].split("\n}\n", 1)[0]
        wait = g.index('wait_until 300 guest_ssh "$ip1" "ping -c 1 -W 2 $ip2"')
        self.assertLess(wait, g.index('"ping -c 5 $ip2"'))
        d = self.src.split("diag() {", 1)[1].split("\n}\n", 1)[0]
        for cmd in ("network agent list", "ovn-sbctl show", "console log show", "journalctl -b"):
            self.assertIn(cmd, d)
        # every OpenStack call in diag is bounded (os_t), and so is every other command that could hang
        self.assertNotIn("os_ ", d)

    def test_the_chassis_name_is_checked_before_and_after_the_restart(self):
        api = self.src.split("api_checks() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("wait_until 120 chassis_named", api)
        f = self.src.split("chassis_named() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("timeout 30 ovn-sbctl --bare --columns=name list Chassis", f)
        self.assertIn('[ "$n" = "$h" ]', f)                     # exactly one chassis, the host
        self.assertIn("/etc/openvswitch/system-id.conf", f)

    def test_the_ping_output_is_kept(self):
        g = self.src.split("guest_checks() {", 1)[1].split("\n}\n", 1)[0]
        keep = g.index('> "$OUT/diag/ping-$l.txt"')
        self.assertIn('2>&1; echo "==== exit $?"; }', g)
        self.assertLess(keep, g.index('got="$(ping_received "$OUT/diag/ping-$l.txt")"'))
        self.assertIn('mkdir -p -m 0700 "$OUT/diag"', g)

    def test_ping_received_reads_iputils_and_busybox(self):
        # the function is run by bash on summaries as ping prints them; the first is
        # s66r3d's diag/ping-before-restart.txt, which the old pattern read as 0
        f = "ping_received() {" + self.src.split("ping_received() {", 1)[1].split("\n}\n", 1)[0] + "\n}\n"
        cases = [
            ("64 bytes from 10.10.10.200: icmp_seq=5 ttl=64 time=0.383 ms\n\n"
             "--- 10.10.10.200 ping statistics ---\n"
             "5 packets transmitted, 5 received, 0% packet loss, time 4080ms\n"
             "rtt min/avg/max/mdev = 0.383/0.481/0.793/0.156 ms\n==== exit 0\n", "5"),
            ("--- 10.10.10.200 ping statistics ---\n"
             "5 packets transmitted, 0 received, +5 errors, 100% packet loss, time 4086ms\n==== exit 1\n", "0"),
            ("--- 10.10.10.200 ping statistics ---\n"
             "5 packets transmitted, 3 packets received, 40% packet loss\n==== exit 1\n", "3"),
            ("--- 10.10.10.200 ping statistics ---\n"
             "15 packets transmitted, 12 received, 20% packet loss\n", "12"),
            ("ssh: connect to host 10.10.10.58 port 22: Connection timed out\n==== exit 255\n", ""),
            ("", ""),
        ]
        with tempfile.TemporaryDirectory() as d:
            for i, (text, want) in enumerate(cases):
                p = os.path.join(d, "ping-%d.txt" % i)
                with open(p, "w") as fh:
                    fh.write(text)
                r = subprocess.run(["bash", "-c", f + 'ping_received "$1"', "_", p],
                                   capture_output=True, text=True, env={"PATH": os.environ["PATH"], "LC_ALL": "C"})
                self.assertEqual((r.returncode, r.stdout.strip()), (0, want), text)

    def test_traceback_count_reads_oslo_log_lines(self):
        # journal lines as journalctl -o cat printed them in s66r4a: oslo.log puts
        # the date, pid, level and module before the header, so '^Traceback'
        # counted 0 there; continuation lines of one traceback count once
        f = "traceback_count() {" + self.src.split("traceback_count() {", 1)[1].split("\n}\n", 1)[0] + "\n}\n"
        oslo = ("2026-11-15 02:00:52.963 300185 ERROR ovsdbapp.backend.ovs_idl.transaction [-] Traceback (most recent call last):\n"
                "2026-11-15 02:00:52.963 300185 ERROR ovsdbapp.backend.ovs_idl.transaction   File \"/usr/lib/x.py\", line 1, in run\n"
                "2026-11-15 02:00:52.963 300185 ERROR ovsdbapp.backend.ovs_idl.transaction RowNotFound: Cannot find Chassis_Private\n")
        nova = ("2026-11-15 02:01:34.280 300453 ERROR nova Traceback (most recent call last):\n"
                "2026-11-15 02:01:34.280 300453 ERROR nova AttributeError: 'ComputeManager' object has no attribute 'rpcserver_alt'\n")
        plain = "Traceback (most recent call last):\n  File \"/usr/bin/x\", line 1\nValueError: x\n"
        cases = [
            (oslo, "1"),
            (oslo + nova + plain, "3"),
            ("2026-11-15 01:56:16.483 300185 WARNING neutron.agent.ovn.metadata.agent [-] Using br-int instead.\n", "0"),
            ("a line that mentions a Traceback in words\n", "0"),
            ("", "0"),
        ]
        for text, want in cases:
            r = subprocess.run(["bash", "-c", "set -uo pipefail\n" + f + "traceback_count"], input=text,
                               capture_output=True, text=True, env={"PATH": os.environ["PATH"], "LC_ALL": "C"})
            self.assertEqual((r.returncode, r.stdout.strip()), (0, want), text)

    def test_the_accept_counts_tracebacks_with_traceback_count(self):
        acc = self.src.split("s_accept() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("| traceback_count)", acc)
        self.assertNotIn("'^Traceback'", self.src)

    def test_the_evidence_never_copies_hagistack_etc(self):
        ev = self.src.split("s_evidence() {", 1)[1].split("\n}\n", 1)[0]
        self.assertNotIn("cp -p /etc/hagistack", ev)
        self.assertNotIn("$OPENRC\" \"$ev", ev)
        self.assertIn("a secret appears in the evidence", ev)
        self.assertIn("python3 -I -c \"$SECRET_SCAN\" \"$ev\"", ev)


if __name__ == "__main__":
    unittest.main()
