# MIAB Whitelists

![ShellCheck](https://github.com/Anton-Babaskin/miab-whitelists/actions/workflows/shellcheck.yml/badge.svg)


[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Automate adding domains and IP addresses to Postfix and Postgrey whitelists on Mail-in-a-Box servers with a single, universal Bash script.

---

## 📖 Table of Contents

* [Overview](#overview)
* [Prerequisites](#prerequisites)
* [Installation](#installation)
* [Configuration](#configuration)
* [Usage](#usage)
* [Backup & Safety](#backup--safety)
* [Examples](#examples)
* [Contributing](#contributing)
* [License](#license)

---


## Overview
`add_whitelists.sh` is a universal script to add domains, IP addresses and CIDR ranges to Postfix and Postgrey whitelists. It supports **single-entry** and **bulk-from-file** modes. The script **auto-creates** missing files/directories, makes **timestamped backups** before changes (rotating backups older than 30 days), **ignores** blank lines and `#` comments, **deduplicates** entries, and **restarts** Postfix/Postgrey only when changes are made. At the end it prints how many entries were added to each file and a list of what was actually added.

### What goes where

The two whitelist files serve different purposes, so each entry type is routed accordingly:

| Entry type | Postfix (`client_whitelist`) | Postgrey (`whitelist_clients.local`) | Notes |
|------------|:---------------------------:|:------------------------------------:|-------|
| Domain     | ✅ `entry OK`               | ✅ `entry`                            | Added to both |
| IPv4       | ✅ `entry OK`               | ✅ `entry`                            | Added to both |
| CIDR       | ❌ (skipped)                | ✅ `entry`                            | Postfix hash maps don't support CIDR |

- **Postfix** (`/etc/postfix/client_whitelist`) — hash table (`entry OK`), requires `postmap` after changes. Bypasses Postfix smtpd restrictions (RBL, rate limits, reject rules). Supports domains and IPs, **not** CIDR.
- **Postgrey** (`/etc/postgrey/whitelist_clients.local`) — plain text (`entry`), no `postmap` needed. Bypasses greylisting delay. Supports domains, IPs and CIDR.

### Usage

**Single entry**

    sudo ./add_whitelists.sh example.com
    # or
    sudo ./add_whitelists.sh 203.0.113.7


### Bulk from a file

1. Create a file `whitelists.txt` with one domain or IP per line (blank lines and `#` comments are ignored):

    example.com  
    mail.example.org  
    192.168.1.10

2. **Run:**

    ```bash
    sudo ./add_whitelists.sh -f whitelists.txt
    ```


### What the script does
- **Auto-creates** required files if missing:
  - `/etc/postfix/client_whitelist`
  - `/etc/postgrey/whitelist_clients.local`
- **Routes by entry type** (see table above): domains and IPs go to both files; CIDR goes to Postgrey only.
- **Backs up** whitelist files with timestamps before modifying them, and **rotates** backups older than 30 days.
- **Skips duplicates** (doesn’t add the same entry twice).
- **Rebuilds** Postfix hash map (`postmap`) and **restarts** Postfix/Postgrey only when changes occurred.
- **Shows a summary**: separate counters (Postfix added, Postgrey added, errors) and a list of actually added entries.
- **`--version`** prints the script version.


Keeping your whitelist entries in a separate file lets you safely publish this script on GitHub without exposing private data.

---

## ⚙️ Prerequisites

* **OS:** Debian / Ubuntu
* **Services:** Postfix & Postgrey installed
* **Permissions:** Root or `sudo` to modify `/etc/postfix` and `/etc/postgrey`

---

## 🚀 Installation

1. **Clone the repo**

   ```bash
   git clone https://github.com/Anton-Babaskin/miab-whitelists.git
   cd miab-whitelists
   ```
2. **Create your whitelist file**

   ```text
   # whitelist.txt
   example.com
   198.51.100.0/24
   mail.partner-domain.org
   ```
3. **Make the script executable**

   ```bash
   chmod +x add_whitelists.sh
   ```

---

## 🛠️ Configuration

Customize paths in the script header if needed:

```bash
# add_whitelists.sh
POSTFIX_FILE="/etc/postfix/client_whitelist"
POSTGREY_FILE="/etc/postgrey/whitelist_clients.local"
```

---

## ▶️ Usage

Run the script with your whitelist file:

```bash
sudo ./add_whitelists.sh -f whitelist.txt
```
Quick add: add any single domain or IP with one command, no file needed:
```bash
sudo ./add_whitelists.sh YOURDOMAIN.com
```
**What happens under the hood:**

1. Backups:

   ```bash
   /etc/postfix/client_whitelist.bak_YYYY-MM-DD_HH:MM:SS
   /etc/postgrey/whitelist_clients.local.bak_YYYY-MM-DD_HH:MM:SS
   ```
2. Reads each line and routes by type:

   * Domain or IP, if missing in Postfix: appends `ENTRY OK`.
   * Domain, IP **or CIDR**, if missing in Postgrey: appends `ENTRY`.
   * CIDR is **never** added to Postfix (hash maps don't support CIDR).
3. Applies changes:

   ```bash
   postmap "$POSTFIX_FILE"
   systemctl restart postfix
   systemctl restart postgrey
   ```

---

## 🛡️ Backup & Safety

Before making changes, the script creates timestamped backups. To restore from backup:

```bash
sudo cp /etc/postfix/client_whitelist.bak_YYYY-MM-DD_HH:MM:SS /etc/postfix/client_whitelist
sudo cp /etc/postgrey/whitelist_clients.local.bak_YYYY-MM-DD_HH:MM:SS /etc/postgrey/whitelist_clients.local
sudo postmap /etc/postfix/client_whitelist
sudo systemctl restart postfix postgrey
```

**Backup rotation:**
To automatically delete backups older than 30 days, add this line at the end of your script or run it separately:

```bash
find /etc/postfix -name "client_whitelist.bak_*" -mtime +30 -delete
```

---

## 💡 Examples

**One-liner:**

```bash
echo -e "partner.com
198.51.100.0/24" > whitelist.txt
sudo ./add_whitelists.sh whitelist.txt
```

**Automate via cron:**

```cron
# /etc/cron.daily/miab-whitelist
#!/bin/bash
cd /opt/miab-whitelists
git pull --ff-only
/opt/miab-whitelists/add_whitelists.sh /opt/miab-whitelists/whitelist.txt
```

---

## ✅ Testing checklist

After changing the script, verify routing manually on a MIAB server:

```bash
sudo ./add_whitelists.sh testdomain.com
grep testdomain.com /etc/postfix/client_whitelist            # → "testdomain.com OK"
grep testdomain.com /etc/postgrey/whitelist_clients.local    # → "testdomain.com"

sudo ./add_whitelists.sh 1.2.3.4
grep 1.2.3.4 /etc/postfix/client_whitelist                   # → "1.2.3.4 OK"
grep 1.2.3.4 /etc/postgrey/whitelist_clients.local           # → "1.2.3.4"

sudo ./add_whitelists.sh 198.51.100.0/24
grep 198.51.100.0/24 /etc/postfix/client_whitelist           # → NOT present
grep 198.51.100.0/24 /etc/postgrey/whitelist_clients.local   # → present
```

Also run ShellCheck before committing:

```bash
shellcheck add_whitelists.sh
```

---

## 🤝 Contributing

Pull requests and issues welcome!
Please follow the standard fork → branch → PR workflow.

---

## 📜 License

MIT © Anton Babaskin. See [LICENSE](LICENSE) for details.
![ShellCheck](https://github.com/Anton-Babaskin/miab-whitelists/actions/workflows/shellcheck.yml/badge.svg)
