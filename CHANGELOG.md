# Changelog

All significant changes in one place.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [2.0.0] – 2026-06-16
### Added
- **`refresh_cloud_senders.sh`** — companion tool that recursively expands the SPF
  records of major mail providers (Microsoft 365, Google Workspace, Amazon SES,
  SendGrid, Mailgun, Mimecast) into a deduplicated list of ip4/ip6 CIDR ranges.
  - Recursively follows `include:` and `redirect=` with a depth limit and loop guard.
  - `-d EXISTING` diff mode: prints only ranges not already present in a whitelist.
  - `-o OUTPUT` custom output path, `--version` flag.
  - Generates output ready to feed into `add_whitelists.sh -f`.
- `--version` flag for `add_whitelists.sh` (reports script version, starting at v2.0).
- Automatic backup rotation: removes whitelist backups older than 30 days.
- Project documentation overhaul: bilingual READMEs (`README.md` / `README_RU.md`),
  `LICENSE` (MIT), `SECURITY.md`, `.editorconfig`, issue and pull request templates,
  and a corrected Contributor Covenant `CODE_OF_CONDUCT.md`.
- Sample whitelist moved to `examples/whitelist.example.txt` with safe placeholder data.
### Fixed
- **IP/CIDR routing bug.** IPs were added to Postfix only (Postgrey was skipped),
  and CIDR ranges were dropped entirely. Now:
  - Domain → Postfix (`entry OK`) + Postgrey (`entry`)
  - IP     → Postfix (`entry OK`) + Postgrey (`entry`)
  - CIDR   → Postgrey only (`entry`); Postfix is skipped because hash maps
    do not support CIDR (an info message explains why).
### Changed
- Summary now shows separate counters: Postfix added, Postgrey added, errors.
- Removed the `SKIPPED_PG` counter (it was a workaround for the routing bug).
- ShellCheck workflow now fails on real problems (removed `|| true`), runs `bash -n`,
  declares `permissions: contents: read`, and supports `workflow_dispatch`.
- ShellCheck clean across both scripts.

## [1.0.0] – 2025-07-21
- Initial release:
- Core script `add_whitelists.sh` with dry-run support, `-h`, `-n`, `-f` flags and validation.
- Backups and rotation older than 30 days.
- Clear documentation in `README.md`.
- MIT license.
- CI: ShellCheck workflow.
