# Rocky-only Neutron workers and maintenance-lock extraction

This change selects Rocky worker enablement from cb3154a and the unchanged Rocky lock-fix files from 40472e8. It does not include Ubuntu product/test changes or shared README claims about Ubuntu workers. Rocky product files are byte-identical to the previously audited40472e8 candidate; the new commit hashes identify an extraction, not a new runtime campaign.

The retained records separate historical worker/network acceptance, PATH-B artifact provenance, the earlier INCONCLUSIVE audit, and the final focused runtime audit (handover3/3 and32/32 starts). Previous acceptance is historical evidence, not validation newly executed for this branch. This repository contains neither frozen RPMs nor raw packet captures; their recorded hashes and preserved evidence paths remain in the reports. RPM rebuilding/reproducibility and new deployment acceptance remain outside this extraction.

Ubuntu F-NEW-1: DEFERRED / OPEN. Ubuntu WP-A STATUS: HOLD. WP-A MERGE: HOLD. The Rocky-only PR does not release these gates. F13b/python333 artifacts, O-A and tag_request remain deferred.

The upstream stable/2026.1 backports are in Gerrit review (read-back2026-10-02 JST, both NEW):
- https://review.opendev.org/c/openstack/neutron/+/1008327
- https://review.opendev.org/c/openstack/neutron/+/1008328

No Gerrit change, Ubuntu SRU, package rebuild, tag, release or master merge is performed by this extraction.
