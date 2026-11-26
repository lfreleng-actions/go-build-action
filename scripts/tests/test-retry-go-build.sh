#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation

# Network-free tests for scripts/retry-go-build.sh.
#
# Usage: bash scripts/tests/test-retry-go-build.sh
#
# A stand-in 'go' prints a chosen message and exits non-zero for its
# first N calls, then succeeds; a stand-in 'sleep' records each delay
# and returns at once. Both are written at run time into a temporary
# directory placed first on PATH.

set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
retry_script="${script_dir}/../retry-go-build.sh"

# Register cleanup only once the directory exists and is canonical, so
# a failed mktemp or cd can never point the trap at another directory
if ! work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/retry-test.XXXXXX")" \
    || [ -z "${work}" ] || [ ! -d "${work}" ]; then
    echo "Error: cannot create a temporary directory ❌"
    exit 1
fi
# On Git Bash, RUNNER_TEMP keeps its drive letter (D:\a\_temp), whose
# colon would split the stub directory in PATH; use the POSIX form
if ! canonical="$(cd -- "${work}" && pwd -P)" || [ -z "${canonical}" ]; then
    echo "Error: cannot resolve temporary directory ${work} ❌"
    rmdir -- "${work}" 2> /dev/null
    exit 1
fi
work="${canonical}"
trap 'rm -rf -- "${work}"' EXIT
mkdir -p "${work}/bin"

cat > "${work}/bin/go" << 'EOF'
#!/usr/bin/env bash
calls=0
if [ -f "${STUB_STATE}/calls" ]; then
    calls="$(cat "${STUB_STATE}/calls")"
fi
calls=$((calls + 1))
echo "${calls}" > "${STUB_STATE}/calls"
echo "stub go call ${calls}: $*"
if [ "${calls}" -le "${STUB_FAIL_CALLS}" ]; then
    echo "${STUB_MESSAGE}" >&2
    exit "${STUB_STATUS}"
fi
exit 0
EOF
cat > "${work}/bin/sleep" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "${STUB_STATE}/sleeps"
EOF
chmod +x "${work}/bin/go" "${work}/bin/sleep"

failures=0
case_count=0
output=""
rc=0

# run_case ATTEMPTS FAIL_CALLS STATUS MESSAGE
run_case() {
    rm -rf -- "${work}/state"
    mkdir -p "${work}/state"
    output="$(
        PATH="${work}/bin:${PATH}" \
            STUB_STATE="${work}/state" \
            STUB_FAIL_CALLS="$2" \
            STUB_STATUS="$3" \
            STUB_MESSAGE="$4" \
            MODULE_DOWNLOAD_ATTEMPTS="$1" \
            bash "${retry_script}" go build ./... 2>&1
    )"
    rc=$?
}

calls() {
    cat "${work}/state/calls" 2> /dev/null || echo 0
}

sleeps() {
    if [ -f "${work}/state/sleeps" ]; then
        tr '\n' ' ' < "${work}/state/sleeps"
    fi
}

warnings() {
    printf '%s\n' "${output}" | grep -c '^::warning::' || true
}

# check NAME ACTUAL EXPECTED
check() {
    if [ "$2" != "$3" ]; then
        echo "FAIL [${current}] $1: expected '$3', got '$2'"
        printf '%s\n' "${output}" | sed 's/^/    | /'
        failures=$((failures + 1))
    fi
}

start() {
    current="$1"
    case_count=$((case_count + 1))
}

transient='github.com/fatih/color@v1.9.0: read "https://proxy.golang.org/x":'
transient+=' stream error: stream ID 2543; INTERNAL_ERROR; received from peer'
compile_error='./main.go:5:2: undefined: foo'

start "transient once, then success"
run_case 3 1 1 "${transient}"
check "exit status" "${rc}" 0
check "attempts" "$(calls)" 2
check "warnings" "$(warnings)" 1
check "delays" "$(sleeps)" "5 "
case "${output}" in
    *"attempt 1 of 3 failed with transient error 'stream error:'"*) ;;
    *) check "warning text" "missing" "present" ;;
esac

start "transient on every attempt"
run_case 3 99 1 "${transient}"
check "exit status" "${rc}" 1
check "attempts" "$(calls)" 3
check "warnings" "$(warnings)" 2
check "delays" "$(sleeps)" "5 15 "
case "${output}" in
    *"stub go call 3: build ./..."*"${transient}"*) ;;
    *) check "last output shown" "missing" "present" ;;
esac

start "delays cap at 30 seconds"
run_case 5 99 1 "dial tcp: i/o timeout"
check "attempts" "$(calls)" 5
check "delays" "$(sleeps)" "5 15 30 30 "

start "compile error is not retried"
run_case 3 99 1 "${compile_error}"
check "exit status" "${rc}" 1
check "attempts" "$(calls)" 1
check "warnings" "$(warnings)" 0
check "delays" "$(sleeps)" ""
case "${output}" in
    *"${compile_error}"*) ;;
    *) check "build output shown" "missing" "present" ;;
esac

start "success first time"
run_case 3 0 1 ""
check "exit status" "${rc}" 0
check "attempts" "$(calls)" 1
check "warnings" "$(warnings)" 0
check "delays" "$(sleeps)" ""

start "exit status is the build's, not tee's"
run_case 3 99 7 "${compile_error}"
check "exit status" "${rc}" 7
run_case 2 99 42 "${transient}"
check "exit status after retries" "${rc}" 42
check "attempts" "$(calls)" 2

start "one attempt disables retries"
run_case 1 99 1 "${transient}"
check "exit status" "${rc}" 1
check "attempts" "$(calls)" 1
check "warnings" "$(warnings)" 0

start "markers match case-sensitively"
run_case 3 99 1 "Stream Error: internal_error"
check "attempts" "$(calls)" 1

start "invalid attempt count is rejected"
run_case 11 0 1 ""
check "exit status" "${rc}" 2
check "attempts" "$(calls)" 0

if [ "${failures}" -ne 0 ]; then
    echo "${failures} check(s) failed across ${case_count} cases ❌"
    exit 1
fi
echo "All ${case_count} retry-go-build cases passed ✅"
