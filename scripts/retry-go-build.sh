#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation

# Run a build command, retrying it only when a failed attempt's output
# carries a transient network marker.
#
# Usage: MODULE_DOWNLOAD_ATTEMPTS=<1-10> bash retry-go-build.sh CMD [ARG...]
#
# Every attempt runs the same command with the same arguments, working
# directory and environment. Output streams to the log as it arrives
# and is captured for marker matching. The script exits with the last
# attempt's own exit status. A failure without a marker (a compile
# error, for example) is not retried; a marker never turns a failure
# into a pass, it only buys further attempts.

set -u

# Fixed, case-sensitive substrings that mark a failure as a transient
# network problem rather than a defect in the code being built
transient_markers=(
    # HTTP/2 stream reset by the module proxy or a middlebox
    "stream error:"
    # HTTP/2 RST_STREAM/GOAWAY error code from the peer
    "INTERNAL_ERROR"
    # TCP connection dropped mid-transfer
    "connection reset by peer"
    # Read or dial deadline exceeded
    "i/o timeout"
    # TLS negotiation with the proxy stalled
    "TLS handshake timeout"
    # Response body truncated before completion
    "unexpected EOF"
    # Proxy or CDN gateway errors
    "502 Bad Gateway"
    "503 Service Unavailable"
    "504 Gateway Timeout"
)

attempts="${MODULE_DOWNLOAD_ATTEMPTS:-3}"
case "${attempts}" in
    [1-9]|10) ;;
    *)
        echo "Error: MODULE_DOWNLOAD_ATTEMPTS must be 1-10 ❌"
        exit 2 ;;
esac

if [ "$#" -eq 0 ]; then
    echo "Error: no build command given ❌"
    exit 2
fi

# Delay in seconds before the given retry (1 = the second attempt)
retry_delay() {
    case "$1" in
        1) echo 5 ;;
        2) echo 15 ;;
        *) echo 30 ;;
    esac
}

if ! log_file="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/go-build.XXXXXX")"
then
    echo "Error: cannot create a temporary log file ❌"
    exit 2
fi
trap 'rm -f -- "${log_file}"' EXIT

attempt=1
while :; do
    "$@" 2>&1 | tee "${log_file}"
    status="${PIPESTATUS[0]}"
    if [ "${status}" -eq 0 ]; then
        exit 0
    fi
    found=""
    for marker in "${transient_markers[@]}"; do
        if grep -F -q -e "${marker}" -- "${log_file}"; then
            found="${marker}"
            break
        fi
    done
    if [ -z "${found}" ] || [ "${attempt}" -ge "${attempts}" ]; then
        exit "${status}"
    fi
    delay="$(retry_delay "${attempt}")"
    echo "::warning::go build attempt ${attempt} of ${attempts} failed" \
        "with transient error '${found}'; retrying in ${delay}s"
    sleep "${delay}"
    attempt=$((attempt + 1))
done
