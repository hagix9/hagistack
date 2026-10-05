#!/usr/bin/env python3
"""Regression test for the OVN maintenance-worker lock race (F-NEW-1).

Neutron 28.0.2 asks for the maintenance worker's OVSDB lock from the worker's
main thread while the connection thread is already running Idl.run(). If the
connection thread reads the lock reply before python-ovs has recorded the
request id, the reply is dropped: the worker then believes it holds the lock,
and every northbound write fails with NOT_LOCKED for the life of the process.
third-party/neutron/ carries upstream 83f1d830 + 91abb5e7 (Apache-2.0), which
request the lock before the connection starts and only for the real maintenance
worker; the Neutron RPM applies them as Patch0001 and Patch0002.

The race is timing-dependent, so this test forces its window open: it wraps the
python-ovs lock request in a short sleep between sending the request and
recording its id. On the vulnerable code the worker then ends up stuck every
time; on the fixed code it cannot.

The test uses the real Neutron code path (OvsdbNbOvnIdl.from_worker and
DBInconsistenciesPeriodics) against its own private ovsdb-server with the OVN
northbound schema on 127.0.0.1, so it never touches a running deployment. It
writes only to that private database.

  usage: tests-neutron-maintenance-lock.py [--neutron-path DIR]

  --neutron-path  import neutron from DIR instead of the installed package, e.g.
                  an unpacked unpatched 28.0.2 tree for the negative control.

Exit 0: fixed behaviour. Exit 1: a check failed (the vulnerable code must fail).
Needs: python3-neutron (or --neutron-path), python3-ovsdbapp, python-ovs,
ovsdb-server and ovsdb-tool from openvswitch, and the ovn-nb schema from ovn.
"""
import glob
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from unittest import mock

if "--neutron-path" in sys.argv:
    sys.path.insert(0, sys.argv[sys.argv.index("--neutron-path") + 1])

import ovs.db.idl as ovs_idl  # noqa: E402

WINDOW = 0.02   # seconds between sending the lock request and recording its id
_send_lock_request = ovs_idl.Idl._Idl__do_send_lock_request


def _widened(self, method):
    msg_id = _send_lock_request(self, method)
    time.sleep(WINDOW)
    return msg_id


ovs_idl.Idl._Idl__do_send_lock_request = _widened


def private_nb():
    schema = next((p for p in ("/usr/share/ovn/ovn-nb.ovsschema",
                               *glob.glob("/usr/share/ovn*/ovn-nb.ovsschema"))
                   if os.path.exists(p)), None)
    if not schema:
        sys.exit("ovn-nb.ovsschema not found (install ovn)")
    tmp = tempfile.mkdtemp(prefix="nb-locktest-")
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    db = os.path.join(tmp, "nb.db")
    subprocess.run(["ovsdb-tool", "create", db, schema], check=True)
    srv = subprocess.Popen(["ovsdb-server", db, "--remote=ptcp:%d:127.0.0.1" % port,
                            "--unixctl=%s/ctl" % tmp, "--log-file=%s/log" % tmp],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        with socket.socket() as s:
            if s.connect_ex(("127.0.0.1", port)) == 0:
                break
        time.sleep(0.1)
    subprocess.run(["ovsdb-client", "transact", "tcp:127.0.0.1:%d" % port,
                    '["OVN_Northbound",{"op":"insert","table":"NB_Global","row":{}}]'],
                   check=True, stdout=subprocess.DEVNULL)
    return srv, tmp, "tcp:127.0.0.1:%d" % port


srv, tmp, remote = private_nb()
failures = []
try:
    from oslo_config import cfg
    from neutron.conf.plugins.ml2.drivers.ovn import ovn_conf
    ovn_conf.register_opts()
    cfg.CONF([], project="neutron", default_config_files=[], default_config_dirs=[])
    cfg.CONF.set_override("ovn_nb_connection", remote, "ovn")

    import neutron
    from neutron import service as n_service
    from neutron.common.ovn import constants as ovn_const
    from neutron.plugins.ml2.drivers.ovn.mech_driver.ovsdb import (
        impl_idl_ovn, maintenance, worker)
    print("neutron from %s" % os.path.dirname(neutron.__file__))

    def start_maintenance_worker():
        # OVNMechanismDriver.post_fork_initialize does this for the real
        # maintenance worker in the fixed code; the vulnerable code has no
        # such attribute and ignores it.
        worker.MaintenanceWorker.lock_name = getattr(
            ovn_const, "MAINTENANCE_NB_IDL_LOCK_NAME", None)
        api = impl_idl_ovn.OvsdbNbOvnIdl.from_worker(worker.MaintenanceWorker)
        client = mock.MagicMock()
        client._nb_idl = api
        periodics = maintenance.DBInconsistenciesPeriodics(client)
        return api, periodics

    # 1. one maintenance worker, race window forced open
    for k in range(1, 4):
        api, periodics = start_maintenance_worker()
        time.sleep(1.0)
        idl = api.idl
        stuck = periodics.has_lock and not idl.has_lock
        try:
            row = next(iter(api.db_list_rows("NB_Global").execute(check_error=True)))
            api.db_set("NB_Global", row.uuid,
                       ("external_ids", {"locktest": str(k)})).execute(check_error=True)
            write = "ok"
        except Exception as e:  # NOT_LOCKED surfaces as RuntimeError
            write = "failed: %s" % str(e).split(":")[0]
        print("start %d: idl.has_lock=%s is_lock_contended=%s neutron has_lock=%s "
              "stuck=%s NB write %s" % (k, idl.has_lock, idl.is_lock_contended,
                                        periodics.has_lock, stuck, write))
        if stuck:
            failures.append("start %d: worker believes it has the lock, OVSDB says no" % k)
        if write != "ok":
            failures.append("start %d: NB write %s" % (k, write))
        api.ovsdb_connection.stop(timeout=5)

    # 2. an RPC worker must not ask for the maintenance lock
    rpc = impl_idl_ovn.OvsdbNbOvnIdl.from_worker(n_service.RpcWorker)
    time.sleep(0.5)
    print("RpcWorker lock_name=%s has_lock=%s" % (rpc.idl.lock_name, rpc.idl.has_lock))
    if rpc.idl.lock_name is not None or rpc.idl.has_lock:
        failures.append("RPC worker requested the maintenance lock")

    # 3. two maintenance workers: one owner, one waiter, then handover
    a, pa = start_maintenance_worker()
    b, pb = start_maintenance_worker()
    time.sleep(1.0)
    print("handover: A has_lock=%s; B has_lock=%s contended=%s neutron has_lock=%s"
          % (a.idl.has_lock, b.idl.has_lock, b.idl.is_lock_contended, pb.has_lock))
    if not (a.idl.has_lock and not b.idl.has_lock and not pb.has_lock):
        failures.append("handover: expected A owner and B waiting")
    a.ovsdb_connection.stop(timeout=5)
    time.sleep(2.0)
    print("after A stops: B has_lock=%s neutron has_lock=%s" % (b.idl.has_lock, pb.has_lock))
    if not (b.idl.has_lock and pb.has_lock):
        failures.append("handover: B did not take the lock after A stopped")
    b.ovsdb_connection.stop(timeout=5)
    rpc.ovsdb_connection.stop(timeout=5)
finally:
    srv.terminate()
    srv.wait(timeout=10)
    shutil.rmtree(tmp, ignore_errors=True)

for f in failures:
    print("FAIL: " + f)
print("RESULT: %s" % ("PASS" if not failures else "FAIL"))
sys.exit(1 if failures else 0)
