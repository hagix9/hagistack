"""Check the commands in the documentation against the real tools.

  OSC=/path/to/openstack HAGISTACK=../rocky10.2/hagistack python3 -I scripts/check_commands.py

* every `openstack ...` command in a ```bash block: the subcommand exists and
  every --option it uses appears in that subcommand's --help
  (python-openstackclient 9.0.1 is the version the nodes get);
* every `./hagistack SUBCOMMAND` and its --options exist in the installer's parser.
No cloud is contacted: only `--help` is run.
"""
import os, re, subprocess, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent / "src" / "content" / "docs"
osc = os.environ.get("OSC", "openstack")
hs = pathlib.Path(os.environ.get("HAGISTACK", str(root.parents[3] / "rocky10.2" / "hagistack")))

cmds = []
for md in sorted(root.rglob("*.md*")):
    text = md.read_text(encoding="utf-8")
    for block in re.findall(r"```(?:bash|sh)\n(.*?)```", text, re.S):
        joined = re.sub(r"\\\n\s*", " ", block)
        for line in joined.splitlines():
            line = line.split("  #")[0].strip()
            line = re.sub(r"^\S+=\$\(", "", line)          # VAR=$(openstack ...)
            for m in re.finditer(r"(?:^|[;(|&]\s*)(openstack\s[^|;)]*)", line):
                cmds.append((md.relative_to(root), "osc", m.group(1).strip()))
            m = re.search(r"(?:^|\s)(?:sudo\s+(?:\S+=\S+\s+)*)?\./hagistack\s+(.*)", line)
            if m:
                cmds.append((md.relative_to(root), "hs", m.group(1).strip()))

help_cache = {}
def osc_help(sub):
    if sub not in help_cache:
        p = subprocess.run([osc] + sub.split() + ["--help"], capture_output=True, text=True)
        # openstack answers 0 even for a command group or an unknown word
        # ("Command 'x' matches: ..."); only a real subcommand prints its usage.
        ok = p.returncode == 0 and p.stdout.startswith("usage: openstack " + sub + " ")
        help_cache[sub] = p.stdout if ok else None
    return help_cache[sub]

src = hs.read_text(encoding="utf-8")
labels = set()
for l in re.findall(r"(?m)^\s*((?:--?[A-Za-z0-9-]+\|?)+)\)", src):
    labels.update(x for x in l.split("|") if x.startswith("--"))
subs = set(re.findall(r"(?m)^\s+(all-in-one|controller|compute-add|compute-secrets|discover-hosts|status|rpm-prepare|rpm-bundle)\)", src))

bad = 0; n_osc = n_hs = 0
for f, kind, c in cmds:
    toks = c.split()
    if kind == "osc":
        n_osc += 1
        toks = toks[1:]
        glob = []
        while toks and toks[0].startswith("--os-"):   # global options such as --os-compute-api-version 2.74
            glob += toks[:2]; toks = toks[2:]
        if toks and toks[0] == "help":
            toks = toks[1:]
        words = []
        for t in toks:
            if t.startswith("-") or not re.fullmatch(r"[a-z][a-z-]*", t): break
            words.append(t)
        # the longest prefix that is a real subcommand
        sub = None
        for k in range(len(words), 0, -1):
            if osc_help(" ".join(words[:k])) is not None:
                sub = " ".join(words[:k]); break
        if not sub:
            bad += 1; print(f"UNKNOWN COMMAND  {f}: {c}"); continue
        h = osc_help(sub)
        known = set(re.findall(r"(?<![\w-])(--[a-z0-9][a-z0-9-]*)", h))
        rest = toks[len(sub.split()):]
        for o in re.findall(r"(?<!\S)(--[a-z][a-z0-9-]*)", " ".join(rest)):
            if o not in known:
                bad += 1; print(f"UNKNOWN OPTION   {f}: {o} in `{c}`")
        for o in re.findall(r"(?<!\S)(-[cf])(?=\s)", " ".join(toks)):
            if f"[{o} " not in h and f"{o} " not in h:
                bad += 1; print(f"UNKNOWN OPTION   {f}: {o} in `{c}`")
    else:
        n_hs += 1
        if toks[0] not in subs:
            bad += 1; print(f"UNKNOWN HAGISTACK SUBCOMMAND {f}: {c}")
        for o in re.findall(r"(?<!\S)(--[a-z][a-z0-9-]*)", c):
            if o not in labels:
                bad += 1; print(f"UNKNOWN HAGISTACK OPTION {f}: {o} in `{c}`")
print(f"{n_osc} openstack and {n_hs} hagistack commands checked, {bad} problem(s)")
sys.exit(1 if bad else 0)
