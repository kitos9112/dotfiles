# Deterministic Chezmoi Modernization Design

## Objective

Make this dotfiles repository simpler to understand, deterministic to render,
straightforward to test, and explicit about the chezmoi features it requires.
Preserve current bootstrap/profile behavior while removing obsolete code and
duplicated maintenance work.

## Scope

This modernization covers:

- pinned release versions for archive and standalone-file externals;
- pure, offline chezmoi template rendering;
- a chezmoi 2.72.0 minimum-version contract;
- stricter template data handling and shell-safe interpolation;
- native chezmoi completion generation;
- consolidation of duplicated ASDF maintenance scripts;
- focused offline contract tests and one local test entry point;
- removal of confirmed no-op or superseded files; and
- matching README and CI documentation.

This work does not replace asdf, Homebrew, Oh My Zsh, editors, terminal
configurations, or the existing desktop/server and work/personal profile model.
Git-repository externals retain their current refresh-period behavior because
their static URLs do not make template rendering depend on the network.

## Architecture

The repository will have three clear layers.

### Declarative data

Machine profiles, packages, fonts, and release versions live under
`home/.chezmoidata/`. A new `versions.yaml` stores the versions currently
resolved dynamically for asdf, uv, fzf, Nerd Fonts, retry, direnv, VS Code, and
Go. The migration initializes every pin to the latest stable upstream release
available when implementation begins. After that commit, Renovate is the only
automated mechanism that updates the pins.

Each version has a Renovate-recognizable dependency declaration. Version bumps
therefore arrive as ordinary reviewed commits and are exercised by CI before
reaching machines.

### Chezmoi rendering

`home/.chezmoiexternal.yaml` transforms checked-in data plus platform and
profile values into external definitions. Rendering does not call `curl`,
`git ls-remote`, a release API, or a shell command that writes a cache.

The custom version/revision cache templates are removed:

- `get-github-latest-version`;
- `get-github-head-revision`, which has no current consumers;
- `read-versions-and-revisions-cache`; and
- `save-versions-and-revisions-cache`.

Templates touched by the migration use chezmoi's `shellQuote` or
`shellQuoteList` functions when emitting shell arguments. Optional data uses
`get`, `hasKey`, or `default` explicitly. Once all templates render without
implicit missing values, the repository removes `missingkey=zero` and returns
to chezmoi's `missingkey=error` default.

`home/.chezmoiversion` becomes `2.72.0`, the first release that supplies the
shell quoting functions used by this repository.

### Execution and verification

Chezmoi scripts perform only work that cannot be represented declaratively.
They are idempotent, have one responsibility, and avoid doing general package
upgrades during every `chezmoi apply`.

Offline contract tests verify rendering and script behavior. Separate Linux
container and macOS smoke tests exercise real installation and target-state
application.

## Dependency and External Behavior

Release archive and standalone binary URLs use the pinned values from
`versions.yaml`. The URL layout remains the same unless the upstream release
requires a different stable asset naming scheme. Platform and architecture
mapping remains centralized in the existing helper templates.

The custom cross-run cache is deleted instead of repaired. This eliminates its
inverted `--refresh-externals` behavior, side effects during rendering, shell
quoting risk in the cache writer, and dependence on `curl` and GitHub during
template evaluation.

`refreshPeriod` remains meaningful for fetching the external artifact itself;
it no longer controls discovery of an unreviewed new version.

## Script Simplification

### Completion generation

The checked-in chezmoi Zsh completion becomes a template whose content is:

```text
{{ completion "zsh" }}
```

The apply-time script that runs `chezmoi completion` and writes back into the
source checkout is removed. Existing third-party completion files remain
unchanged unless their current update path is proven safe and declarative.

### ASDF maintenance

ASDF plugin declarations become data rather than repeated shell calls. One
`run_onchange_` script fingerprints the plugin manifest and `.tool-versions`,
adds missing plugins, and installs the declared versions. Re-running with the
same inputs is a no-op from chezmoi's perspective.

The duplicated `asdf plugin update --all` and `asdf install` operations in the
current after scripts are consolidated. Routine `brew update`, `brew upgrade`,
and unconditional ASDF upgrades are removed from `chezmoi apply`; they are
explicit maintenance actions rather than dotfile convergence.

Remaining scripts that source `home/scripts/.helpers` migrate to the maintained
`scripts-library`. If no consumer remains, `.helpers` is removed. Scripts use
debug tracing only when `DOTFILES_DEBUG` is set; normal applies do not enable
verbose shell execution by default.

The Rust and IaC scripts are checked against current manifests. They are removed
only where the same outcome is already provided elsewhere; otherwise they are
kept and converted to the same idempotent, manifest-driven pattern.

### Confirmed obsolete files

The following files are removed:

- `home/ansible.cfg`, which contains no active settings;
- `home/.chezmoiscripts/run_after_102-reload.zsh.tmpl`, which performs no work;
- `home/scripts/install_dotfiles.sh`, the ignored superseded installer; and
- any legacy helper left with no consumers after script consolidation.

## Testing Design

The existing bootstrap contract is refactored, not rewritten. Common setup,
rendering, and assertions move into a small `tests/lib/` helper. Focused test
files cover:

1. profile resolution and generated chezmoi configuration;
2. package selection and pinned external rendering;
3. desktop, font, GNOME, and terminal behavior;
4. rendered script syntax, ordering, and first-bootstrap resilience;
5. Claude settings merge behavior; and
6. repository policy, including offline rendering and strict missing keys.

Tests call `chezmoi execute-template --file` for source templates and use
`--override-data` to supply Linux Ubuntu, Linux AlmaLinux, and macOS data under
desktop and server profiles. They render complete templates rather than
deleting guards with `sed`, and they never depend on the developer's chezmoi
configuration.

`task test` is the single fast local entry point. It runs all split template
contracts plus the existing FreeIPA, Go tools, Wireshark, and shell-history
backup contracts.

CI invokes `task test` under a matrix containing:

- chezmoi 2.72.0, proving the declared floor; and
- the latest stable chezmoi release, providing forward-compatibility coverage.

Existing Linux Docker smoke tests continue to cover AlmaLinux 9, AlmaLinux 10,
Ubuntu 24.04, and Ubuntu 26.04. The macOS smoke test continues to apply and
verify a temporary home. Smoke tests remain separate from offline contracts
because downloads and package installation are their intended responsibility.

## Error Handling

The following conditions fail immediately with actionable output:

- invalid profile, root, or Homebrew override values;
- missing required template data;
- malformed generated TOML, JSON, YAML, or shell;
- a network lookup attempted during an offline rendering contract;
- a source-tree mutation caused by a dry run or test apply; and
- a noninteractive target conflict in CI.

Optional environmental operations such as installing a convenience tool or
refreshing a nonessential integration may warn and continue. Merge-style
targets and state-changing helpers retain explicit idempotency tests.

## Documentation

The README will explain that:

- external release versions are pinned in `.chezmoidata/versions.yaml`;
- Renovate proposes version updates;
- `task test` runs all fast local contracts;
- CI tests both the minimum and latest chezmoi versions; and
- package upgrades are no longer an implicit side effect of every apply.

The documented distro matrix remains identical to the actual Docker matrix.

## Acceptance Criteria

The modernization is complete when:

- chezmoi template contracts pass without network access;
- no release version is discovered dynamically during rendering;
- chezmoi 2.72.0 and latest both pass `task test` in CI;
- Linux and macOS smoke tests remain valid;
- all rendered scripts pass the appropriate shell syntax checks;
- `uvx pre-commit run --all-files` passes;
- a dry run and test apply leave the source tree unchanged;
- duplicate ASDF/package-upgrade work is removed from normal applies;
- approved obsolete files and unreferenced helpers are gone;
- README and CI describe the implemented behavior; and
- all implementation changes are committed using conventional commits.
