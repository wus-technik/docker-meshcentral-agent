#!/bin/sh
# Prove that every tool the `tools` target promises is present AND able to
# start. Two different failures are being guarded against here:
#
#   1. A renamed package. Debian moves these between releases — `dnsutils`
#      became `bind9-dnsutils` in trixie — and apt happily installs a
#      transitional package, so the build stays green while the binary is gone.
#   2. A binary that installs but cannot exec, which is how the rejected
#      copy-only multi-stage variant failed: missing transitive libraries.
#
# Exit status is deliberately ignored for the probe commands. Several of these
# tools exit non-zero for `--version` or for being called without a target, and
# that is not a defect. A binary that is absent, not executable, or unable to
# load its libraries exits 126/127, and that is what fails the run.
set -eu

status=0

check() {
    bin="$1"
    shift

    if ! command -v "$bin" >/dev/null 2>&1; then
        echo "MISSING  ${bin}" >&2
        status=1
        return
    fi

    rc=0
    "$bin" "$@" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then
        echo "BROKEN   ${bin} (exit ${rc} — cannot execute or load libraries)" >&2
        status=1
        return
    fi

    echo "ok       ${bin}"
}

# Inherited from the slim target — the agent's own install path depends on
# these two, so a tools build that lost them is worse than useless.
check curl --version
check wget --version

# Reachability and path
check ping -V
check arping -V
check tracepath -V
check traceroute --version
check mtr --version
check fping -v

# Name resolution
check dig -v
check nslookup -version
check host -V

# Local network state
check ip -V
check ss -V
check ethtool --version

# Ports, transport, capture
check nc -h
check nmap --version
check iperf3 --version
check socat -V
check tcpdump --version

# Service-level probes
check openssl version
check smbclient --version
check ldapsearch -VV
check whois --version

# Reading the results
check ps --version
check lsof -v
check jq --version
check less --version
check vi --version

if [ "$status" -ne 0 ]; then
    echo "" >&2
    echo "tools smoke test FAILED — see the lines above." >&2
    exit 1
fi

echo ""
echo "tools smoke test passed."
