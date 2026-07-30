# Go-Native Developer Tools Design

## Goal

Manage Go-based developer tools declaratively with Go's native tool manifest,
allow Renovate to update them through its built-in `gomod` manager, and make
chezmoi installs reliable across asdf-managed Go upgrades.

## Confirmed failure

When `.tool-versions` changes from one Go patch release to another, an existing
interactive shell can still export `GOROOT`, `GOPATH`, and `GOBIN` for the old
asdf installation. Chezmoi then installs the new Go version in one `run_after`
process and invokes the new Go shim in a later process. The later process
inherits the old Go environment and fails with a compiler/standard-library
version mismatch.

A fresh bootstrap has a related failure mode: the asdf-generated Go shim calls
plain `asdf`, but `~/.local/bin` is not guaranteed to be in chezmoi's inherited
`PATH`.

## Architecture

The managed target `~/.config/dotfiles/go-tools` contains `go.mod` and `go.sum`.
The module declares every Go CLI with a Go 1.24+ `tool` directive. The initial
tool is `github.com/mbrt/gmailctl/cmd/gmailctl` at `v0.12.0`.

A `run_onchange_after_104-install-go-tools.zsh.tmpl` script replaces the current
always-running gmailctl installer. Its rendered content embeds checksums of
`go.mod`, `go.sum`, and `.tool-versions`, so chezmoi reruns it when a tool or the
selected Go runtime changes.

The script invokes `~/.local/bin/asdf` directly and supplies
`ASDF_DATA_DIR=~/.asdf`. It removes inherited `GOROOT`, `GOPATH`, and `GOBIN`
before `asdf exec go`, allowing the asdf-golang plugin to construct a
self-consistent environment for the newly selected runtime. `go install tool`
installs binaries into that Go version's asdf `bin` directory, after which
`asdf reshim golang` refreshes command shims.

## Failure handling

The installer uses strict shell options and fails the chezmoi apply if asdf,
the selected Go version, module download, compilation, installation, or reshim
fails. The earlier asdf update script must no longer convert `asdf install`
failures into success.

No tool version is resolved dynamically by the installer. Network access is
only required when Go needs modules that are absent from its cache.

## Testing

A hermetic shell regression test renders the chezmoi installer into a temporary
home and uses a recording asdf executable. It starts with stale Go environment
variables and a `PATH` that does not contain asdf. The test proves that the
installer:

- finds asdf by its managed absolute path;
- removes stale Go environment variables;
- runs `go -C <manifest> install tool`;
- refreshes golang shims; and
- contains change-detection fingerprints for both the manifest and runtime pin.

The same test suite renders the asdf update script with a failing asdf
executable and verifies that the failure propagates.

## Future consolidation boundary

This change consolidates only Go-built developer tools. A later, separate
project can move language runtimes and cross-language CLIs to mise, leaving
Homebrew responsible for operating-system libraries, services, and GUI
applications. This design does not change PATH ownership or introduce a second
runtime manager.
