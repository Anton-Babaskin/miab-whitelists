# Changelog

All significant changes in one place.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [2.1.0] – 2026-07-19
### Added
- **`--setup` — one-command Postfix integration.** Idempotently wires
  `check_client_access hash:/etc/postfix/client_whitelist` and
  `check_client_access cidr:/etc/postfix/client_whitelist_cidr` into
  `smtpd_recipient_restrictions`, inserted right before the first
  `check_policy_service` (Postgrey). A whitelisted client therefore skips
  greylisting but still passes RBL checks and `reject_unlisted_recipient`.
  The existing restrictions chain is preserved — nothing is hardcoded.
  Map files (and the hash `.db`) are created before `postfix reload`, so the
  reload cannot fail on a missing map. Safe to re-run after MIAB updates.
- **`--check`** — shows whether both maps are wired in and prints the current
  restrictions chain; exit code 0 = wired, 2 = not wired (scriptable).
- **CIDR support in Postfix via a `cidr:` map.** IPv4 and IPv6 CIDR ranges now
  go to `/etc/postfix/client_whitelist_cidr` (plus Postgrey, as before).
  IPv6 CIDR entries are no longer rejected as invalid.
- Safety net: if entries were added while the maps are not wired into Postfix,
  the script warns and suggests `--setup` instead of silently feeding a dead file.
- The cidr map file gets the same backups and 30-day rotation as the other files.
### Changed
- `postfix reload` instead of `systemctl restart postfix` — active SMTP
  sessions are no longer dropped when applying whitelist changes.
- Whitespace trimming switched from `xargs` to `sed` (input containing quotes
  no longer breaks parsing); CR characters from CRLF files are stripped.
### Fixed
- **Dry-run crash under `set -e`.** In v2.0, `backup_if_exists`/`ensure_file`
  returned non-zero in dry-run mode, silently killing the script after the
  first backup message. Dry-run now runs to completion.
- The script no longer exits with status 1 when audit logging is unavailable.

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
