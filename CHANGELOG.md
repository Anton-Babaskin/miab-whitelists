# Changelog

All significant changes in one place.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]
- …

## [2.0.0] – 2026-06-15
### Fixed
- **IP/CIDR routing bug.** IPs were added to Postfix only (Postgrey was skipped),
  and CIDR ranges were dropped entirely. Now:
  - Domain → Postfix (`entry OK`) + Postgrey (`entry`)
  - IP     → Postfix (`entry OK`) + Postgrey (`entry`)
  - CIDR   → Postgrey only (`entry`); Postfix is skipped because hash maps
    do not support CIDR (an info message explains why).
### Added
- `--version` flag (reports script version, starting at v2.0).
- Automatic backup rotation: removes whitelist backups older than 30 days.
### Changed
- Summary now shows separate counters: Postfix added, Postgrey added, errors.
- Removed the `SKIPPED_PG` counter (it was a workaround for the routing bug).
- ShellCheck clean.

## [1.0.0] – 2025-07-21
- Initial release:
- Core script `add_whitelists.sh` with dry-run support, `-h`, `-n`, `-f` flags and validation.
- Backups and rotation older than 30 days.
- Clear documentation in `README.md`.
- MIT license.
- CI: ShellCheck workflow.
