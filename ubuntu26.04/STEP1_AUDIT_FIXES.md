# Step 1 audit — fixes and regression verification

- Date: 2026-09-27
- Subject: `ubuntu26.04/hagistack`, version `0.1.0-step1`
- Scope: the five findings from the Step 1 audit. **No Step 2 (Keystone) work.**
- Environment: `ubuntu:26.04` → **Ubuntu 26.04.1 LTS amd64**, nerdctl/containerd inside an
  already-running `lima` VM. **No systemd in the container.** `/src` mounted read-only.
  No GCE, AWS or Sinter operation; no macOS host service or network change.

## Summary

| Suite | PASS | FAIL | UNVERIFIED |
|---|---|---|---|
| `container-audit.sh` (the five findings) | 40 | 0 | 0 |
| `container-verify.sh` (existing regression) | 65 | 0 | 6 |
| `container-dbtest.sh` (database / queue) | 28 | 0 | 3 |

## Before / after, per finding

`container-repro.sh` runs the same probes against both builds. Condensed:

| # | Finding | Before (`ab68428`) | After |
|---|---|---|---|
| 1 | Config file executed code | **`$(touch …)` and `` `touch …` `` both RAN** — marker file created | Refused, exit 1, no marker. Value never echoed back |
| 2 | Precedence incomplete | `--virt-type kvm` was **overwritten by the file** (`virt_type=qemu`); env tier had no effect at all | `VIRT_TYPE=kvm [command line]`, `TENANT_CIDR=10.2.2.0/24 [environment]`, etc. |
| 3 | Two passwords, one DB user | `NOVA_API_DB_PASS` generated but unusable | Single `NOVA_DB_PASS`; obsolete key reported and left in place |
| 4 | False completion | **`STEP 1 COMPLETE`, exit 0**, and `memcached.done` written though nothing started | `STEP 1 INCOMPLETE`, **exit 4**, no marker for skipped phases |
| 5 | `gen_secret` pipefail hazard | Not reproduced as a live failure (see below) | Structurally removed |

### Finding 5 in detail — reported honestly

The bare pipeline was measured directly:

```
set -Eeuo pipefail
tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
   -> exit 141 (SIGPIPE) on 200 of 200 runs
```

But as actually *called* — `s="$(gen_secret 32)"` — it did **not** abort in 200 of 200 runs and
returned a correct 32-character secret. So this was a **real hazard that the call site happened to
mask**, not a live defect. Any refactor that used `gen_secret` outside a command substitution, or
that cared about the status of a following command, would have exposed it.

It is fixed regardless: the consumer-side `head` is gone. The producer is bounded
(`head -c 4096 /dev/urandom` / `openssl rand -base64 256`) and the result is trimmed with a shell
substring, so no pipe is ever broken. Verified over 100 runs × 5 secrets on the fallback path and
on the openssl path: every secret 32 (or 48) characters, charset `[A-Za-z0-9]`, exit 0 throughout.
No secret value appears anywhere in the shell's output — asserted by comparing every value in
`secrets.env` against the full run log.

## What changed in the shell

| Finding | Cause | Fix |
|---|---|---|
| 1 | The file was validated line-shape-only and then `source`d, so any `KEY=VALUE` whose VALUE was a command substitution executed on load | The file is **parsed**: `KEY` must be in `CONFIG_KEYS`, `VALUE` must match `^[A-Za-z0-9._:/@+=-]*$`, one optional quote pair is stripped. Unknown keys, duplicate keys and malformed lines are refused. Values land in `FILE_VAL[]`, never in a shell command. A rejected value is described, never echoed |
| 2 | Only 6 of 9 options were re-applied after the file loaded, and the top-level `VAR=""` initialisers wiped inherited environment variables before anything could read them | Three explicit tiers (`CLI_*`, `ENV_*`, `FILE_*`) collected independently, then `resolve_config()` applies `CLI > env > file > default` for **every** key. The environment is captured with `printenv` *before* the defaults blank the variables. Presence is tracked separately from value, so `--tenant-cidr ""` is an error rather than a silent fall-through. Repeating a flag: last wins |
| 3 | `nova` and `nova_api` are owned by the same DB user, but two passwords were generated; the second `CREATE USER IF NOT EXISTS` is a no-op, so `NOVA_API_DB_PASS` could never work | One `NOVA_DB_PASS` for the `nova` user, used for both databases. `NOVA_API_DB_PASS` moved to `OBSOLETE_SECRET_KEYS`: if an older `secrets.env` still has it, the run says so once and **leaves the file alone** — nothing is rewritten and nothing is rotated |
| 4 | An unreachable service returned 0 from its phase; the run then printed `STEP 1 COMPLETE` and exited 0. `phase_memcached` also wrote its state marker unconditionally | `note_skip()` records the phase and the reason. A run with any skip prints `STEP 1 INCOMPLETE`, names the skipped phases, and **exits 4**; skipped phases write no state marker. `memcached` is only marked done when `systemctl is-active` confirms it. `status` prints `base layer: INCOMPLETE — missing: …` and explains the exit code |
| 5 | `… \| head -c N` makes the producer take SIGPIPE, which is 141 under `pipefail` | Producer bounded, no consumer-side `head`, trimmed with `${out:0:n}` |
| (extra) | `rabbitmq_reachable` called `rabbitmqctl status` unbounded. Observed live: a probe sat for **20+ minutes** on a slow node and the run never returned | All reachability probes go through `_probe()`, which wraps them in `timeout -k 5 ${HAGISTACK_PROBE_TIMEOUT:-20}`. The `-k` is essential: `rabbitmqctl` ignores SIGTERM, so a plain `timeout` still never returns |

The last row was found *by this verification run itself* — the first DB suite attempt hung on
exactly that call and had to be killed.

## Tests: making sure they bite

Three of the new checks are written so that the **old** build fails them, which is the only way to
know the test is exercising the fix:

- **Code execution** is proved by a marker file, not by a message. Five payloads
  (`$(…)`, backticks, `;`, trailing space, `${IFS}`) each create `/tmp/M<n>` if they run.
  Against `ab68428` the marker appears; against the fixed build it does not, and the run exits 1.
- **Precedence** asserts both the value *and* the source string from the `--check` table, for
  every key, at all four tiers — so a value that happens to be right for the wrong reason fails.
- **The destructive-SQL scan** (from the previous round) keeps its positive control against the
  2013 shell, so it cannot silently become vacuous.

Three test-harness bugs were also found and fixed during this round: `BASE` re-passed
`--mgmt-ip` *after* the CLI override (last-flag-wins made the override invisible — the shell was
correct, the test was not), the openssl branch was never actually taken because the harness did
not define `have`, and the secrets sub-test did not extract `OBSOLETE_SECRET_KEYS`, so it ran with
an unbound variable.

## Still not verified

| Item | Why | Goes to |
|---|---|---|
| Service startup under **systemd**, unit ordering, dependency resolution | No systemd in a container | GCE 区分 B — B0a / B0b |
| **RabbitMQ** | Would not come up inside the container; the manual start attempt is recorded, not counted | GCE 区分 B — B0b |
| Every OpenStack service, KVM guest boot | Not implemented in step 1 | GCE 区分 B |
| Provider network, Floating IP, physical LAN | Not implemented in step 1 | GCE 区分 B / C |

Nothing here has run on real Ubuntu 26.04 hardware or on a GCE VM.

## Reproducing

```sh
nerdctl run --rm -v "$PWD/ubuntu26.04:/src:ro" -v /tmp/out:/out ubuntu:26.04 bash -lc '
  apt-get update -qq && apt-get install -y -qq shellcheck iproute2 openssl
  bash /src/tests/container-audit.sh     # the five findings
  bash /src/tests/container-verify.sh'   # the standing regression suite
# container-dbtest.sh additionally installs mariadb-server and starts it by hand (~1.5 GB free).
# container-repro.sh takes a hagistack path and a label, for before/after comparison.
```

## Result tables

### Audit suite — the five findings (40 PASS / 0 FAIL)

| ID | Status | Detail |
|---|---|---|
| `1.1-no-exec` | PASS | refused, rc=1, no marker |
| `1.2-no-exec` | PASS | refused, rc=1, no marker |
| `1.3-no-exec` | PASS | refused, rc=1, no marker |
| `1.4-no-exec` | PASS | refused, rc=1, no marker |
| `1.5-no-exec` | PASS | refused, rc=1, no marker |
| `1.6-no-value-leak` | PASS | value not echoed in the error |
| `1.7-unknown-key` | PASS | unknown key refused |
| `1.8-duplicate-key` | PASS | duplicate key refused |
| `1.9-malformed-line` | PASS | malformed line refused (rc=1) |
| `1.10-valid-file-ok` | PASS | quoted value + comment + trailing blanks accepted |
| `2.1-file-tenant` | PASS | TENANT_CIDR=10.3.3.0/24 [config file] |
| `2.2-file-dns` | PASS | DNS_SERVER=10.3.3.53 [config file] |
| `2.3-file-virt` | PASS | VIRT_TYPE=qemu [config file] |
| `2.4-env-tenant` | PASS | TENANT_CIDR=10.2.2.0/24 [environment] |
| `2.5-env-dns` | PASS | DNS_SERVER=10.2.2.53 [environment] |
| `2.6-env-virt` | PASS | VIRT_TYPE=kvm [environment] |
| `2.7-env-mgmt` | PASS | MGMT_IP=10.2.2.9 [environment] |
| `2.8-cli-tenant` | PASS | TENANT_CIDR=10.1.1.0/24 [command line] |
| `2.9-cli-dns` | PASS | DNS_SERVER=10.1.1.53 [command line] |
| `2.10-cli-virt` | PASS | VIRT_TYPE=qemu [command line] |
| `2.11-cli-mgmt` | PASS | MGMT_IP=10.1.1.9 [command line] |
| `2.12-default-tenant` | PASS | TENANT_CIDR=10.10.10.0/24 [default] |
| `2.13-default-dns` | PASS | DNS_SERVER=172.24.4.1 [default] |
| `2.14-explicit-empty-cli` | PASS | --tenant-cidr '' rejected (rc=1) |
| `2.15-explicit-empty-file` | PASS | blank value in file rejected (rc=1) |
| `2.16-flag-missing-value` | PASS | trailing flag without value rejected (rc=1) |
| `2.17-last-flag-wins` | PASS | MGMT_IP=10.8.8.8 [command line] |
| `5.1-fallback-exit` | PASS | 100 runs x5 secrets, no nonzero exit |
| `5.2-fallback-shape` | PASS | every secret 32 chars, charset [A-Za-z0-9] |
| `5.3-no-pipe-to-head` | PASS | no consumer-side head in gen_secret |
| `5.4-openssl-path` | PASS | openssl branch: 48-char secrets, exit 0 |
| `5.5-no-secret-in-output` | PASS | no generated secret appears in stdout/stderr |
| `4.1-exit-code` | PASS | exit 4 when base layer incomplete |
| `4.2-banner` | PASS | INCOMPLETE banner shown |
| `4.3-no-false-complete` | PASS | does not claim COMPLETE |
| `4.4-lists-skipped` | PASS | names the skipped phases |
| `4.5-no-marker` | PASS | no state marker for a skipped phase |
| `4.6-memcached-marker` | PASS | memcached not marked done |
| `4.7-status-agrees` | PASS | status reports INCOMPLETE |
| `4.8-status-mentions-exit` | PASS | status explains the exit code |

### Database / queue suite (28 PASS / 0 FAIL / 3 UNVERIFIED)

MariaDB started by hand: `mariadbd-safe --user=mysql --skip-networking` (MariaDB 11.8.6-MariaDB-5ubuntu0.1). RabbitMQ was attempted the same way (`rabbitmq-server -detached`) and did not come up; recorded UNVERIFIED, not PASS.

| ID | Status | Detail |
|---|---|---|
| `DB0-unreachable-honest` | PASS | with no server running, shell said NOT VERIFIED and skipped |
| `DB1-pkg-installed` | PASS | mariadb-server installed inside the container |
| `DB2-manual-start` | PASS | started via: mariadbd-safe --skip-networking (manual, no systemd)  (11.8.6-MariaDB-5ubuntu0.1 from Ubuntu) |
| `DB3-reachable-detected` | PASS | shell detected the hand-started server |
| `DB4-databases-created` | PASS | keystone glance placement nova nova_api neutron |
| `DB5-users-created` | PASS | 5 service users created |
| `DB6-data-survives-rerun` | PASS | sentinel row intact after 2nd all-in-one run |
| `DB7-reuse-reported` | PASS | 2nd run reported existing databases left untouched |
| `DB8-db-password-stable` | PASS | existing DB user credential not rotated |
| `DB9-secrets-stable` | PASS | secrets.env unchanged across DB runs |
| `DB10-third-run` | PASS | data still intact after a 3rd run |
| `DB11-bind-loopback` | PASS | single bind-address line, loopback (bind-address = 127.0.0.1) |
| `DB17-nova-single-cred` | PASS | single NOVA_DB_PASS present |
| `DB18-no-new-api-key` | PASS | NOVA_API_DB_PASS no longer generated |
| `DB19-login-nova` | PASS | nova user logs into the 'nova' database |
| `DB20-login-nova-api` | PASS | same credential logs into 'nova_api' |
| `DB21-grants-nova-api` | PASS | nova user has DDL rights on nova_api |
| `DB22-obsolete-reported` | PASS | stale NOVA_API_DB_PASS reported as unused |
| `DB23-obsolete-kept` | PASS | stale key left untouched (not rewritten, not rotated) |
| `DB24-cred-unchanged` | PASS | nova credential still valid after the migration run |
| `DB25-partial-exit` | PASS | exit 4 while any phase is skipped |
| `DB26-done-marker-present` | PASS | database phase DID complete and is marked |
| `DB27-skipped-no-marker` | PASS | skipped rabbitmq carries no marker |
| `DB28-partial-banner` | PASS | INCOMPLETE banner even though the DB succeeded |
| `DB29-status-names-gap` | PASS | status names rabbitmq as the missing phase |
| `DB30-status-shows-done` | PASS | status shows database as done |
| `DB12-rabbitmq-start` | UNVERIFIED | rabbitmq-server would not start in this container |
| `DB13-rabbit-user` | UNVERIFIED | depends on DB12 |
| `DB14-rabbit-rerun` | UNVERIFIED | depends on DB12 |
| `DB15-state-in-container` | PASS | state under /etc/hagistack and /var/lib/hagistack (container FS) |
| `DB16-src-readonly` | PASS | /src is a read-only bind mount; source untouched |
