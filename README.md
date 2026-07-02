<!--
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation
-->

# 🛠️ Go Build Action

<!-- prettier-ignore-start -->
<!-- markdownlint-disable-next-line MD013 -->
[![Linux Foundation](https://img.shields.io/badge/Linux-Foundation-blue)](https://linuxfoundation.org/) [![Source Code](https://img.shields.io/badge/GitHub-100000?logo=github&logoColor=white&color=blue)](https://github.com/lfreleng-actions/go-build-action) [![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![pre-commit.ci status badge]][pre-commit.ci results page] [![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/lfreleng-actions/go-build-action/badge)](https://scorecard.dev/viewer/?uri=github.com/lfreleng-actions/go-build-action)
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

The action needs `realpath` (GNU coreutils) on the runner.
GitHub-hosted Ubuntu runners include it; minimal self-hosted or
non-Linux runners must provide it. The action installs the Go
toolchain via the pinned `actions/setup-go`, with caching off per
organisation security policy, so runners need egress to the Go
distribution endpoints and, for module downloads during the build, to
`proxy.golang.org` and `sum.golang.org`.

## Inputs

<!-- markdownlint-disable MD013 -->

| Name            | Required | Default     | Description                                                                       |
| --------------- | -------- | ----------- | --------------------------------------------------------------------------------- |
| go_version      | False    | `''`        | Explicit Go version to install; takes precedence over go_version_file             |
| go_version_file | False    | `go.mod`    | File to read the Go version from, relative to path_prefix; must resolve within it |
| path_prefix     | False    | `.`         | Project directory; must resolve within the workspace                              |
| build_flags     | False    | `''`        | Extra `go build` flags (restricted character set)                                 |
| goos            | False    | `''`        | Target operating system (GOOS); requires goarch                                   |
| goarch          | False    | `''`        | Target architecture (GOARCH); requires goos                                       |
| cgo_enabled     | False    | `0`         | CGO_ENABLED value for the build: `0` or `1`                                       |
| ldflags         | False    | `''`        | Linker flags passed via `-ldflags` (restricted character set)                     |
| output_name     | False    | `''`        | Binary filename to build (restricted character set)                               |
| build_target    | False    | `./...`     | Space-separated package pattern(s) to build                                       |
| artifact_upload | False    | `false`     | Upload the built binary as an artifact; requires output_name                      |
| artifact_name   | False    | `go-binary` | Artifact name (restricted character set)                                          |

<!-- markdownlint-enable MD013 -->

## Outputs

<!-- markdownlint-disable MD013 -->

| Name            | Description                                              |
| --------------- | -------------------------------------------------------- |
| binary_path     | Absolute path to the built binary (when output_name set) |
| go_version_used | Go toolchain version the build used                      |

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

## Toolchain Selection

With `go_version` set, the action installs that exact version. With
`go_version` empty, it reads the version from `go_version_file`
(default `go.mod`) under `path_prefix`. For legacy modules with
ancient `go` directives (for example Jenkins-era Gerrit projects on
`go 1.16`), pass an explicit modern `go_version`: toolchains that old
lack the automatic toolchain switching that current tooling expects.

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
3. **Build**: Runs `go build` in the project directory, with `-o` when the caller names a binary, exporting GOOS/GOARCH/CGO_ENABLED for cross-compilation
4. **Outputs and Summary**: Emits the binary path and toolchain version, plus a step summary; the optional artifact upload uses the pinned `actions/upload-artifact`

<!-- markdownlint-enable MD013 -->

## Notes

- When the module has no buildable main package, leave `output_name`
  unset: the default `go build ./...` validation build compiles every
  package without producing binaries
- The action writes the binary into the project directory as
  `<path_prefix>/<output_name>` and reports the absolute path through
  `binary_path`

[pre-commit.ci results page]: https://results.pre-commit.ci/latest/github/lfreleng-actions/go-build-action/main
[pre-commit.ci status badge]: https://results.pre-commit.ci/badge/github/lfreleng-actions/go-build-action/main.svg
