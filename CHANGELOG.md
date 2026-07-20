# Changelog

All significant changes in one place.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [2.4.1] – 2026-07-20
`refresh_cloud_senders.sh` v1.3 — closes the remaining review findings.
### Fixed
- **Diff mode compares the first field only.** `-d /etc/postfix/client_whitelist_cidr`
  used to compare against whole lines (`CIDR OK`), so every existing range was
  reported as new on every run.
- **Honest DNS failure handling.** Network-level failures (dig timeout/SERVFAIL)
  are now distinguished from empty answers (no TXT/NXDOMAIN) and counted:
  partial results exit 3 with a warning, `--apply` refuses to apply partial
  data, and if nothing was collected at all the script exits 1 **without
  overwriting the previous output file**.
- **Phantom counters on total DNS failure.** An empty result array used to
  produce a single empty element, reporting `ip4=1, ip6=1` on a fully failed
  run.
### Added
- `tests/run_refresh_tests.sh` — 16 sandboxed checks with a fixture `dig` stub:
  SPF recursion, include cycles, dedup, first-field diff, partial/total DNS
  failure, `--apply` refusal. Wired into CI.

## [2.4.0] – 2026-07-20
Safety release based on an external security review. Project logic is
unchanged: two-layer deliverability (Postfix maps first, Postgrey `.local`
as the redundant layer that survives MIAB updates).

### Security
- **`--remove` no longer feeds user input into regexes.** The entry is
  validated as a domain/IP/CIDR first (regex-looking garbage is refused),
  and removal is an exact first-field comparison in awk with an atomic
  tmp+mv write. Previously a crafted argument like `.*` could wipe all
  whitelist files. `already_in_file` moved to the same awk exact match.
### Added
- **Real input validation:** IPv4 octets ≤255 and no leading zeros, IPv4
  prefix ≤32, structural IPv6 checks (single `::`, ≤4 hex digits per group,
  group count) and IPv6 prefix ≤128. `999.999.999.999`, `10.0.0.0/99`,
  `2001:db8::/129` are now rejected.
- **Transactional batches:** the whole input is validated first; any invalid
  entry aborts the run with exit 2 and nothing applied. `--best-effort`
  restores the old permissive behavior explicitly. Stable exit codes
  (0 ok / 1 runtime / 2 validation) for Ansible and monitoring.
- **Order-aware `--check`:** verifies both tokens are present, positioned
  BEFORE the first `check_policy_service` (maps placed after postgrey never
  fire) and not duplicated; misordered/duplicated wiring is exit 2 with an
  explanation.
- **Self-repairing `--setup`:** rebuilds the restrictions chain — strips all
  existing occurrences of our tokens (fixes duplicates and wrong position)
  and re-inserts them at the correct point.
- **Rollback in `--setup`:** the previous `smtpd_recipient_restrictions`
  value is restored automatically if `postfix check` or `postfix reload`
  fails — a broken main.cf is never left behind.
### Changed
- Docs clarify that entries match the CONNECTING CLIENT (rDNS hostname/IP),
  not the From: header (`check_client_access` semantics).

## [2.3.1] – 2026-07-19
### Added
- **`sync_whitelists.sh` v1.0 — fleet auto-sync.** Keeps a server's whitelists
  converged with a git repository: `git pull --ff-only` → apply via
  `add_whitelists.sh -f` → verify wiring via `--check` and automatically
  re-run `--setup` if a MIAB update unwired the maps. Failures go to syslog
  and (optionally) e-mail via `ALERT_EMAIL`.
  - `--install` writes a sample config (`/etc/miab-whitelists/sync.conf`),
    installs the script to `/usr/local/bin` and enables a daily systemd timer
    (06:30 ± 30 min randomized, `Persistent=true` catches up after downtime).
  - Sandboxed test suite `tests/run_sync_tests.sh` (10 checks), wired into CI.

## [2.3.0] – 2026-07-19
### Changed
- **~24x faster bulk imports** (21.5s → 0.9s for 2000 entries in benchmarks).
  Three fork storms eliminated from the per-entry hot path:
  - duplicate checks now use in-memory hash lookups (existing files are read
    once into associative arrays) instead of two `grep` processes per entry;
  - `trim_lower` rewritten in pure bash (no `tr | sed` pipeline and no
    command-substitution subshell per line);
  - `log_line` timestamps use the bash builtin `printf '%(...)T'` instead of
    forking `date(1)` twice per entry.
- Postgrey: try `systemctl reload` (SIGHUP re-reads whitelists) before
  falling back to restart.

## [2.2.0] – 2026-07-19
### Added
- **`--remove ENTRY`** — removes an entry from all three whitelist files
  (Postfix hash, Postfix cidr, Postgrey) with backups, then rebuilds/reloads
  only what actually changed. Exit 1 if the entry was not found anywhere.
- **`--verify ENTRY`** — answers "is this client actually whitelisted?":
  queries the hash map via `postmap -q`, checks real CIDR containment for
  addresses via the cidr map, checks Postgrey, and reports whether the maps
  are wired into Postfix. Exit 0 = whitelisted at Postfix level, 1 = not.
- **`--list`** — prints all three whitelist files with entry counters and
  modification times, plus the current Postfix integration status.
- **Bare IPv6 addresses** are now accepted (e.g. `2001:db8::15`) and routed
  to the cidr map (matched as a full-length address) + Postgrey.
- **Functional test suite** (`tests/run_tests.sh`) — 37 sandboxed checks
  covering routing, dry-run, duplicates, `--setup` idempotency, partial
  wiring, `--remove`, `--verify` and `--list`; runs in CI on every push
  alongside ShellCheck (workflow renamed to "CI" with a test job).
- **`refresh_cloud_senders.sh` v1.2: `--apply`** — feeds the generated list
  straight into `add_whitelists.sh -f` (in diff mode only the new ranges are
  applied; skipped when there is nothing new). Requires root; the location of
  `add_whitelists.sh` is resolved before generation starts.

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
