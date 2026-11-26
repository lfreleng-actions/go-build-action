#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation

# Isolated tests for the module_download_attempts check in the
# action's "Validate inputs" step.
#
# Usage: bash scripts/tests/test-validate-attempts.sh
#
# Extracts that step's run script from action.yaml and runs it the way
# a composite 'shell: bash' step does, against a fixture that passes
# every other check. A valid count must pass and an invalid one must
# fail with the attempt-count diagnostic, proving the action rejects it
# before Setup Go and the build run, not by some later failure.

set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
action_file="${script_dir}/../../action.yaml"

# Register cleanup only once the directory exists and is canonical, so
# a failed mktemp or cd can never point the trap at another directory
if ! work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/validate-test.XXXXXX")" \
    || [ -z "${work}" ] || [ ! -d "${work}" ]; then
    echo "Error: cannot create a temporary directory ❌"
    exit 1
fi
if ! canonical="$(cd -- "${work}" && pwd -P)" || [ -z "${canonical}" ]; then
    echo "Error: cannot resolve temporary directory ${work} ❌"
    rmdir -- "${work}" 2> /dev/null
    exit 1
fi
work="${canonical}"
trap 'rm -rf -- "${work}"' EXIT
mkdir -p "${work}/workspace"
printf 'module fixture\n\ngo 1.25\n' > "${work}/workspace/go.mod"

# Print the block scalar under the validate step's 'run: |', with the
# step's eight-space indentation removed
awk '
    /^      id: validate$/ { in_step = 1; next }
    in_step && /^      run: \|$/ { in_run = 1; next }
    in_run && /[^ ]/ && !/^        / { exit }
    in_run { sub(/^        /, ""); print }
' "${action_file}" > "${work}/validate.sh"

case "$(head -n 1 "${work}/validate.sh")" in
    "# Validate inputs") ;;
    *)
        echo "Error: cannot extract the Validate inputs step ❌"
        exit 1 ;;
esac
if grep -F -q '$''{{' "${work}/validate.sh"; then
    echo "Error: Validate inputs uses an expression; harness invalid ❌"
    exit 1
fi

failures=0
case_count=0
output=""
rc=0

# run_validate ATTEMPTS
run_validate() {
    : > "${work}/github_output"
    output="$(
        cd "${work}/workspace" &&
            GITHUB_WORKSPACE="${work}/workspace" \
            GITHUB_OUTPUT="${work}/github_output" \
            INPUT_GO_VERSION="" \
            INPUT_GO_VERSION_FILE="go.mod" \
            INPUT_PATH_PREFIX="." \
            INPUT_BUILD_FLAGS="" \
            INPUT_GOOS="" \
            INPUT_GOARCH="" \
            INPUT_CGO_ENABLED="0" \
            INPUT_LDFLAGS="" \
            INPUT_OUTPUT_NAME="" \
            INPUT_BUILD_TARGET="./..." \
            INPUT_ARTIFACT_UPLOAD="false" \
            INPUT_ARTIFACT_NAME="go-binary" \
            INPUT_MODULE_DOWNLOAD_ATTEMPTS="$1" \
            bash --noprofile --norc -eo pipefail "${work}/validate.sh" 2>&1
    )"
    rc=$?
    case_count=$((case_count + 1))
}

fail() {
    echo "FAIL [attempts=$(printf '%q' "$1")] $2"
    printf '%s\n' "${output}" | sed 's/^/    | /'
    failures=$((failures + 1))
}

for value in 1 3 10; do
    run_validate "${value}"
    if [ "${rc}" -ne 0 ]; then
        fail "${value}" "expected a pass, got exit ${rc}"
    elif ! grep -q '^setup_go_version_file<<' "${work}/github_output"
    then
        fail "${value}" "expected the setup_go_version_file output"
    fi
done

for value in 0 11 01 -1 +3 1.5 abc "" " 3" "3 " $'3\n'; do
    run_validate "${value}"
    if [ "${rc}" -eq 0 ]; then
        fail "${value}" "expected a failure, got exit 0"
        continue
    fi
    case "${output}" in
        *"Error: invalid module_download_attempts"*) ;;
        *) fail "${value}" "missing the attempt-count diagnostic" ;;
    esac
    if [ -s "${work}/github_output" ]; then
        fail "${value}" "expected no step outputs"
    fi
done

if [ "${failures}" -ne 0 ]; then
    echo "${failures} check(s) failed across ${case_count} cases ❌"
    exit 1
fi
echo "All ${case_count} module_download_attempts cases passed ✅"
