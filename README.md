<p align="right">
  🇬🇧 English · <a href="./README_RU.md">🇷🇺 Русский</a>
</p>

<div align="center">

# 📬 MIAB Whitelists

<!-- quick-start -->

## âš¡ Quick Start

```bash
git clone https://github.com/Anton-Babaskin/miab-whitelists.git && cd miab-whitelists && chmod +x add_whitelists.sh && sudo ./add_whitelists.sh --setup && sudo ./add_whitelists.sh example.com
```

> [!IMPORTANT]
> This changes Postfix/Postgrey whitelist configuration. Use -n for a dry run.

### A toolkit for managing Postfix & Postgrey whitelists on Mail-in-a-Box

<p>
  Two complementary Bash tools: add trusted senders by hand, and keep cloud provider IP ranges fresh straight from their SPF records.
</p>

<p>
  <a href="https://github.com/Anton-Babaskin/miab-whitelists/actions/workflows/shellcheck.yml">
    <img alt="ShellCheck" src="https://img.shields.io/github/actions/workflow/status/Anton-Babaskin/miab-whitelists/shellcheck.yml?branch=main&style=for-the-badge&logo=githubactions&logoColor=white&label=ShellCheck">
  </a>
  <img alt="Version" src="https://img.shields.io/badge/version-2.4-1f6feb?style=for-the-badge">
  <a href="./LICENSE">
    <img alt="MIT License" src="https://img.shields.io/github/license/Anton-Babaskin/miab-whitelists?style=for-the-badge">
  </a>
  <a href="https://github.com/Anton-Babaskin/miab-whitelists/commits/main">
    <img alt="Last commit" src="https://img.shields.io/github/last-commit/Anton-Babaskin/miab-whitelists?style=for-the-badge">
  </a>
</p>

<p>
  <img alt="Bash" src="https://img.shields.io/badge/Bash-4%2B-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white">
  <img alt="Mail-in-a-Box" src="https://img.shields.io/badge/Mail--in--a--Box-Compatible-1f6feb?style=for-the-badge">
  <img alt="Postfix" src="https://img.shields.io/badge/Postfix-Whitelist-336791?style=for-the-badge">
  <img alt="Postgrey" src="https://img.shields.io/badge/Postgrey-Whitelist-6f42c1?style=for-the-badge">
  <img alt="Platform" src="https://img.shields.io/badge/Debian%20%7C%20Ubuntu-Supported-E95420?style=for-the-badge&logo=ubuntu&logoColor=white">
</p>

<p>
  <a href="https://github.com/Anton-Babaskin/miab-whitelists/stargazers">
    <img alt="Stars" src="https://img.shields.io/github/stars/Anton-Babaskin/miab-whitelists?style=flat-square">
  </a>
  <a href="https://github.com/Anton-Babaskin/miab-whitelists/issues">
    <img alt="Issues" src="https://img.shields.io/github/issues/Anton-Babaskin/miab-whitelists?style=flat-square">
  </a>
  <a href="https://github.com/Anton-Babaskin/miab-whitelists/forks">
    <img alt="Forks" src="https://img.shields.io/github/forks/Anton-Babaskin/miab-whitelists?style=flat-square">
  </a>
</p>

</div>

---

## 🧰 Tools

| Tool | What it does | Needs root |
| ---- | ------------ | :--------: |
| [`add_whitelists.sh`](#-add_whitelistssh) | Add domains, IPv4 addresses and IPv4/IPv6 CIDR ranges to the Postfix and Postgrey whitelists — one entry at a time or in bulk from a file. Idempotent, with backups, dry-run and one-command Postfix integration (`--setup`). | Yes |
| [`refresh_cloud_senders.sh`](#%EF%B8%8F-refresh_cloud_senderssh) | Auto-generate up-to-date cloud provider IP ranges by recursively expanding their SPF records into ip4/ip6 CIDR. Pairs with `add_whitelists.sh`. | No |
| [`sync_whitelists.sh`](#-sync_whitelistssh) | Fleet auto-sync: pull your whitelist from a git repo on a daily systemd timer, apply it, and self-heal the Postfix integration after MIAB updates. | Yes |

Typical pipeline:

```bash
# 1. Find new provider ranges not already whitelisted
./refresh_cloud_senders.sh -d whitelist.txt -o new.txt

# 2. Review them
less new.txt

# 3. Apply (IPv4 entries route to Postgrey; see notes below)
sudo ./add_whitelists.sh -f new.txt
```

---

# 🧩 `add_whitelists.sh`

Safely adds trusted senders to the Postfix and Postgrey whitelist files used on Mail-in-a-Box servers.

```bash
sudo ./add_whitelists.sh example.com
```

The script automatically:

* detects whether the entry is a domain, IPv4 address or IPv4/IPv6 CIDR network;
* sends it to the appropriate whitelist file;
* skips existing entries;
* creates timestamped backups;
* rotates backups older than 30 days;
* rebuilds the Postfix map only when required;
* reloads/restarts only the affected services (`postfix reload` — active SMTP sessions are not dropped);
* writes an audit log when logging is available.

For multiple entries:

```bash
sudo ./add_whitelists.sh -f examples/whitelist.example.txt
```

Preview everything without changing the server:

```bash
sudo ./add_whitelists.sh -n -f examples/whitelist.example.txt
```

### ✨ Features

| Feature                     | Description                                                                 |
| --------------------------- | --------------------------------------------------------------------------- |
| 🎯 Automatic routing        | Domains, IPv4 addresses and IPv4/IPv6 CIDR networks are sent to the correct whitelist |
| 🔌 One-command integration  | `--setup` wires the whitelist maps into `smtpd_recipient_restrictions`; `--check` verifies the wiring |
| 🗑 Entry removal            | `--remove ENTRY` deletes an entry from all whitelist files and reloads only affected services |
| 🔍 Live verification        | `--verify ENTRY` queries the actual Postfix maps (`postmap -q`, CIDR containment) and Postgrey |
| 📋 State overview           | `--list` prints all whitelist files with counters, mtimes and integration status |
| 📄 Single or bulk input     | Process one entry or thousands from a file (in-memory dedup, ~2000 entries/s) |
| ♻️ Idempotent operation     | Existing entries are detected and skipped                                   |
| 🔍 Dry-run mode             | Preview planned changes without modifying files or restarting services      |
| 💾 Timestamped backups      | Both whitelist files are backed up before processing                        |
| 🧹 Backup rotation          | Backups older than 30 days are removed automatically                        |
| ⚡ Conditional reloads       | `postmap` and service restarts run only when their whitelist changes        |
| 🧾 Audit logging            | Operations are logged to `/var/log/add_whitelists.log` when possible        |
| 🎨 Terminal-friendly output | Colored output is enabled for interactive terminals                         |
| 🛡️ Root protection         | The script refuses to modify system files without root privileges           |

### 🧭 Entry routing

The two whitelist files serve different purposes, so entries are routed automatically.

| Entry type          | Example           |            Postfix            |       Postgrey      |
| ------------------- | ----------------- | :---------------------------: | :-----------------: |
| Domain or hostname  | `example.com`     | ✅ hash: `example.com OK`      |   ✅ `example.com`   |
| IPv4 address        | `203.0.113.10`    | ✅ hash: `203.0.113.10 OK`     |   ✅ `203.0.113.10`  |
| IPv4 CIDR network   | `198.51.100.0/24` | ✅ cidr: `198.51.100.0/24 OK`  | ✅ `198.51.100.0/24` |
| IPv6 CIDR network   | `2001:db8::/32`   | ✅ cidr: `2001:db8::/32 OK`    |  ✅ `2001:db8::/32`  |
| IPv6 address        | `2001:db8::15`    | ✅ cidr: `2001:db8::15 OK`     |  ✅ `2001:db8::15`   |

> [!NOTE]
> Postfix `hash:` maps do not support CIDR networks, so CIDR entries (IPv4 and IPv6) go into a separate `cidr:` map, which Postfix re-reads on every reload.

> [!IMPORTANT]
> The Postfix maps only take effect after `sudo add_whitelists.sh --setup` has been run once — it wires both maps into `smtpd_recipient_restrictions` (see [Postfix integration](#-postfix-integration----setup----check)). Postgrey whitelisting works without `--setup`.

#### Managed files

| Service  | File                                    | Map type |
| -------- | --------------------------------------- | -------- |
| Postfix  | `/etc/postfix/client_whitelist`         | `hash:`  |
| Postfix  | `/etc/postfix/client_whitelist_cidr`    | `cidr:`  |
| Postgrey | `/etc/postgrey/whitelist_clients.local` | —        |

### 🔌 Postfix integration — `--setup` / `--check`

Adding entries to the whitelist files is not enough by itself: Postfix must be told to consult them. `--setup` does this once, idempotently:

```bash
sudo add_whitelists.sh --setup
```

It inserts

```text
check_client_access hash:/etc/postfix/client_whitelist,
check_client_access cidr:/etc/postfix/client_whitelist_cidr
```

into `smtpd_recipient_restrictions` **right before the first `check_policy_service`** (the Postgrey policy daemon). This position matters: a whitelisted client skips greylisting but still passes RBL checks and `reject_unlisted_recipient` (it cannot send to nonexistent mailboxes). The existing restrictions chain is preserved as-is — nothing is hardcoded or replaced.

`--setup` is safe to re-run at any time: if both maps are already wired, it does nothing. If Postfix config is missing the map files, they are created (and `postmap` is run) *before* `postfix reload`, so the reload cannot fail on a missing map.

To verify the current state:

```bash
add_whitelists.sh --check    # exit 0 = wired, exit 2 = not wired
```

> [!WARNING]
> Mail-in-a-Box updates may regenerate `main.cf` and overwrite `smtpd_recipient_restrictions`. Re-run `--setup` (or at least `--check`) after every MIAB update. The script also prints a reminder whenever it detects that entries were added while the maps are not wired.

### 🚀 Quick start

#### Option 1: Run from the repository

```bash
git clone https://github.com/Anton-Babaskin/miab-whitelists.git
cd miab-whitelists

chmod +x add_whitelists.sh
sudo ./add_whitelists.sh example.com
```

#### Option 2: Install globally

```bash
git clone https://github.com/Anton-Babaskin/miab-whitelists.git
cd miab-whitelists

sudo install -m 0755 add_whitelists.sh /usr/local/bin/add_whitelists.sh
```

The command can then be used from any directory:

```bash
sudo add_whitelists.sh example.com
```

### 🛠 Usage

```bash
sudo add_whitelists.sh example.com                       # add a domain
sudo add_whitelists.sh mail.example.net                  # add a mail hostname
sudo add_whitelists.sh 203.0.113.10                      # add an IPv4 address
sudo add_whitelists.sh 198.51.100.0/24                   # add an IPv4 CIDR network
sudo add_whitelists.sh 2001:db8::/32                     # add an IPv6 CIDR network
sudo add_whitelists.sh -f examples/whitelist.example.txt # import a file
sudo add_whitelists.sh -n example.com                    # preview a single entry
sudo add_whitelists.sh -n -f examples/whitelist.example.txt  # preview a whole file
sudo add_whitelists.sh --setup                           # wire maps into Postfix (once)
add_whitelists.sh --check                                # verify Postfix integration
add_whitelists.sh --list                                 # show current whitelist state
add_whitelists.sh --verify 203.0.113.10                  # is this client whitelisted?
sudo add_whitelists.sh --remove example.com              # remove from all whitelists
add_whitelists.sh -h                                     # show help
add_whitelists.sh --help                                 # show help
add_whitelists.sh --version                              # show the script version
```

### 🎛 CLI reference

```text
Usage:
  add_whitelists.sh [-n] ENTRY
  add_whitelists.sh [-n] -f FILE
  add_whitelists.sh --setup
  add_whitelists.sh --check
  add_whitelists.sh --list
  add_whitelists.sh --remove ENTRY
  add_whitelists.sh --verify ENTRY

Options:
  -f FILE         Read entries from a file
  -n              Dry-run: show the result without applying changes
  -h / --help     Show help
  --best-effort   Apply valid entries even if the batch contains invalid ones
                  (default: validate the whole batch first, abort on any error)
  --setup      Wire whitelist maps into Postfix restrictions (idempotent,
               self-repairing: fixes wrong order and duplicates; rolls back
               automatically if postfix check/reload fails)
  --check      Show Postfix integration status, including map ORDER relative
               to the greylisting policy service (exit 0 = OK, 2 = not OK)
  --list       Show all whitelist files, counters and integration status
  --remove     Remove ENTRY from all whitelist files (exit 1 if not found)
  --verify     Check whether ENTRY is actually whitelisted (exit 0 = yes)
  --version    Show the script version

Exit codes:
  0 success, 1 usage/runtime error, 2 validation failed
```

> [!IMPORTANT]
> Dry-run mode still requires root privileges because the script validates access to the system environment before processing.

> [!NOTE]
> Entries match the **connecting SMTP client** (its rDNS hostname or IP address), not the `From:` header — that is how Postfix `check_client_access` and Postgrey client whitelists work. A `gmail.com` entry allows hosts whose rDNS ends in `gmail.com`, not "mail from gmail addresses".

### 📄 Input file format

Use one entry per line:

```text
# Domains
example.com
mail.example.net

# IPv4 addresses
203.0.113.10

# IPv4 CIDR networks
198.51.100.0/24

# IPv6 CIDR networks
2001:db8::/32
```

The parser:

* ignores empty lines;
* ignores lines beginning with `#`;
* trims surrounding whitespace;
* normalizes entries to lowercase;
* reports unsupported or malformed entries;
* skips entries that already exist.

> [!NOTE]
> Supported entry types: domains, IPv4/IPv6 addresses, IPv4/IPv6 CIDR networks. Bare IPv6 addresses go to the `cidr:` map, where they match as a full-length address.

### 🔄 What happens during a run

```text
Input
  │
  ▼
Normalize and validate
  │
  ▼
Detect entry type
  │
  ├── Domain ────────► Postfix hash + Postgrey
  ├── IPv4 ──────────► Postfix hash + Postgrey
  └── CIDR v4/v6 ────► Postfix cidr + Postgrey
  │
  ▼
Skip existing entries
  │
  ▼
Apply only actual changes
  │
  ├── Postfix hash changed ─► postmap + reload Postfix
  ├── Postfix cidr changed ─► reload Postfix
  └── Postgrey changed ─────► restart Postgrey
```

On each run, the script:

1. verifies root privileges;
2. prepares the audit log when possible;
3. creates missing whitelist directories and files;
4. prepares timestamped backups;
5. removes backups older than 30 days;
6. processes and routes every entry;
7. skips duplicate records;
8. rebuilds the Postfix hash map only when Postfix changes;
9. restarts only the affected service;
10. prints counters and a summary of added entries.

### 💾 Backups and recovery

Backups use the following format:

```text
/etc/postfix/client_whitelist.bak_YYYY-MM-DD_HHMMSS
/etc/postfix/client_whitelist_cidr.bak_YYYY-MM-DD_HHMMSS
/etc/postgrey/whitelist_clients.local.bak_YYYY-MM-DD_HHMMSS
```

Backups older than 30 days are removed automatically.

#### List available backups

```bash
ls -lah /etc/postfix/client_whitelist.bak_*
ls -lah /etc/postgrey/whitelist_clients.local.bak_*
```

#### Restore Postfix

```bash
sudo cp \
  /etc/postfix/client_whitelist.bak_YYYY-MM-DD_HHMMSS \
  /etc/postfix/client_whitelist

sudo postmap /etc/postfix/client_whitelist
sudo systemctl restart postfix
```

#### Restore Postgrey

```bash
sudo cp \
  /etc/postgrey/whitelist_clients.local.bak_YYYY-MM-DD_HHMMSS \
  /etc/postgrey/whitelist_clients.local

sudo systemctl restart postgrey
```

Always replace `YYYY-MM-DD_HHMMSS` with the timestamp of the backup being restored.

### 🧾 Logging

When the log file can be prepared, operations are written to:

```text
/var/log/add_whitelists.log
```

Example:

```bash
sudo tail -f /var/log/add_whitelists.log
```

The log records script start/completion, the invoking user, added entries, duplicates, invalid input, service restarts and final counters. Logging is best-effort — failure to prepare the log file does not stop whitelist processing.

### 🛡️ Security notice

> [!WARNING]
> Whitelisting may allow selected senders to bypass greylisting or other mail restrictions configured on the server.

Whitelisting a cloud provider's SPF ranges (Microsoft 365, Google, SES…) trusts the provider's **shared pool** — every tenant of that provider, not just your partner. On this toolkit that means those clients skip greylisting only (RBL checks and recipient validation still apply), so the risk is moderate — but keep it in mind.

Only add entries that you control or have independently verified. Before applying a large list:

```bash
sudo add_whitelists.sh -n -f whitelist.txt
```

Recommended practices:

* review every domain, IP address and network;
* keep corporate whitelist data in a private repository;
* do not commit production mail infrastructure details publicly;
* use the smallest possible network range;
* review `/var/log/add_whitelists.log`;
* periodically audit both whitelist files;
* verify backups before deleting old entries.

This repository intentionally contains no production corporate whitelist.

### 🛟 Troubleshooting

| Symptom | Resolution |
| ------- | ---------- |
| `ERROR: Run as root or with sudo` | Run with `sudo`. |
| `File not found: ...` | Check the path with `ls -lah`, then pass an absolute path to `-f`. |
| An entry was not added | It probably already exists — `grep -F "example.com" /etc/postfix/client_whitelist`. Also check the log. |
| Whitelisted client is still greylisted | The maps are probably not wired into Postfix — run `add_whitelists.sh --check`, then `sudo add_whitelists.sh --setup`. |
| Integration lost after a MIAB update | MIAB regenerated `main.cf`. Re-run `sudo add_whitelists.sh --setup`. |
| Postfix changes not active | `sudo postmap /etc/postfix/client_whitelist && sudo postfix reload`. |

To debug a specific sender, ask the actual Postfix maps instead of grepping files:

```bash
add_whitelists.sh --verify 203.0.113.10
```

Validate the scripts before running them:

```bash
bash -n add_whitelists.sh
shellcheck add_whitelists.sh
sudo bash tests/run_tests.sh    # sandboxed functional test suite (no system changes)
```

---

# ☁️ `refresh_cloud_senders.sh`

Keeps cloud provider IP ranges current by reading them straight from each provider's SPF record.

### Why

A provider's SPF record is **their own source of truth** — they update it whenever their sending infrastructure changes. Maintaining hundreds of individual IPs by hand rots quickly; the SPF record never does. Run this tool periodically and you always get the provider's current ranges.

`refresh_cloud_senders.sh` recursively expands each provider's SPF record (following `include:` and `redirect=`, with a depth limit and a loop guard), collects every `ip4:` and `ip6:` range, deduplicates them, and writes a ready-to-use list. It only reads DNS and writes a file — **it does not require root** and never touches your mail server directly.

### Dependency

Requires `dig`:

```bash
sudo apt install dnsutils      # Debian / Ubuntu
sudo yum install bind-utils    # RHEL / CentOS / Fedora
```

### Usage

```text
Usage:
  refresh_cloud_senders.sh [-o OUTPUT] [-d EXISTING] [--apply] [-h]

Options:
  -o OUTPUT    Output file (default: cloud_senders.generated.txt)
  -d EXISTING  Diff mode: compare against an existing whitelist and print
               ONLY the new ranges (those not already present).
  --apply      Immediately feed the result to add_whitelists.sh -f
               (requires root; in diff mode only the new ranges are applied)
  -h           Show help
  --version    Show the script version
```

```bash
./refresh_cloud_senders.sh                          # full list -> cloud_senders.generated.txt
./refresh_cloud_senders.sh -o ranges.txt            # custom output path
./refresh_cloud_senders.sh -d whitelist.txt         # show only ranges new to your whitelist
./refresh_cloud_senders.sh -d whitelist.txt -o new.txt
sudo ./refresh_cloud_senders.sh -d /etc/postfix/client_whitelist_cidr --apply   # one-step update
./refresh_cloud_senders.sh --version
```

The generated file is annotated and grouped into IPv4 and IPv6 sections, with a header recording the date, mode and source providers.

### Typical workflow

```bash
# 1. Compute what's new relative to your current whitelist
./refresh_cloud_senders.sh -d whitelist.txt -o new.txt

# 2. Review before applying anything
less new.txt

# 3. Apply with the companion tool
sudo ./add_whitelists.sh -f new.txt
```

> [!IMPORTANT]
> `refresh_cloud_senders.sh` emits both IPv4 and IPv6 ranges, and since v2.1 `add_whitelists.sh` accepts both: every CIDR range (v4 and v6) is routed to the Postfix `cidr:` map and to Postgrey. Feed the generated file straight to `add_whitelists.sh -f` — nothing is skipped.

### Default providers

The `PROVIDERS` array at the top of the script controls which SPF records are expanded. Defaults:

| Provider | SPF domain |
| -------- | ---------- |
| Microsoft 365 / Exchange Online | `spf.protection.outlook.com` |
| Google Workspace | `_spf.google.com` |
| Amazon SES | `amazonses.com` |
| SendGrid | `sendgrid.net` |
| Mailgun | `mailgun.org` |
| Mimecast | `_netblocks.mimecast.com` |

To track another provider, add its SPF domain to the array:

```bash
PROVIDERS=(
  "spf.protection.outlook.com"
  "_spf.google.com"
  # ...
  "spf.example-provider.com"   # your additional provider
)
```

### Keeping it current

Provider ranges change occasionally, not constantly. A quarterly audit is usually enough:

```cron
# Run on the 1st of every quarter and email the diff for review (no auto-apply)
0 6 1 1,4,7,10 * /usr/local/bin/refresh_cloud_senders.sh -d /etc/postfix/client_whitelist -o /tmp/cloud_new.txt
```

Review the diff and apply it deliberately with `add_whitelists.sh` — avoid blindly auto-applying provider ranges to your mail filters.

---

# 🔁 `sync_whitelists.sh`

Fleet auto-sync: edit the whitelist in one (private) git repository — every server converges on its own, on a daily systemd timer.

Each sync cycle:

1. `git pull --ff-only` in the whitelist repository;
2. applies the list via `add_whitelists.sh -f` (idempotent and fast, so it always applies — a missed run costs nothing);
3. verifies the Postfix integration with `--check` and, if a Mail-in-a-Box update unwired the maps, **automatically re-runs `--setup`**;
4. reports failures to syslog and, optionally, by e-mail.

### Setup (once per server)

```bash
# 1. Clone your private whitelist repo somewhere stable
sudo git clone git@github.example.com:you/corporate-whitelist.git /opt/corporate-whitelist

# 2. Install the timer and sample config
sudo ./sync_whitelists.sh --install

# 3. Point the config at the repo
sudo nano /etc/miab-whitelists/sync.conf   # set REPO_DIR="/opt/corporate-whitelist"

# 4. Test a cycle manually
sudo sync_whitelists.sh
```

`--install` writes `/etc/miab-whitelists/sync.conf` (mode 600), copies the script to `/usr/local/bin`, and enables `miab-whitelist-sync.timer` — daily at 06:30 with a ±30 min randomized delay (so a fleet doesn't hammer the git server simultaneously) and `Persistent=true` (a server that was down catches up on boot).

### Config reference

| Variable | Default | Meaning |
| -------- | ------- | ------- |
| `REPO_DIR` | — (required) | Git repository containing the whitelist |
| `WHITELIST_FILE` | `whitelist.txt` | Entries file inside the repo |
| `ADD_SCRIPT` | auto-detect | Path to `add_whitelists.sh` |
| `AUTO_SETUP` | `1` | Re-run `--setup` automatically when maps get unwired |
| `ALERT_EMAIL` | empty | E-mail for failure alerts (syslog is always used) |

### Monitoring

```bash
systemctl list-timers miab-whitelist-sync.timer   # next/last run
journalctl -u miab-whitelist-sync.service -n 50   # sync logs
```

---

## 📦 Repository structure

```text
miab-whitelists/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml
│   │   ├── feature_request.yml
│   │   └── config.yml
│   ├── workflows/
│   │   └── shellcheck.yml
│   └── PULL_REQUEST_TEMPLATE.md
├── examples/
│   └── whitelist.example.txt
├── tests/
│   ├── run_tests.sh
│   └── run_sync_tests.sh
├── add_whitelists.sh
├── refresh_cloud_senders.sh
├── sync_whitelists.sh
├── CHANGELOG.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── LICENSE
├── README.md
├── README_RU.md
└── SECURITY.md
```

---

## 📋 Requirements

| Tool | Requirements |
| ---- | ------------ |
| `add_whitelists.sh` | Bash, Debian/Ubuntu, Postfix, Postgrey, `postmap`, `systemctl`, root/`sudo` |
| `refresh_cloud_senders.sh` | Bash, `dig` (dnsutils / bind-utils) — no root required |

The project is designed for Mail-in-a-Box servers, but `add_whitelists.sh` also works with compatible Postfix/Postgrey installations using the same whitelist paths.

> [!CAUTION]
> Always verify file paths and mail server configuration before using the scripts outside Mail-in-a-Box.

---

## 🔗 Related repositories

| Repository                                                                                   | Purpose                                      |
| -------------------------------------------------------------------------------------------- | -------------------------------------------- |
| [`miab-whitelists`](https://github.com/Anton-Babaskin/miab-whitelists)                       | Reusable whitelist processing engine         |
| [`mass-domain-miab-whitelist`](https://github.com/Anton-Babaskin/mass-domain-miab-whitelist) | Predefined bulk whitelist importer           |
| [`miab-whitelist-installer`](https://github.com/Anton-Babaskin/miab-whitelist-installer)     | Automated installer for the complete toolkit |

---

## 🤝 Contributing

Contributions are welcome. Before opening a pull request:

```bash
bash -n add_whitelists.sh && shellcheck add_whitelists.sh
bash -n refresh_cloud_senders.sh && shellcheck refresh_cloud_senders.sh
```

Please read:

* [CONTRIBUTING.md](./CONTRIBUTING.md)
* [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)
* [SECURITY.md](./SECURITY.md)

Never include real corporate whitelist data, authentication tokens, mail logs or private infrastructure details in issues or pull requests.

---

## 📜 Changelog

See [CHANGELOG.md](./CHANGELOG.md) for release history and notable changes.

---

## ⚖️ License

Distributed under the [MIT License](./LICENSE).

Copyright © 2025-2026 Anton Babaskin.

---

## ℹ️ Disclaimer

This is an independent community project and is not affiliated with or officially supported by the Mail-in-a-Box project.

Always test changes in dry-run mode and review your mail server configuration before applying whitelist entries to a production system.
