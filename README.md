<p align="right">
  🇬🇧 English · <a href="./README_RU.md">🇷🇺 Русский</a>
</p>

<div align="center">

# 📬 MIAB Whitelists

### Safe and idempotent Postfix & Postgrey whitelist management for Mail-in-a-Box

<p>
  Add trusted domains, IPv4 addresses and CIDR networks from a single command or a prepared file.
</p>

<p>
  <a href="https://github.com/Anton-Babaskin/miab-whitelists/actions/workflows/shellcheck.yml">
    <img alt="ShellCheck" src="https://img.shields.io/github/actions/workflow/status/Anton-Babaskin/miab-whitelists/shellcheck.yml?branch=main&style=for-the-badge&logo=githubactions&logoColor=white&label=ShellCheck">
  </a>
  <img alt="Version" src="https://img.shields.io/badge/version-2.0-1f6feb?style=for-the-badge">
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

## ⚡ TL;DR

`add_whitelists.sh` safely adds trusted senders to the Postfix and Postgrey whitelist files used on Mail-in-a-Box servers.

```bash
sudo ./add_whitelists.sh example.com
```

The script automatically:

* detects whether the entry is a domain, IPv4 address or IPv4 CIDR network;
* sends it to the appropriate whitelist file;
* skips existing entries;
* creates timestamped backups;
* rotates backups older than 30 days;
* rebuilds the Postfix map only when required;
* restarts only the affected services;
* writes an audit log when logging is available.

For multiple entries:

```bash
sudo ./add_whitelists.sh -f examples/whitelist.example.txt
```

Preview everything without changing the server:

```bash
sudo ./add_whitelists.sh -n -f examples/whitelist.example.txt
```

---

## ✨ Features

| Feature                     | Description                                                                 |
| --------------------------- | --------------------------------------------------------------------------- |
| 🎯 Automatic routing        | Domains, IPv4 addresses and CIDR networks are sent to the correct whitelist |
| 📄 Single or bulk input     | Process one entry or load hundreds of entries from a file                   |
| ♻️ Idempotent operation     | Existing entries are detected and skipped                                   |
| 🔍 Dry-run mode             | Preview planned changes without modifying files or restarting services      |
| 💾 Timestamped backups      | Both whitelist files are backed up before processing                        |
| 🧹 Backup rotation          | Backups older than 30 days are removed automatically                        |
| ⚡ Conditional reloads       | `postmap` and service restarts run only when their whitelist changes        |
| 🧾 Audit logging            | Operations are logged to `/var/log/add_whitelists.log` when possible        |
| 🎨 Terminal-friendly output | Colored output is enabled for interactive terminals                         |
| 🛡️ Root protection         | The script refuses to modify system files without root privileges           |

---

## 🧭 Entry routing

The two whitelist files serve different purposes, so entries are routed automatically.

| Entry type         | Example           |       Postfix       |       Postgrey      |
| ------------------ | ----------------- | :-----------------: | :-----------------: |
| Domain or hostname | `example.com`     |  ✅ `example.com OK` |   ✅ `example.com`   |
| IPv4 address       | `203.0.113.10`    | ✅ `203.0.113.10 OK` |   ✅ `203.0.113.10`  |
| IPv4 CIDR network  | `198.51.100.0/24` |          ❌          | ✅ `198.51.100.0/24` |

> [!NOTE]
> Postfix `hash:` maps do not support CIDR networks. CIDR entries are therefore added only to Postgrey.

### Managed files

| Service  | File                                    |
| -------- | --------------------------------------- |
| Postfix  | `/etc/postfix/client_whitelist`         |
| Postgrey | `/etc/postgrey/whitelist_clients.local` |

---

## 🚀 Quick start

### Option 1: Run from the repository

```bash
git clone https://github.com/Anton-Babaskin/miab-whitelists.git
cd miab-whitelists

chmod +x add_whitelists.sh
sudo ./add_whitelists.sh example.com
```

### Option 2: Install globally

```bash
git clone https://github.com/Anton-Babaskin/miab-whitelists.git
cd miab-whitelists

sudo install -m 0755 add_whitelists.sh /usr/local/bin/add_whitelists.sh
```

The command can then be used from any directory:

```bash
sudo add_whitelists.sh example.com
```

### Complete toolkit installation

To install this tool together with the predefined bulk whitelist importer, use:

[`miab-whitelist-installer`](https://github.com/Anton-Babaskin/miab-whitelist-installer)

---

## 🛠 Usage

### Add a domain

```bash
sudo add_whitelists.sh example.com
```

### Add a mail hostname

```bash
sudo add_whitelists.sh mail.example.net
```

### Add an IPv4 address

```bash
sudo add_whitelists.sh 203.0.113.10
```

### Add an IPv4 CIDR network

```bash
sudo add_whitelists.sh 198.51.100.0/24
```

### Import a file

```bash
sudo add_whitelists.sh -f examples/whitelist.example.txt
```

### Preview a single entry

```bash
sudo add_whitelists.sh -n example.com
```

### Preview a complete file

```bash
sudo add_whitelists.sh -n -f examples/whitelist.example.txt
```

### Display help

```bash
add_whitelists.sh -h
```

or:

```bash
add_whitelists.sh --help
```

### Display the script version

```bash
add_whitelists.sh --version
```

---

## 🎛 CLI reference

```text
Usage:
  add_whitelists.sh [-n] ENTRY
  add_whitelists.sh [-n] -f FILE

Options:
  -f FILE      Read entries from a file
  -n           Dry-run: show the result without applying changes
  -h           Show help
  --help       Show help
  --version    Show the script version
```

> [!IMPORTANT]
> Dry-run mode still requires root privileges because the script validates access to the system environment before processing.

---

## 📄 Input file format

Use one entry per line:

```text
# Domains
example.com
mail.example.net

# IPv4 addresses
203.0.113.10

# IPv4 CIDR networks
198.51.100.0/24
```

The parser:

* ignores empty lines;
* ignores lines beginning with `#`;
* trims surrounding whitespace;
* normalizes entries to lowercase;
* reports unsupported or malformed entries;
* skips entries that already exist.

> [!NOTE]
> The current version supports domains, IPv4 addresses and IPv4 CIDR networks. IPv6 is not currently supported.

---

## 🔄 What happens during a run

```text
Input
  │
  ▼
Normalize and validate
  │
  ▼
Detect entry type
  │
  ├── Domain ──────► Postfix + Postgrey
  ├── IPv4 ────────► Postfix + Postgrey
  └── IPv4 CIDR ───► Postgrey only
  │
  ▼
Skip existing entries
  │
  ▼
Apply only actual changes
  │
  ├── Postfix changed ─► postmap + restart Postfix
  └── Postgrey changed ─► restart Postgrey
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

---

## 💾 Backups and recovery

Backups use the following format:

```text
/etc/postfix/client_whitelist.bak_YYYY-MM-DD_HHMMSS
/etc/postgrey/whitelist_clients.local.bak_YYYY-MM-DD_HHMMSS
```

Backups older than 30 days are removed automatically.

### List available backups

```bash
ls -lah /etc/postfix/client_whitelist.bak_*
ls -lah /etc/postgrey/whitelist_clients.local.bak_*
```

### Restore Postfix

```bash
sudo cp \
  /etc/postfix/client_whitelist.bak_YYYY-MM-DD_HHMMSS \
  /etc/postfix/client_whitelist

sudo postmap /etc/postfix/client_whitelist
sudo systemctl restart postfix
```

### Restore Postgrey

```bash
sudo cp \
  /etc/postgrey/whitelist_clients.local.bak_YYYY-MM-DD_HHMMSS \
  /etc/postgrey/whitelist_clients.local

sudo systemctl restart postgrey
```

Always replace `YYYY-MM-DD_HHMMSS` with the timestamp of the backup being restored.

---

## 🧾 Logging

When the log file can be prepared, operations are written to:

```text
/var/log/add_whitelists.log
```

Example:

```bash
sudo tail -f /var/log/add_whitelists.log
```

The log records:

* script start and completion;
* invoking user;
* added domains, IP addresses and CIDR networks;
* duplicate entries;
* invalid input;
* service restarts;
* final counters.

Logging is best-effort. Failure to prepare the log file does not stop whitelist processing.

---

## 🛡️ Security notice

> [!WARNING]
> Whitelisting may allow selected senders to bypass greylisting or other mail restrictions configured on the server.

Only add entries that you control or have independently verified.

Before applying a large list:

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
├── add_whitelists.sh
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

* Bash;
* Debian or Ubuntu;
* Postfix;
* Postgrey;
* `postmap`;
* `systemctl`;
* root or `sudo` privileges.

The project is designed for Mail-in-a-Box servers, but it can also work with compatible Postfix/Postgrey installations using the same whitelist paths.

> [!CAUTION]
> Always verify file paths and mail server configuration before using the script outside Mail-in-a-Box.

---

## 🛟 Troubleshooting

### `ERROR: Run as root or with sudo`

Use:

```bash
sudo add_whitelists.sh example.com
```

### `File not found`

Verify the path:

```bash
ls -lah /path/to/whitelist.txt
```

Then use an absolute path:

```bash
sudo add_whitelists.sh -f /path/to/whitelist.txt
```

### An entry was not added

Check whether it already exists:

```bash
grep -F "example.com" /etc/postfix/client_whitelist
grep -F "example.com" /etc/postgrey/whitelist_clients.local
```

Also review the log:

```bash
sudo tail -n 100 /var/log/add_whitelists.log
```

### CIDR is missing from Postfix

This is expected. Postfix `hash:` maps do not support CIDR networks, so CIDR entries are routed only to Postgrey.

### Postfix changes are not active

Rebuild the map and restart Postfix:

```bash
sudo postmap /etc/postfix/client_whitelist
sudo systemctl restart postfix
```

### Check the script before running it

```bash
bash -n add_whitelists.sh
shellcheck add_whitelists.sh
```

---

## 🔗 Related repositories

| Repository                                                                                   | Purpose                                      |
| -------------------------------------------------------------------------------------------- | -------------------------------------------- |
| [`miab-whitelists`](https://github.com/Anton-Babaskin/miab-whitelists)                       | Reusable whitelist processing engine         |
| [`mass-domain-miab-whitelist`](https://github.com/Anton-Babaskin/mass-domain-miab-whitelist) | Predefined bulk whitelist importer           |
| [`miab-whitelist-installer`](https://github.com/Anton-Babaskin/miab-whitelist-installer)     | Automated installer for the complete toolkit |

---

## 🤝 Contributing

Contributions are welcome.

Before opening a pull request:

```bash
bash -n add_whitelists.sh
shellcheck add_whitelists.sh
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
