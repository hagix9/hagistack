"""Hagistack's edits to RDO's rpm-master specs, written as rules rather than patches.

Nothing in this file is third-party packaging text. A rule names where to look (a
section, a macro, the tail of a file path) and states what Hagistack wants there.
The only multi-line strings are text Hagistack wrote itself. Each rule says what
it does and why in its own words; it does not quote the spec it edits.

The reviewed input and output SHA-256 of every file live in the manifest
(SPEC rows), not here, so that this file contains no digest that can drift from
the pin it is supposed to match.

Selectors, all of them optional and combined with AND:
  scope   section the line sits under: 'preamble', '%install', '%files api', a
          pattern such as '%files*', or 'any'
  has     substrings the line must contain
  starts  prefix of the stripped line
  ends    tails; the line must end with one of them
expect is how many lines the selector must find. Any other count stops the build.
"""


def replace_lines(f, scope, expect, text=(), absorb=0, **sel):
    """Remove the selected lines and put `text` (Hagistack's own) where the first one was.
    absorb = length of the comment block directly above the first line that goes too."""
    return (f, dict(op='replace_lines', scope=scope, sel=sel, expect=expect, absorb=absorb,
                    text=[t + '\n' for t in text]))


def token_replace(f, scope, expect, old, new, **sel):
    """Within each selected line, swap one token for another; the token must occur once."""
    return (f, dict(op='token_replace', scope=scope, sel=sel, expect=expect, old=old, new=new))


def word_remove(f, scope, expect, word, **sel):
    """Within each selected line, drop one space-separated word; it must occur once."""
    return (f, dict(op='word_remove', scope=scope, sel=sel, expect=expect, word=word))


def insert(f, scope, where, text, **sel):
    """Insert `text` (Hagistack's own) before/after the single selected line."""
    return (f, dict(op='insert', scope=scope, sel=sel, expect=1, where=where,
                    text=[t + '\n' for t in text]))


def global_set(f, name, old, new):
    """Change a one-word %global, which must currently hold `old`."""
    return (f, dict(op='global_set', name=name, old=old, new=new))


def global_prepend(f, name, words):
    """Put words in front of a %global list; none of them may be in it already."""
    return (f, dict(op='global_prepend', name=name, words=list(words)))


NEUTRON_PATCHES = (
    'third-party/neutron/0001-Ensure-MaintenanceWorker-lock-set-before-connect.patch',
    'third-party/neutron/0002-Only-set-the-maintenance-worker-lock-on-the-worker.patch',
)

KEYSTONE = 'openstack-keystone.spec'
NEUTRON = 'openstack-neutron.spec'

RULES = {

    # cliff 4.13.3 still has cliff/tests in the sdist but its wheel no longer
    # installs it, so neither the exclude in the main package nor the tests
    # subpackage's file entry can be satisfied. Both go; the subpackage stays
    # declared and empty, because removing a subpackage changes what an upgrade sees.
    'cliff': dict(version='4.13.3', files=['python-cliff.spec'], ops=[
        replace_lines('python-cliff.spec', '%files*', 2, ends=('/%{modname}/tests',)),
    ]),

    # Documentation off: the doc build needs a Sphinx extension EL10 does not ship as
    # an importable module, and the dashboard is what this shell deploys, not the docs.
    # Also: horizon 25.7.3 compiles its message catalogs in %build but its wheel does
    # not carry them, so the buildroot has empty locale trees and the language-file
    # step fails. The catalogs are copied into the two trees %install has just laid out.
    'horizon': dict(version='25.7.3', files=['python-django-horizon.spec'], ops=[
        global_set('python-django-horizon.spec', 'with_doc', '1', '0'),
        insert('python-django-horizon.spec', '%install', 'before', [
            "# horizon 25.7.3 compiles its message catalogs in the build section, but its",
            "# pyproject wheel does not carry them: 100 .mo files exist in the build tree and",
            "# none reaches the buildroot, so the lang-file step below finds nothing and the",
            "# build stops. Copy them into the two trees the install section has just laid",
            "# out. tar is used rather than a shell loop because a loop here ends up inside",
            "# the generated script and is easy to break.",
            "find horizon openstack_auth -name '*.mo' -print0 2>/dev/null \\",
            "  | tar --null -cf - -T - | tar -xf - -C %{buildroot}%{python3_sitelib} || :",
            "find openstack_dashboard -name '*.mo' -print0 2>/dev/null \\",
            "  | tar --null -cf - -T - | tar -xf - -C %{buildroot}%{_datadir}/openstack-dashboard || :",
            ""], starts='%find_lang'),
    ]),

    # keystone 29 dropped the generated WSGI scripts and wsgi-keystone.conf (release
    # notes remove-wsgi-scripts, add-keystone-wsgi-module) and ships uwsgi-keystone.conf
    # plus an importable keystone.wsgi.api. So: no script paths to rewrite in %prep,
    # install the uwsgi file, and do not package the two scripts.
    # Separately, keystone 29 spells the self-referential tox dependency with a shorter
    # extras list; the stripping must accept either spelling.
    'keystone': dict(version='29.1.0', files=[KEYSTONE], ops=[
        replace_lines(KEYSTONE, '%prep', 2, absorb=1, has=('httpd/wsgi-keystone.conf',), text=[
            "# Upstream removed httpd/wsgi-keystone.conf and the generated",
            "# keystone-wsgi-public and keystone-wsgi-admin scripts after 27.x (release notes",
            "# remove-wsgi-scripts and add-keystone-wsgi-module). 29.1.0 ships",
            "# httpd/uwsgi-keystone.conf and the importable keystone.wsgi.api module, so",
            "# there are no script paths left to adjust."]),
        replace_lines(KEYSTONE, '%prep', 1, has=('tox.ini', '[ldap'), text=[
            "# keystone 29 changed this self-referential tox dep from .[ldap,memcache] to",
            "# .[ldap]. Either form is rejected by packaging.requirements when the tox-based",
            "# buildrequires generator parses it, so match both. The extras are already",
            "# covered by this spec's own BuildRequires.",
            r"sed -i '/^[[:space:]]*\.\[ldap[^]]*\][[:space:]]*$/d' tox.ini"]),
        token_replace(KEYSTONE, '%install', 1, 'wsgi-keystone.conf', 'uwsgi-keystone.conf',
                      has=('httpd/wsgi-keystone.conf',)),
        replace_lines(KEYSTONE, '%files', 2, ends=('/keystone-wsgi-admin', '/keystone-wsgi-public')),
        token_replace(KEYSTONE, '%files', 1, 'wsgi-keystone.conf', 'uwsgi-keystone.conf',
                      has=('/wsgi-keystone.conf',)),
    ]),

    # neutron 28.0.2 has no generated neutron-api / neutron-server script any more.
    # Two upstream OVN maintenance-lock fixes (F-NEW-1) are carried as Patch0001/0002;
    # their files are third-party/neutron/ (Apache-2.0), registered by PATCH rows.
    # The pair is inseparable: the first alone makes RPC workers request the
    # maintenance lock too.
    'neutron': dict(version='28.0.2', files=[NEUTRON], patches=NEUTRON_PATCHES, ops=[
        insert(NEUTRON, 'preamble', 'before', [
            "# Hagistack: upstream fix for the OVN maintenance-worker lock race, which is",
            "# not in stable/2026.1. Rebased onto 28.0.2. The two are carried together:",
            "# 0001 alone would make RPC workers request the maintenance lock as well.",
            "Patch0001:      0001-Ensure-MaintenanceWorker-lock-set-before-connect.patch",
            "Patch0002:      0002-Only-set-the-maintenance-worker-lock-on-the-worker.patch",
            ""], starts='BuildArch:'),
        replace_lines(NEUTRON, '%files', 2, ends=('/neutron-api', '/neutron-server')),
    ]),

    # nova 33.0.2 has no generated API scripts either.
    'nova': dict(version='33.0.2', files=['openstack-nova.spec'], ops=[
        replace_lines('openstack-nova.spec', '%files api', 2,
                      ends=('/nova-api*', '/nova-metadata-wsgi')),
    ]),

    # os-ken 4.1.2 declares no console scripts; neutron uses it as a library.
    'os-ken': dict(version='4.1.2', files=['python-os-ken.spec'], ops=[
        replace_lines('python-os-ken.spec', '%files*', 2, ends=('/%{binname}', '/%{binname}-manager')),
    ]),

    # PEP 625: the metadata directory now carries the normalised distribution name,
    # which the spec already has a macro for.
    'oslo-cache': dict(version='4.1.1', files=['python-oslo-cache.spec'], ops=[
        token_replace('python-oslo-cache.spec', '%files*', 1, '%{pypi_name}', '%{tarsources}',
                      has=('.dist-info',)),
    ]),
    'oslo-privsep': dict(version='3.10.1', files=['python-oslo-privsep.spec'], ops=[
        token_replace('python-oslo-privsep.spec', '%files*', 1, '%{pypi_name}', '%{tarsources}',
                      has=('.dist-info',)),
    ]),

    # tzdata is a test-only Python dependency EL10 does not provide as a dist name
    # (the system tzdata package is what zoneinfo reads).
    'oslo-utils': dict(version='10.0.1', files=['python-oslo-utils.spec'], ops=[
        global_prepend('python-oslo-utils.spec', 'excluded_brs', ['tzdata']),
    ]),

    # placement 15.0.0 has no generated placement-api script. The packaged vhost named
    # it, so it is retargeted at the importable module; only %install knows the
    # site-packages path, hence the placeholder and the substitution.
    'placement': dict(version='15.0.0', files=['openstack-placement.spec', 'placement-api.conf'], ops=[
        insert('openstack-placement.spec', '%install', 'after', [
            "# The vhost referred to /usr/bin/placement-api, which upstream removed in 15.0.0",
            "# (release note remove-wsgi-scripts). It now points at the importable module",
            "# placement/wsgi/api.py, whose path is only known here.",
            'sed -i "s|@SITELIB@|%{python3_sitelib}|g" %{buildroot}%{_sysconfdir}/httpd/conf.d/00-placement-api.conf'],
            has=('%{SOURCE3}', '00-placement-api.conf')),
        replace_lines('openstack-placement.spec', '%files api', 1, ends=('/placement-api',)),
        token_replace('placement-api.conf', 'any', 2, '/usr/bin/placement-api',
                      '@SITELIB@/placement/wsgi/api.py', has=('/usr/bin/placement-api',)),
    ]),

    # tooz 8.1.0: four optional-driver test dependencies EL10 lacks go on the exclusion
    # list; the zake extra no longer exists upstream, so the extras subpackage list
    # drops it and the main package must stop requiring it.
    'tooz': dict(version='8.1.0', files=['python-tooz.spec'], ops=[
        global_prepend('python-tooz.spec', 'excluded_brs',
                       ['kubernetes', 'python-consul2', 'sherlock', 'sysv-ipc']),
        replace_lines('python-tooz.spec', 'any', 1, starts='Requires:', has=('+zake',)),
        word_remove('python-tooz.spec', '%install', 1, 'zake', has=('%pyproject_extras_subpkg',)),
    ]),
}
