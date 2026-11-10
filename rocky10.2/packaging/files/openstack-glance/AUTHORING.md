# Authoring record: openstack-glance packaging files

These files were written for Hagistack from a functional specification, the
upstream Glance 32.0.0 source (Apache-2.0), the upstream oslo.rootwrap 7.9.0
source (Apache-2.0) and public man pages. Paths below are relative to the
unpacked upstream tree `glance-32.0.0/` or `oslo_rootwrap-7.9.0/`.

## Statement of sources

No distribution packaging was consulted: no RDO, Fedora, CentOS, Debian or
Ubuntu packaging, no existing OpenStack `.service`, logrotate or sudoers file
from any distribution, and no web search for them. None of the forbidden local
paths (`hagistack-license-decision-2026-11-10/`, `hagistack-u1-*`,
`hagistack-rc*`, `hagistack-ownpkg-2026-11-11/lima`,
`hagistack-ownpkg-2026-11-11/rc4-baseline`, any `*.rpm`, any `*.spec` outside
the upstream tarball, `rocky10.2/spec-adapt/`) was opened. No network, build,
VM or git command was run. The only checks run were a Python syntax parse of
`glance-wsgi-api` and `visudo -c -f openstack-glance.sudoers` (parsed OK).

## openstack-glance-api.service

Facts:
- `glance-api` is the console script `glance.cmd.api:main`
  (`glance.egg-info/entry_points.txt`, line 2).
- `main()` parses config, starts `wsgi.Server` and then blocks in
  `server.wait()`; it never detaches (`glance/cmd/api.py` lines 72-97). The
  only `os.fork()` is for worker children, and the parent stays in the
  foreground waiting on them (`glance/common/wsgi.py` lines 660-700).
- No sd_notify: Glance does not depend on oslo.service (`requirements.txt`
  lists no oslo.service), and a grep of `glance/` (excluding tests) for
  `systemd`, `sd_notify`, `NOTIFY_SOCKET` and `oslo_service` finds nothing.
- Config: `config.parse_args()` calls oslo.config with `project='glance'`
  (`glance/common/config.py` lines 678-682), so the default search would find
  `/etc/glance/glance-api.conf`. The paste file is derived from the last
  `--config-file` by replacing `.conf` with `-paste.ini` and looked up with
  `CONF.find_file` (`glance/common/config.py` lines 709-718).
- Signals: with workers > 0, SIGTERM makes the parent kill its process group
  (`glance/common/wsgi.py` lines 630-636); SIGHUP triggers an in-place reload
  (lines 423-428, 484, 710-736). With `workers = 0` no SIGHUP handler is set
  (lines 475-478), so SIGHUP would kill the process.

Choices:
- `Type=simple`: foreground process, no READY notification. `Type=notify`
  would make systemd time the start out.
- `--config-file /etc/glance/glance-api.conf` passed explicitly so the result
  does not depend on oslo.config's search order (which also looks under the
  user's home directory) and so the paste file resolves to
  `/etc/glance/glance-api-paste.ini`. Nothing under /usr/share is passed.
- `Wants=`/`After=network-online.target`: "start after the network is up"
  (systemd.special(7), systemd.unit(5)).
- `Restart=on-failure`, `RestartSec=5`: restarts after crashes and non-zero
  exits; config errors (exit codes 1-5/99, `glance/cmd/api.py` lines 59-69)
  are throttled by systemd's default start rate limit. A clean stop is not
  restarted (systemd.service(5)).
- No `ExecReload`: SIGHUP is fatal when `workers = 0`, so offering reload
  would be unsafe.
- Default `KillMode=control-group` is fine: workers are in the unit's cgroup.

## openstack-glance-scrubber.service

Facts:
- `glance-scrubber` is `glance.cmd.scrubber:main` (`entry_points.txt` line 11).
- Continuous mode needs the `daemon` option, a CLI option (`-D/--daemon`,
  default False) (`glance/scrubber.py` lines 128-152); otherwise it runs once
  and exits (`glance/cmd/scrubber.py` lines 81-86).
- In daemon mode, `scrubber.Daemon(CONF.wakeup_time)` runs in the foreground
  and sleeps between runs (`glance/scrubber.py` lines 288-315; `wakeup_time`
  defaults to 300, line 105).
- No sd_notify (same grep as above). Logs go to stderr by default
  (`glance/cmd/scrubber.py` line 46), i.e. to the journal unless `log_file`
  is set.
- `RuntimeError` is caught and turned into `sys.exit("ERROR: ...")`, i.e. exit
  status 1 (`glance/cmd/scrubber.py` lines 89-90).

Choices:
- `--daemon` passed explicitly; `--config-file /etc/glance/glance-scrubber.conf`
  passed explicitly for the same reasons as the API.
- `Type=simple`, `Restart=on-failure`, `RestartSec=5`. Observation:
  `Daemon._run` calls itself recursively (`glance/scrubber.py` line 315
  evaluates `self._run(application)` before passing it to
  `add_done_callback`), so after about 1000 runs Python should raise
  `RecursionError` (a `RuntimeError` subclass), which `main()` turns into exit
  status 1. `Restart=on-failure` then restarts it. This is inferred from the
  code, not observed at runtime.
- `[Install] WantedBy=multi-user.target` is there so an operator can enable
  it; the package should not enable it by default (no preset).

## openstack-glance.logrotate

Facts:
- Logging uses oslo.log options `log_file`, `log_dir`, `watch_log_file`
  (default false) (`etc/glance-api.conf` lines 1060-1076; `etc/glance-scrubber.conf`
  lines 635-651). With the default, the file is not reopened when it is moved.
- glance-api's SIGHUP re-runs `logging.setup` (`glance/common/wsgi.py`
  line 733), but only when workers > 0, and it restarts the workers. The
  scrubber has no SIGHUP handling. So a signal is not a safe general way to
  reopen logs.

Choices (logrotate(8)):
- `copytruncate`: works without any signal. The cost is that a few lines
  written between copy and truncate can be lost.
- `weekly`, `rotate 4`, `compress`, `delaycompress`, `missingok`, `notifempty`.
- `su glance glance`: stops logrotate refusing to rotate if
  `/var/log/glance` is owned by or writable by `glance`.

## openstack-glance.sudoers

Facts:
- oslo.rootwrap usage documentation shows the pattern
  `<user> ALL = (root) NOPASSWD: /usr/bin/<x>-rootwrap /etc/<x>/rootwrap.conf *`
  (`oslo_rootwrap-7.9.0/doc/source/user/usage.rst` line 61).
- Glance's cinder store default `rootwrap_config = /etc/glance/rootwrap.conf`
  (`etc/glance-api.conf` line 1614).
- Upstream Glance has no `glance-rootwrap` console script
  (`entry_points.txt`); oslo.rootwrap provides `oslo-rootwrap`
  (`oslo.rootwrap.egg-info/entry_points.txt`). `/usr/bin/glance-rootwrap` has to be
  provided by the package; that is outside these files.

Choices (sudoers(5)):
- Exactly two commands, `NOPASSWD`, runas `(root)` only.
- `Defaults:glance !requiretty` so it works without a tty even when a global
  `requiretty` is set.
- Comments only use `#` followed by a space, so they cannot be read as
  `#include` or `#<uid>`.

## openstack-glance.sysusers

Facts: sysusers.d(5) syntax `g name GID` and `u name UID:GROUP "GECOS" home
shell`. The ID 161 comes from the Fedora/EL `setup` package's uidgid table,
as stated in the specification.

Choices: the group line comes first so the user line can name it. The GECOS
text was written for this file.

## glance-wsgi-api

Facts: `glance/wsgi/api.py` builds module-level `application` via
`wsgi_app.init_app()` on import (lines 15-22). `init_app()` reads config from
`OS_GLANCE_CONFIG_DIR` (default `/etc/glance`) (`glance/common/wsgi_app.py`
lines 55-69, 109-113). Upstream's uwsgi sample loads
`module = glance.wsgi.api:application` (`httpd/glance-api-uwsgi.ini`).

Choices: the script just re-exports `application`, which is the name
mod_wsgi and uwsgi `--wsgi-file` look for. Shebang `#!/usr/bin/python3`,
mode 0755.

## Uncertainties

- `Type=notify` is not used because there is no sd_notify call in upstream.
  If a later Glance switches to oslo.service, revisit this.
- The `/usr/bin/glance-rootwrap` wrapper and `/etc/glance/rootwrap.conf` are not
  part of upstream Glance 32.0.0's installed scripts; the package must ship them
  for the sudoers rule to be useful.
- The scrubber recursion observation has not been checked at runtime.

## glance-rootwrap.conf (written separately)

Not part of the delegated set above. Written by the main Hagistack session
from the option names in upstream oslo.rootwrap 7.9.0 `etc/rootwrap.conf.sample`
(Apache-2.0): `filters_path` set to `/etc/glance/rootwrap.d`, where the package
links the filter files that python3-glance-store and os-brick install;
`exec_dirs`; `use_syslog=False`. That session has read RDO packaging during the
earlier licence review, but did not open RDO's file of this name; the file's
content is the three documented options and comments.
