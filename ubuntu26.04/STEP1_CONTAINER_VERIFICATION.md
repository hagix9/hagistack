# Step 1 — local container verification record

- Date: 2026-09-27
- Subject: `ubuntu26.04/hagistack` version `0.1.0-step1`
- Result: **main suite 62 PASS / 0 FAIL / 6 UNVERIFIED**, **database suite 14 PASS / 0 FAIL / 3 UNVERIFIED**
- Suites: `ubuntu26.04/tests/container-verify.sh`, `ubuntu26.04/tests/container-dbtest.sh`

## Environment

| | |
|---|---|
| Container image | `ubuntu:26.04` → **Ubuntu 26.04.1 LTS**, `amd64` |
| Runtime | `nerdctl` 2.3.5 / containerd, inside an **already-running** `lima` VM (`ubuntu-amd64`, x86_64) |
| systemd in container | **absent** (`/run/systemd/system` missing, PID 1 = `bash`) |
| Source mount | `/src` **read-only** bind mount; the repository was never written to from inside |
| Mac host | **unchanged** — no network setting, no service, no package touched on macOS |

`containerd` was started inside the lima **guest** (`sudo systemctl start containerd`); it had
been `inactive`. That is a guest-VM change, not a macOS host change, and it is
reverted at the end of this record.

## What this does and does not establish

**Established here**: Bash syntax, ShellCheck cleanliness, CLI behaviour, input
validation, configuration-generation idempotence, secret file permissions and
value stability, source hygiene, and re-run safety of the package and database
work — including that a planted row survives three consecutive `all-in-one` runs.

**Not established here**, and forwarded to the GCE acceptance: service startup
under systemd, systemd unit ordering and dependency resolution, every OpenStack
service, KVM guest boot, and any provider-network or physical-LAN behaviour.
None of this has run on real Ubuntu 26.04 hardware or on a GCE VM.

## Defects this verification found and fixed

| # | Defect | Why it mattered | Fix |
|---|---|---|---|
| 1 | `trap … ERR` was **never firing inside functions** — `set -E` (`errtrace`) was missing | Every phase ran unguarded; an internal failure exited with a bare status and no message. Found when a missing `iproute2` killed preflight silently | `set -Eeuo pipefail`, plus tests `F10b`/`F10c` that prove the trap fires from inside a function |
| 2 | `--env-file /dev/null` was rejected: the check used `[ -f ]`, false for a character device | `/dev/null` is the natural way to say "ignore all config files"; it masked every validation test | check `[ -r "$f" ]` instead |
| 3 | A missing `iproute2` aborted preflight at the single-NIC check | Hard dependency on a package that is not a hagistack requirement | guarded with `have ip`; autodetection now fails with a clear message telling you to pass `--mgmt-ip` |
| 4 | Database/queue work was gated on *"did systemd start it"* rather than *"does it answer"* | Made the logic impossible to test without systemd, and conflated two questions | `mariadb_reachable` / `rabbitmq_reachable` probes; the start method is recorded and reported |
| 5 | ShellCheck SC2034 (`ASSUME_YES` unused) and SC1010 (bare `done` inside `$( )`) | — | removed / quoted |

Three **test-harness** bugs were also fixed, and are worth recording because two
of them would have produced false confidence:

- Piping into `grep -q` under `set -o pipefail` returns **141** (SIGPIPE), so two
  checks were failing for reasons unrelated to the shell. Output is now captured first.
- The destructive-SQL scan matched the shell's own honest banner prose
  *"it does not drop databases"*. It now requires a DB-client invocation on the
  same line, and a **positive control** runs the same scan against the 2013 shell
  `ubuntu13.10/hagistack_controller_neutron.sh` and asserts it **is** flagged —
  otherwise the check would be vacuous.
- The excluded-engine scan flagged the header comment that documents *not* using
  OpenStack-Ansible/Kolla/Packstack/DevStack. It now judges code, not comments.

## Main suite

| ID | Status | Detail |
|---|---|---|
| `A1-bash-n` | PASS | exit 0 |
| `A2-shellcheck` | PASS | no warnings (-S warning) |
| `B1-help` | PASS | exit 0 |
| `B2-no-args-help` | PASS | exit 0 |
| `B3-version` | PASS | exit 0 |
| `B4-bad-command` | PASS | exit 2 |
| `B5-bad-option` | PASS | exit 2 |
| `B6-compute-add-NI` | PASS | exit 3 |
| `B7-status` | PASS | exit 0 |
| `B8-help-honest` | PASS | help states it is not a working OpenStack |
| `B9-status-pending` | PASS | pending phases listed |
| `C1-missing-required` | PASS | exit 1 |
| `C2-bad-nic-chars` | PASS | exit 1 |
| `C3-nic-absent` | PASS | exit 1 |
| `C4-bad-cidr` | PASS | exit 1 |
| `C5-cidr-no-prefix` | PASS | exit 1 |
| `C6-gw-outside` | PASS | exit 1 |
| `C7-pool-reversed` | PASS | exit 1 |
| `C8-gw-in-pool` | PASS | exit 1 |
| `C9-bad-ip-octet` | PASS | exit 1 |
| `C10-envfile-not-sourced` | PASS | exit 1 |
| `C11-envfile-no-exec` | PASS | injected command did not run |
| `C12-preflight-ok` | PASS | exit 0 |
| `C13-check-no-writes` | PASS | no /etc/hagistack, no /var/lib/hagistack |
| `C14-wrong-ubuntu-ver` | PASS | exit 1 |
| `C15-wrong-os` | PASS | exit 1 |
| `C16-osrelease-restored` | PASS | os-release restored (ubuntu 26.04) |
| `D1-first-write` | PASS | first write changes, second does not |
| `D2-byte-identical` | PASS | file unchanged on 2nd apply |
| `D3-multi-idempotent` | PASS | 3 keys across 2 sections all stable |
| `D4-no-dup-append` | PASS | no duplicate append |
| `D5-single-occurrence` | PASS | 1 bind-address, 1 [mysqld] |
| `D6-value-updated` | PASS | value replaced in place |
| `E1-secret-mode` | PASS | secrets.env mode 600 |
| `E2-dir-mode` | PASS | /etc/hagistack mode 750 |
| `E3-values-stable` | PASS | sha256 identical across runs |
| `E4-mode-after-rerun` | PASS | still 600 after re-run |
| `E5-key-count` | PASS | 11 keys generated |
| `E6-secret-quality` | PASS | no duplicates, all >=24 chars |
| `E7-reuse-reported` | PASS | 2nd run reports reuse |
| `F1-no-fixed-password` | PASS | no literal credential assignment in code |
| `F2-no-drop-db` | PASS | no drop statement passed to a DB client |
| `F2b-scan-positive-control` | PASS | scan flags the legacy shell as expected |
| `F2c-banner-intact` | PASS | re-run safety banner still states no DB drops |
| `F3-no-destructive-rm` | PASS | no destructive rm of system paths |
| `F4-no-blind-append` | PASS | no tee -a into shared system files |
| `F5-no-mac-disable` | PASS | does not disable AppArmor/SELinux |
| `F6-no-libvirt-open` | PASS | no unauthenticated libvirt TCP |
| `F7-no-wildcard-bind` | PASS | no 0.0.0.0 bind |
| `F8-no-force-bypass` | PASS | no --force safety bypass |
| `F9-strict-mode` | PASS | strict mode: set -Eeuo pipefail |
| `F10-err-trap` | PASS | ERR trap present |
| `F10b-errtrace-enabled` | PASS | set -E present, so ERR fires inside functions |
| `F10c-trap-fires-in-fn` | PASS | ERR trap fires inside a function (exit 9) |
| `F10d-fails-loudly` | PASS | bad --env-file rejected with a clear message |
| `F11-no-excluded-engines` | PASS | OSA/Kolla/Packstack/DevStack not invoked in code |
| `G1-systemd-absent-detected` | PASS | shell detected no systemd and said so |
| `G2-marks-unverified` | PASS | reports NOT VERIFIED instead of claiming success |
| `G3-stage-banner` | PASS | prints the 'not a working OpenStack' banner |
| `G4-mariadb-start` | UNVERIFIED | not started here (no systemd); manual-start case covered in db-results.tsv; systemd case = GCE B0b |
| `G5-rabbitmq-start` | UNVERIFIED | not started here; would not start manually either (see db-results.tsv); GCE B0b |
| `G6-unit-ordering` | UNVERIFIED | systemd unit ordering; GCE acceptance item B0a |
| `G7-openstack-services` | UNVERIFIED | no OpenStack service implemented in step 1 |
| `G8-kvm-guest-boot` | UNVERIFIED | no /dev/kvm and no nova; GCE acceptance item B4 |
| `G9-physical-lan` | UNVERIFIED | no provider network in step 1; class C item |
| `H1-secrets-survive` | PASS | secrets unchanged after full re-run |
| `H2-phase-skip` | PASS | completed phase skipped on re-run |
| `H3-state-marker` | PASS | state marker written |

## Database / queue suite

MariaDB was started **by hand**, because this container has no systemd:

```
mariadbd-safe --user=mysql --skip-networking     (manual, no systemd)
  -> MariaDB 11.8.6-MariaDB-5ubuntu0.1 from Ubuntu
```

RabbitMQ was attempted the same way (`rabbitmq-server -detached`) and **would not
start** in this container. It is recorded as UNVERIFIED, not PASS.

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
| `DB12-rabbitmq-start` | UNVERIFIED | rabbitmq-server would not start in this container |
| `DB13-rabbit-user` | UNVERIFIED | depends on DB12 |
| `DB14-rabbit-rerun` | UNVERIFIED | depends on DB12 |
| `DB15-state-in-container` | PASS | state under /etc/hagistack and /var/lib/hagistack (container FS) |
| `DB16-src-readonly` | PASS | /src is a read-only bind mount; source untouched |

### Re-run behaviour, measured

```
run 1:  databases created        keystone glance placement nova nova_api neutron
        service users created    5
        secrets.env              generated, mode 600
        sentinel row planted     keystone.hagistack_sentinel = 'must survive re-run'

run 2:  "database 'keystone' already exists — left untouched"   (and the other five)
        sentinel row             STILL PRESENT
        keystone DB credential   unchanged (hash compared before/after)
        secrets.env              sha256 identical
        99-hagistack.cnf         1 bind-address line, still 127.0.0.1 (no duplicate append)

run 3:  sentinel row             STILL PRESENT
```

## Items forwarded to the GCE acceptance

| Item | Goes to |
|---|---|
| MariaDB / RabbitMQ under systemd | `HAGISTACK_VERIFICATION_SCOPE_2026-09-26.md` §5 区分 B — B0b |
| systemd unit ordering and dependency resolution | §5 区分 B — B0a |
| Every OpenStack service (Keystone … Horizon) | §5 区分 B — B0, B1–B11 |
| Nova KVM guest boot | §5 区分 B — B4 |
| Provider network, Floating IP on the internal virtual LAN | §5 区分 B — B1–B9 |
| Physical LAN, physical NIC in `br-ex`, single-NIC IP migration, VLAN | §5 区分 C — C1–C6 |

## Reproducing

```sh
# in a container runtime of your choice, with the repo checked out
nerdctl run --rm -v "$PWD/ubuntu26.04:/src:ro" -v /tmp/out:/out ubuntu:26.04 \
  bash -lc 'apt-get update -qq && apt-get install -y -qq shellcheck iproute2 && bash /src/tests/container-verify.sh'
```

`container-dbtest.sh` additionally installs `mariadb-server` inside the container
and starts it by hand; it needs roughly 1.5 GB of free space.

## Cleanup performed

The `ubuntu:26.04` image and the verification workspace were removed from the
lima guest, and `containerd` was returned to `inactive` — the state it was in
before this work. No GCE resource was created, started or modified; no AWS API
was called; the Sinter repositories were not written to.
