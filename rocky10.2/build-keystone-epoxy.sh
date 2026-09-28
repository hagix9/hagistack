#!/usr/bin/env bash
# openstack-keystone 27.0.0 (OpenStack 2025.1 Epoxy) on Rocky Linux 10.2,
# from the rdo-packages epoxy-rdo distgit spec and the signed upstream tarball.
# Every input is pinned and fetched over https; nothing comes from RDO's
# centos10-master trunk except build-time dependencies.
set -uo pipefail
# The build logs are written to /tmp as the invoking user on purpose: only the
# dnf/rpmbuild commands need root, not the log files.
say(){ printf '\n######## %s ########\n' "$*"; }
D=https://raw.githubusercontent.com/rdo-packages/keystone-distgit/epoxy-rdo
S=~/rpmbuild/SOURCES
rpmdev-setuptree
SPEC=~/rpmbuild/SPECS/openstack-keystone.spec

say "inputs, pinned"
curl -sSLo "$SPEC" "$D/openstack-keystone.spec"
for f in openstack-keystone.logrotate openstack-keystone-sample-data keystone-dist.conf; do
  curl -sSLo "$S/$f" "$D/$f"
done
curl -sSLo "$S/keystone-27.0.0.tar.gz"     https://tarballs.openstack.org/keystone/keystone-27.0.0.tar.gz
curl -sSLo "$S/keystone-27.0.0.tar.gz.asc" https://tarballs.openstack.org/keystone/keystone-27.0.0.tar.gz.asc
KEY=0x22284f69d9eccdf3df7819791c711af193ff8e54.txt
curl -sSLo "$S/$KEY" "https://releases.openstack.org/_static/$KEY"
for f in "$SPEC" "$S/keystone-27.0.0.tar.gz" "$S/keystone-27.0.0.tar.gz.asc" "$S/$KEY"; do
  printf '  %-46s %s  %s\n' "$(basename "$f")" "$(stat -c %s "$f")" "$(sha256sum "$f" | cut -c1-16)…"
done
echo "--- the file the rpm-master spec trips over, in THIS tarball ---"
# NB: no `| grep -q` here. Under `set -o pipefail` grep -q closes the pipe, tar
# takes SIGPIPE and the pipeline returns 141 — which is how the first run of
# this script wrongly reported the file as absent.
if tar tzf "$S/keystone-27.0.0.tar.gz" > /tmp/tarlist.txt 2>/dev/null; then
  if grep -q 'httpd/wsgi-keystone.conf' /tmp/tarlist.txt; then
    echo "  PRESENT in 27.0.0 -> %prep succeeds"
  else
    echo "  ABSENT in 27.0.0 -> %prep would fail"
  fi
fi

say "build dependencies (two-pass: static, then the dynamic ones)"
# shellcheck disable=SC2024  # the log belongs to the caller, not to root
sudo dnf -y builddep "$SPEC" > /tmp/builddep.log 2>&1
echo "  static builddep exit=$?"
# pyproject-rpm-macros generates further BuildRequires during %generate_buildrequires;
# DLRN does the same `rpmbuild -br --nodeps` round trip. Bounded at 6 rounds.
for round in 1 2 3 4 5 6; do
  rpmbuild -br --nodeps "$SPEC" > /tmp/br.log 2>&1
  NOSRC=$(ls -t ~/rpmbuild/SRPMS/*.buildreqs.nosrc.rpm 2>/dev/null | head -1)
  [ -n "$NOSRC" ] || break
  # shellcheck disable=SC2024  # the log belongs to the caller, not to root
  sudo dnf -y builddep "$NOSRC" > /tmp/bd.log 2>&1
  rpmbuild -bb "$SPEC" > /tmp/rpmbuild.log 2>&1 && break
  grep -aA20 "Failed build dependencies" /tmp/rpmbuild.log | grep -a "is needed by" \
    | sed "s/^/  round $round still missing: /" | head -4
done
# %install runs `setup.py compile_catalog`, which needs Babel registered as a
# setuptools command. It is not pulled in by either builddep pass.
# shellcheck disable=SC2024  # the log belongs to the caller, not to root
sudo dnf -y install python3-babel > /dev/null 2>&1

say "rpmbuild"
rpmbuild -bb "$SPEC" > /tmp/rpmbuild.log 2>&1
rc=$?
echo "rpmbuild exit=$rc"
if [ "$rc" -eq 0 ]; then
  echo "--- signature verification performed by %prep ---"
  grep -aE "gpgverify|Good signature|gpg:" /tmp/rpmbuild.log | head -5
  echo "--- RPMs produced ---"
  find ~/rpmbuild/RPMS -name '*.rpm' -printf '%f\n' | sort | sed 's/^/  /'
  MAIN=$(find ~/rpmbuild/RPMS -name 'openstack-keystone-27*.rpm' | head -1)
  if [ -n "$MAIN" ]; then
    echo "--- arch: $(rpm -qp --qf '%{ARCH}' "$MAIN" 2>/dev/null) ---"
    echo "--- EL layout it installs (compare with Ubuntu: no vhost, no unit) ---"
    rpm -qlp "$MAIN" 2>/dev/null | grep -E 'wsgi|httpd|systemd|/etc/' | head -8
  fi
else
  echo "--- failure ---"
  grep -aE "^error|RPM build error|Bad exit status|No such file|gpg:" /tmp/rpmbuild.log | tail -12
fi
say "disk"
df -m / | awk 'NR==2{print $4" MB free"}'
