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
`add_whitelists.sh` is a universal script to add domains and IP addresses to Postfix and Postgrey whitelists. It supports **single-entry** and **bulk-from-file** modes. The script **auto-creates** missing files/directories, makes **timestamped backups** before changes, **ignores** blank lines and `#` comments, **deduplicates** entries, and **restarts** Postfix/Postgrey only when changes are made. At the end it prints how many entries were added and a list of what was actually added.

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
- **Backs up** whitelist files with timestamps before modifying them.
- **Skips duplicates** (doesn’t add the same entry twice).
- **Rebuilds** Postfix hash map (`postmap`) and **restarts** Postfix/Postgrey only when changes occurred.
- **Shows a summary**: totals added to Postfix/Postgrey and a list of actually added entries.


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
2. Reads each line:

   * If missing in Postfix: appends `ENTRY OK`.
   * If a domain (not IP/CIDR) and missing in Postgrey: appends `ENTRY`.
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

## 🤝 Contributing

Pull requests and issues welcome!
Please follow the standard fork → branch → PR workflow.

---

## 📜 License

MIT © Anton Babaskin. See [LICENSE](LICENSE) for details.
![ShellCheck](https://github.com/Anton-Babaskin/miab-whitelists/actions/workflows/shellcheck.yml/badge.svg)
