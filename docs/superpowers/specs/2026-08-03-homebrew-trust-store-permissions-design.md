# Homebrew Trust Store Permissions Design

## Goal

Ensure fresh and previously configured machines can run the Homebrew tap-trust script without Homebrew rejecting an insecure trust-store directory.

## Design

Rename the managed `homebrew` directory below `private_dot_config` to `private_homebrew`. Chezmoi will continue mapping it to `~/.config/homebrew`, while the `private_` attribute declares mode `0700` independently of the invoking shell's umask.

Before calling `brew trust`, the existing after-stage script will create (if absent) and set mode `0700` on both stores it manages: `${XDG_CONFIG_HOME:-$HOME/.config}/homebrew` and `$HOME/.homebrew`. This accommodates the second store, which is created outside the managed source tree.

## Validation

Extend the bootstrap-profile contract test to execute the rendered trust script against intentionally group-writable temporary stores with a fake `brew`. The test asserts both stores become `0700`, and asserts that the source directory has the `private_` attribute.
