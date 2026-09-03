# Tool Ownership, Locale, and Linux Packages Design

## Objective

Finish the actionable repository cleanup tracked by issues 3004, 1286, and
1288. Give duplicated developer tools one declared owner, add Spanish locale
data without changing the default locale, and make desktop application packages
profile-aware on Ubuntu, Fedora, and AlmaLinux.

## Scope

This work covers:

- closing issues 1287 and 1529 as already implemented or obsolete;
- closing issue 968 as a stale duplicate of Renovate dashboard issue 9;
- consolidating Go, kubectl, fzf, and direnv under asdf;
- removing their duplicate Homebrew, apt, and chezmoi-external declarations;
- generating `en_GB.UTF-8` and `es_ES.UTF-8` while retaining English as the
  primary system locale;
- replacing the one-time Fedora/AlmaLinux package list with a declarative,
  profile-aware dnf manifest and `run_onchange_` installer;
- adding Alacritty and Wireshark to native desktop package lists where the base
  distribution supplies them; and
- updating contracts and documentation for the resulting ownership model.

This work does not migrate from asdf to mise, add EPEL or another third-party
package repository, automatically uninstall packages from existing machines,
or change the supported acceptance-test distribution matrix.

## Tool Ownership

asdf is the single declared owner of versioned developer runtimes and CLIs that
are currently duplicated. The tracked asdf plugin manifest and
`.tool-versions` will own:

- Go;
- kubectl;
- fzf; and
- direnv.

Existing asdf-owned Node.js, Helm, Terraform, Terragrunt, and Packer behavior is
unchanged. uv remains a pinned chezmoi external because it is not currently
duplicated. Homebrew continues to own system-facing formulae and applications,
but its list will no longer include Go, kubernetes-cli, fzf, or direnv. The apt
manifest will no longer include direnv. The portable Go, fzf, and direnv
externals and their now-unused release pins will be removed.

Shell startup resolves fzf and direnv through normal command lookup after the
asdf shims directory has been placed first on `PATH`. The special-case
`~/.local/bin/fzf` preference is removed. Tests will verify that each migrated
tool has exactly one repository owner and that its asdf plugin and version are
rendered.

Removing a package declaration does not uninstall an already installed package.
An apply must not silently remove software that the operator may now manage
independently. The README will provide optional Homebrew and apt cleanup
commands and explain that asdf shims have precedence even before cleanup.

## Locale Model

`home/.chezmoidata/locale.yaml` will represent locale intent explicitly:

```yaml
locale:
  primary: en_GB.UTF-8
  additional:
    - es_ES.UTF-8
```

Ubuntu and Debian package convergence will generate the primary and additional
locales, then keep `LANG` set to the primary locale. Fedora and AlmaLinux will
install the native English and Spanish glibc language packs and set the system
locale to the primary value. Spanish support therefore becomes available to
applications without changing messages, sorting, dates, or numeric formatting
for the shell session.

Tests will render the package scripts and execute their locale-selection logic
against recording command doubles. They will assert that both locales are
requested and that only `en_GB.UTF-8` becomes the primary locale.

## Linux Package Manifests

`home/.chezmoidata/packages.yaml` will keep the existing apt manifest and add a
parallel dnf manifest. Each family has `common`, `desktop`, and `server` lists.
The dnf common list will absorb the packages currently embedded in
`run_once_before_01-linux-install-prereq.sh.tmpl`; the old script will retain no
duplicate package installation or distribution upgrade behavior.

Desktop application ownership is:

| Distribution family | Alacritty | Wireshark |
| --- | --- | --- |
| Ubuntu/Debian | native apt package | native apt package |
| Fedora | native dnf package | native dnf package |
| AlmaLinux | not installed | native dnf package |

AlmaLinux does not gain a third-party repository merely to obtain Alacritty.
Server profiles select neither application. Distribution-specific additions
will be represented in data rather than hard-coded shell branches.

A new `run_onchange_before_03-linux-dnf-packages.sh.tmpl` will fingerprint the
dnf manifest, select common/profile/distribution packages, install them in one
dnf invocation, install the locale language packs, and set the primary locale.
The apt and dnf scripts will use the same data-selection shape so their tests
can exercise equivalent desktop and server behavior.

## Issue Lifecycle

Issue-closing comments will explain the evidence and link to repository paths or
the completing commits. Issues 1287, 1529, and 968 may close before code changes
because their disposition is already true on the default branch. Issues 3004,
1286, and 1288 close only after their implementation commits are pushed and the
acceptance workflow passes. Until then, they receive progress comments rather
than premature closure.

## Testing

Development follows red-green-refactor cycles:

1. ownership contracts fail while duplicate providers remain;
2. locale contracts fail while only a scalar English locale exists;
3. package-selection and rendered-script contracts fail while dnf packages are
   embedded in a one-time script and desktop applications are absent;
4. the smallest manifest, template, shell, and documentation changes make each
   focused contract pass; and
5. the unified suite and pre-commit hooks run after all focused tests are green.

The Linux smoke matrix remains AlmaLinux 9, AlmaLinux 10, Ubuntu 24.04, and
Ubuntu 26.04. The containers continue to run `chezmoi init --apply` with scripts
excluded; fast contracts therefore carry the package-script behavior coverage.
Where the local container runtime is available, representative Ubuntu and
AlmaLinux images will also be built before completion.

## Error Handling and Migration Safety

- Unsupported profile or distribution data fails template rendering rather
  than silently choosing a package set.
- Package commands retain the repository's tolerate-and-warn behavior where a
  nonessential bootstrap step may be unavailable.
- No migration script uninstalls existing Homebrew or apt packages.
- No new repository or signing key is installed for Alacritty.
- Locale generation failures identify the locale and package family involved.
- No secrets, credentials, hostnames, or machine-confidential values enter the
  public repository or GitHub issue comments.

## Documentation

The README will document:

- the single-owner developer-tool table;
- how Renovate updates versions in `.tool-versions`;
- optional commands for removing legacy duplicate packages;
- the primary and additional locale model;
- apt and dnf manifest locations and profile selection; and
- the fact that AlmaLinux intentionally omits Alacritty without EPEL.

## Acceptance Criteria

The work is complete when:

- Go, kubectl, fzf, and direnv each have one declared repository owner;
- asdf convergence installs every migrated tool from tracked versions;
- shell integrations resolve the asdf-backed commands without a private path
  special case;
- both `en_GB.UTF-8` and `es_ES.UTF-8` are generated or installed while English
  remains primary;
- Ubuntu/Fedora desktop profiles include Alacritty and Wireshark;
- AlmaLinux desktop profiles include Wireshark but no third-party Alacritty
  source;
- server profiles include neither desktop application;
- dnf package changes converge through a manifest-driven `run_onchange_` script;
- focused tests demonstrate red-green behavior;
- `task test` and `uvx pre-commit run --all-files` pass;
- applicable smoke builds pass;
- README and GitHub issues describe the implemented state; and
- implementation changes use focused conventional commits.
