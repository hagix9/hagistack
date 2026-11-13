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
        self.assertEqual(src.count('[ "$(id -u)" -eq 0 ] || '), 1)
        src = src.replace("BASE=/var/tmp/hs6\n", "BASE='%s'\n" % base)
        src = src.replace('[ "$(id -u)" -eq 0 ] || ', ': || ')
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

    def step(self, name):
        p = subprocess.run(["/bin/bash", self.script, name], capture_output=True, text=True, timeout=60)
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
        rc, out = self.step("evidence")
        self.assertEqual(rc, 3, out)
        self.assertIn("install has not started", out)
        open(os.path.join(self.base, "FAIL_install"), "w").close()
        self.assertEqual(self.step("install")[0], 1)
        rc, out = self.step("accept")
        self.assertEqual(rc, 3, out)
        rc, out = self.step("evidence")
        self.assertEqual(rc, 0, out)

    def test_unknown_steps_are_refused(self):
        for bad in ("", "extract", "build;id", "s_build"):
            rc, out = self.step(bad)
            self.assertEqual(rc, 2, out)

    def test_output_is_logged_per_step(self):
        self.step("preflight")
        with open(os.path.join(self.base, "out", "preflight.log")) as f:
            self.assertIn("PASS  stub preflight", f.read())
        with open(os.path.join(self.base, "out", "preflight.result")) as f:
            self.assertEqual(f.read(), "PASS  stub preflight\n")


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

    def test_the_evidence_never_copies_hagistack_etc(self):
        ev = self.src.split("s_evidence() {", 1)[1].split("\n}\n", 1)[0]
        self.assertNotIn("cp -p /etc/hagistack", ev)
        self.assertNotIn("$OPENRC\" \"$ev", ev)
        self.assertIn("the admin password appears in the evidence", ev)


if __name__ == "__main__":
    unittest.main()
