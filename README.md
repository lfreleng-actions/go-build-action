<!--
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation
-->

# 🛠️ Go Build Action

<!-- prettier-ignore-start -->
<!-- markdownlint-disable-next-line MD013 -->
[![Linux Foundation](https://img.shields.io/badge/Linux-Foundation-blue)](https://linuxfoundation.org/) [![Source Code](https://img.shields.io/badge/GitHub-100000?logo=github&logoColor=white&color=blue)](https://github.com/lfreleng-actions/go-build-action) [![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/lfreleng-actions/go-build-action/badge)](https://scorecard.dev/viewer/?uri=github.com/lfreleng-actions/go-build-action)
<!-- prettier-ignore-end -->

Builds Go projects with optional cross-compilation support.

## go-build-action

This action wraps `actions/setup-go` and `go build` behind a validated
interface. Without `output_name` the action performs a validation
build of `build_target` and emits no `binary_path` output; note
`go build` itself may still write a binary to the working directory
when the target is a single main package. With `output_name` it
builds a single main package to a named binary, supporting
cross-platform release matrices through the `goos`/`goarch` inputs.

## Usage Example

<!-- markdownlint-disable MD046 -->

```yaml
steps:
  - name: "Build project"
    id: build
    uses: lfreleng-actions/go-build-action@main
    with:
      path_prefix: '.'
```

Cross-compiled release binary:

```yaml
steps:
  - name: "Build release binary"
    id: build
    uses: lfreleng-actions/go-build-action@main
    with:
      build_target: './cmd/server'
      output_name: server-linux-arm64
      goos: linux
      goarch: arm64
      build_flags: '-trimpath'
      ldflags: '-s -w -X main.version=v1.2.3'
```

<!-- markdownlint-enable MD046 -->

## Requirements

The action runs on Linux, macOS and Windows runners and needs `bash`.
It resolves paths with GNU `realpath` where available (Linux, Git
Bash on Windows) and otherwise falls back to a pure-bash resolver
that needs `readlink`, so macOS runners need no GNU coreutils. The
action converts the paths it emits to native Windows form on Windows
runners. The action installs the Go
toolchain via the pinned `actions/setup-go`, with caching off per
organisation security policy, so runners need egress to the Go
distribution endpoints and, for the module download before the build,
to `proxy.golang.org` and `sum.golang.org`.

## Inputs

<!-- markdownlint-disable MD013 -->

| Name                     | Required | Default     | Description                                                                       |
| ------------------------ | -------- | ----------- | --------------------------------------------------------------------------------- |
| go_version               | False    | `''`        | Explicit Go version to install; takes precedence over go_version_file             |
| go_version_file          | False    | `go.mod`    | File to read the Go version from, relative to path_prefix; must resolve within it |
| path_prefix              | False    | `.`         | Project directory; must resolve within the workspace                              |
| build_flags              | False    | `''`        | Extra `go build` flags (restricted character set)                                 |
| goos                     | False    | `''`        | Target operating system (GOOS); requires goarch                                   |
| goarch                   | False    | `''`        | Target architecture (GOARCH); requires goos                                       |
| cgo_enabled              | False    | `0`         | CGO_ENABLED value for the build: `0` or `1`                                       |
| ldflags                  | False    | `''`        | Linker flags passed via `-ldflags` (restricted character set)                     |
| output_name              | False    | `''`        | Binary filename to build (restricted character set)                               |
| build_target             | False    | `./...`     | Space-separated package pattern(s) to build                                       |
| artifact_upload          | False    | `false`     | Upload the built binary as an artifact; requires output_name                      |
| artifact_name            | False    | `go-binary` | Artifact name (restricted character set)                                          |
| module_download_attempts | False    | `3`         | Attempts at `go mod download` before the build fails; an integer from 1 to 10     |

<!-- markdownlint-enable MD013 -->

## Outputs

<!-- markdownlint-disable MD013 -->

| Name                          | Description                                                      |
| ----------------------------- | ---------------------------------------------------------------- |
| binary_path                   | Absolute path to the built binary (when output_name set)         |
| go_version_used               | Go toolchain version the build used                              |
| module_download_outcome       | Result of the module download: `success`, `failure` or `skipped` |
| module_download_attempts_used | `go mod download` attempts made; `0` when skipped                |

<!-- markdownlint-enable MD013 -->

The action emits `binary_path` when the caller sets `output_name`;
for validation builds the output stays empty.

## Input Constraints

The action validates every input before use and fails closed on
anything outside the expected form:

- `build_flags` and `ldflags` accept the characters
  `A-Z a-z 0-9 space . _ / = , : @ + -` and nothing else, which
  excludes shell metacharacters such as backticks, `$(`, `;`, `&`,
  `|` and newlines
- `output_name` and `artifact_name` accept `A-Z a-z 0-9 . _ -`
- `build_target` accepts `A-Z a-z 0-9 space . _ / -` and rejects
  tokens starting with `-`, so package patterns cannot smuggle extra
  flags into the build command
- The action checks the `goos`/`goarch` pair against a known-good
  allowlist: `linux/amd64`, `linux/arm64`, `linux/arm`, `linux/386`,
  `linux/ppc64le`, `linux/s390x`, `linux/riscv64`, `darwin/amd64`,
  `darwin/arm64`, `windows/amd64`, `windows/arm64`, `windows/386`,
  `freebsd/amd64`, `freebsd/arm64`
- `cgo_enabled` accepts `0` or `1`; booleans accept `true` or `false`
- `module_download_attempts` accepts an integer from `1` to `10`,
  without leading zeros or whitespace

The action does not append `.exe` for Windows targets; include the
extension in `output_name` when it matters to downstream steps.

## Path Constraints

Relative values for `path_prefix` resolve against
`GITHUB_WORKSPACE`, not the current working directory, so behaviour
stays deterministic when a calling workflow sets a custom working
directory. The project directory must resolve within
`GITHUB_WORKSPACE`, and the version file must resolve within the
project directory; paths that escape these boundaries fail the
action, preventing builds against arbitrary runner filesystem
locations.

A `-C <dir>` flag in `build_flags` may appear anywhere in the flags,
at most once. A relative directory resolves against the project
directory; an absolute one, including a native Windows path such as
`D:/a/repo/repo/child`, stands as given. Either way it must stay
within `GITHUB_WORKSPACE`. The action
runs module discovery, the module download and the build there,
while `binary_path` stays in the project directory. As in `go`
itself, the argument after a value-taking flag is that flag's value:
`-gcflags -C` passes `-C` to the compiler and does not change
directory.

## Toolchain Selection

With `go_version` set, the action installs that exact version. With
`go_version` empty, it reads the version from `go_version_file`
(default `go.mod`) under `path_prefix`. For legacy modules with
ancient `go` directives (for example Jenkins-era Gerrit projects on
`go 1.16`), pass an explicit modern `go_version`: toolchains that old
lack the automatic toolchain switching that current tooling expects.

## Module Downloads

With module caching off, every run downloads every module, and a
single transient proxy error could fail the build. The action runs
`go mod download` in the project directory (or the `-C` directory)
before building and retries it on failure, up to
`module_download_attempts` times (default 3). It waits 5 seconds
after the first failure and 15 seconds after each later one, logs
each failed attempt as a warning, and fails with an error after the
last. `go build` runs once: the action never retries a compile error.

The download uses the caller's `GOPROXY`, `GOPRIVATE`, `GONOSUMDB` and
`GOFLAGS` unchanged, plus any `-modfile`, `-overlay` or `-modcacherw`
flag in `build_flags`, so it fetches the module graph the build will
use. The one exception is a `-reuse` in `GOFLAGS`: `go build` ignores
it, but `go mod download` and `go list` reject it inside a module, so
the action clears it for those commands alone. Likewise the action's
own `go env` reads turn off the `go env` flags `-json`, `-u`, `-w` and
`-changed`, which `go build` ignores in `GOFLAGS` but which would turn
a read into a write or empty its answer. `actions/setup-go` runs its
own `go env`, so the action clears `GOFLAGS` for that step alone.
When the build runs
with `-mod=mod` (from `build_flags` or `GOFLAGS`), each attempt also
runs `go list -e -deps` with the build's flags and targets, so imports
that `go.mod` lacks resolve inside the retry too; an import no module
provides then fails as a download failure. That query turns off the
`go list` flags `go build` ignores in `GOFLAGS` (such as `-find`,
`-m`, `-test`, `-json` and `-reuse`), which would otherwise fail or
change it. A package that fails to load because the download could
not fetch its module fails the attempt, but a source error in source
already on disk, such as two package names in one directory of the
main module, of a module replaced by a local directory, of a
dependency already in the module cache, or in the `.go` files a
`build_target` names, is not retried and fails in `go build` at once.
Once the download succeeds, the action builds with `GOPROXY=off` and
`GONOPROXY=none`, so a build that needs a module the download missed
fails at once rather than fetching it, from the proxy or straight from
version control, outside the retry.

The action skips the download, and leaves the build's environment
untouched, when the build uses vendor mode and for a directory with no
`go.mod` or `go.work`. It finds the module mode as `go` does, reading
`GOFLAGS` with Go's own quoting rules (quoted fields, any whitespace
including newlines between flags): a `-mod` or `-modfile` in
`build_flags` wins over one in `GOFLAGS`, even with an empty value
(`-mod=`); without a `-mod`, a `vendor` directory beside `go.mod` (or
beside `go.work` in workspace mode) selects vendor mode when the `go`
directive, read from the `-modfile` if `build_flags` or `GOFLAGS`
names one, is 1.14 or later and `go` wrote `vendor/modules.txt` in the
same mode. With an `-overlay` in effect (from `build_flags` or
`GOFLAGS`) outside workspace mode, the action finds the main module
and its `go` directive with `go list -m`, which applies the overlay:
a `go.mod` that the overlay alone supplies, or whose `go` directive
the overlay changes, counts as the build sees it.
A vendored module built with `-mod=mod` or `-mod=readonly`
downloads, with retries. A Go workspace downloads the modules of every
workspace member. The `module_download_outcome` and
`module_download_attempts_used` outputs report what happened.

## Monorepo and Nested Module Support

Point `path_prefix` at the directory containing the module's
`go.mod`. This supports repositories where the module is not at the
repository root, for example Gerrit-hosted monorepos such as
`onap/multicloud-k8s`, where Go modules live under `src/`:

<!-- markdownlint-disable MD046 -->

```yaml
steps:
  - name: "Build nested module"
    uses: lfreleng-actions/go-build-action@main
    with:
      path_prefix: 'src/k8splugin'
      go_version: '1.25.11'
      build_target: './cmd'
      output_name: k8splugin
```

<!-- markdownlint-enable MD046 -->

## Implementation Details

<!-- markdownlint-disable MD013 -->

1. **Input Validation**: Validates booleans, flag character allowlists, the GOOS/GOARCH pair, filenames and path boundaries before use
2. **Toolchain Setup**: Installs Go via the pinned `actions/setup-go` with `cache: false` (organisation security stance on cache poisoning)
3. **Module Download**: Runs `go mod download` with bounded retries, skipping it in vendor mode, then builds offline with `GOPROXY=off` and `GONOPROXY=none`
4. **Build**: Runs `go build` once in the project directory, with `-o` when the caller names a binary, exporting GOOS/GOARCH/CGO_ENABLED for cross-compilation
5. **Outputs and Summary**: Emits the binary path and toolchain version, plus a step summary; the optional artifact upload uses the pinned `actions/upload-artifact`

<!-- markdownlint-enable MD013 -->

## Notes

- When the module has no buildable main package, leave `output_name`
  unset: the default `go build ./...` validation build compiles every
  package without producing binaries
- The action writes the binary into the project directory as
  `<path_prefix>/<output_name>` and reports the absolute path through
  `binary_path`
