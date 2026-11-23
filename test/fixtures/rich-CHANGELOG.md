# Changelog

## [2.0.0] - 2026-11-20

A big one: the config format changed.

Upgrade note: run `demo migrate` once before starting 2.0.

### Changed

The config file moved to `~/.config/demo/config.toml`.

- Settings are read from TOML instead of JSON. Run the migration:

  ```bash
  demo migrate --from ~/.demo.json
  ```

  The old file is kept as a backup.
- Logs rotate daily.
  1. Old logs are gzipped.
  2. After 30 days they are removed.

### Removed

Only prose here: the `--legacy` flag is gone, without a replacement.

### Fixed

- [x] Crash on empty input
- [ ] Memory leak on reload (still investigating)
- A link to [the issue](https://github.com/demo/demo/issues/1) and <https://example.com>.

#### Windows

- Paths with spaces work.

### Security

> Upgrade as soon as possible: CVE-2026-0001 allowed **remote** code execution.
> Thanks to the reporter.

| Platform | Status |
|:---|:---:|
| Linux | ✅ |
| macOS | ✅ `arm64` too |

<!-- not shown -->
[2.0.0]: https://github.com/demo/demo/compare/v1.0.0...v2.0.0
