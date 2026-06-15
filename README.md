# MIAB Whitelists

[![ShellCheck](https://github.com/Anton-Babaskin/miab-whitelists/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/Anton-Babaskin/miab-whitelists/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Bash script to add domains, IPs and CIDR ranges to Postfix and Postgrey whitelists on Mail-in-a-Box servers. Supports single-entry and bulk-from-file modes.

---

## 📖 Table of Contents

- [What goes where](#what-goes-where)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Backup & Safety](#backup--safety)
- [Testing checklist](#testing-checklist)
- [Examples](#examples)
- [Contributing](#contributing)
- [License](#license)

---

## What goes where

Two whitelist files serve different purposes — entries are routed automatically:

| Entry type | Postfix `client_whitelist` | Postgrey `whitelist_clients.local` | Notes |
|------------|:--------------------------:|:----------------------------------:|-------|
| Domain | ✅ `entry OK` | ✅ `entry` | Added to both |
| IPv4 | ✅ `entry OK` | ✅ `entry` | Added to both |
| CIDR | ❌ skipped | ✅ `entry` | Postfix hash maps don't support CIDR |

- **Postfix** (`/etc/postfix/client_whitelist`) — hash table, requires `postmap` after changes. Bypasses smtpd restrictions (RBL, rate limits, reject rules).
- **Postgrey** (`/etc/postgrey/whitelist_clients.local`) — plain text, no `postmap` needed. Bypasses greylisting delay.

---

## ⚙️ Prerequisites

- **OS:** Debian / Ubuntu
- **Services:** Postfix & Postgrey installed and running
- **Permissions:** root or `sudo`

---

## 🚀 Installation

```bash
git clone https://github.com/Anton-Babaskin/miab-whitelists.git
cd miab-whitelists
chmod +x add_whitelists.sh
```

Optionally install globally so you can call it from anywhere:

```bash
sudo cp add_whitelists.sh /usr/local/bin/add_whitelists.sh
```

---

## ▶️ Usage

### Single entry

```bash
sudo ./add_whitelists.sh example.com
sudo ./add_whitelists.sh 203.0.113.7
sudo ./add_whitelists.sh 198.51.100.0/24
```

### Bulk from file

Create a file with one entry per line (blank lines and `#` comments are ignored):

```text
# Banks
isbank.com.tr
mail.isbank.com.tr

# Known mail IPs
203.0.113.10
198.51.100.0/24
```

Apply it:

```bash
sudo ./add_whitelists.sh -f whitelist.txt
```

### Dry-run (no changes applied)

```bash
sudo ./add_whitelists.sh -n -f whitelist.txt
sudo ./add_whitelists.sh -n example.com
```

### Other flags

```bash
add_whitelists.sh --version   # print script version
add_whitelists.sh -h          # show help
```

### What the script does on each run

1. Creates `/etc/postfix/client_whitelist` and `/etc/postgrey/whitelist_clients.local` if missing.
2. Creates timestamped backups of both files.
3. Rotates backups older than 30 days automatically.
4. Reads each entry, skips duplicates, routes by type (see table above).
5. Runs `postmap` and restarts Postfix/Postgrey **only if changes were made**.
6. Prints a summary: entries added to each file + full list of what was added.

---

## 🛡️ Backup & Safety

Before any changes the script creates timestamped backups:

```
/etc/postfix/client_whitelist.bak_YYYY-MM-DD_HHMMSS
/etc/postgrey/whitelist_clients.local.bak_YYYY-MM-DD_HHMMSS
```

Backups older than 30 days are removed automatically.

**To restore from backup:**

```bash
sudo cp /etc/postfix/client_whitelist.bak_YYYY-MM-DD_HHMMSS /etc/postfix/client_whitelist
sudo cp /etc/postgrey/whitelist_clients.local.bak_YYYY-MM-DD_HHMMSS /etc/postgrey/whitelist_clients.local
sudo postmap /etc/postfix/client_whitelist
sudo systemctl restart postfix postgrey
```

---

## ✅ Testing checklist

After modifying the script, verify routing on a real MIAB server:

```bash
# Domain → both files
sudo ./add_whitelists.sh testdomain.com
grep testdomain.com /etc/postfix/client_whitelist          # → "testdomain.com OK"
grep testdomain.com /etc/postgrey/whitelist_clients.local  # → "testdomain.com"

# IP → both files
sudo ./add_whitelists.sh 1.2.3.4
grep 1.2.3.4 /etc/postfix/client_whitelist                 # → "1.2.3.4 OK"
grep 1.2.3.4 /etc/postgrey/whitelist_clients.local         # → "1.2.3.4"

# CIDR → Postgrey only
sudo ./add_whitelists.sh 198.51.100.0/24
grep 198.51.100.0/24 /etc/postfix/client_whitelist         # → nothing (correct)
grep 198.51.100.0/24 /etc/postgrey/whitelist_clients.local # → "198.51.100.0/24"
```

Run ShellCheck before committing:

```bash
shellcheck add_whitelists.sh
```

---

## 💡 Examples

**Quick one-liner:**

```bash
sudo ./add_whitelists.sh partner.com
```

**Apply a prepared list:**

```bash
sudo ./add_whitelists.sh -f /opt/mywhitelists/whitelist.txt
```

**Preview changes without applying (dry-run):**

```bash
sudo ./add_whitelists.sh -n -f whitelist.txt
```

**Keep your private whitelist data separate:**

This script contains no domain or IP data — it is safe to publish publicly. Store your actual whitelist in a private repository and pass it via `-f`:

```bash
sudo ./add_whitelists.sh -f /path/to/private/whitelist.txt
```

**Automate via cron:**

```bash
# /etc/cron.daily/miab-whitelist
#!/bin/bash
cd /opt/miab-whitelists
git pull --ff-only
add_whitelists.sh -f /opt/private-whitelist/whitelist.txt
```

---

## 🤝 Contributing

Pull requests and issues welcome. Please follow the standard fork → branch → PR workflow.

---

## 📜 License

MIT © Anton Babaskin. See [LICENSE](LICENSE) for details.
