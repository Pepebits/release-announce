# Changelog

## [1.1.0] - 2026-10-27

### Added

- **`ki` for macOS and Windows**: releases include `ki_<version>_darwin_<arch>.tar.gz` and `ki_<version>_windows_<arch>.zip` (amd64 and arm64), and `ki` installs with Homebrew from the Open Southeners tap (`brew install open-southeners/tap/ki`), ready for the upcoming `ki login` and Kiarga commands. `ki agent` commands stay server-side on Linux.

### Changed

- The repository moved to `github.com/open-southeners/ki` (the Go module path too). The old `open-southeners/ki-agent` URLs redirect, so existing installs, updates and the install command keep working.
- **`ki` command**: the CLI is now `ki`, with the agent's commands under `ki agent` (for example `ki agent projects list` and `sudo ki agent update`), as groundwork for upcoming Kiarga commands. Installs place `/usr/local/bin/ki` with `ki-agent` as a symlink to it, and the services run `ki agent run`. If you self-updated from 1.0.x, run `sudo ki-agent update` once (or re-run the installer) to add `ki`.

### Deprecated

- The `ki-agent` command name still works exactly like `ki agent` throughout 1.x, but `ki` is the name to use going forward.

