# MIAB Whitelists

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

## 📝 Overview

`add_whitelists.sh` reads a simple text file (`whitelist.txt`) with one domain or IP (CIDR supported) per line, then:

1. Creates timestamped backups of your existing whitelist files.
2. Adds entries to Postfix (`/etc/postfix/client_whitelist`) suffixed with `OK`.
3. Adds domain entries to Postgrey (`/etc/postgrey/whitelist_clients.local`).
4. Rebuilds the Postfix hash database and restarts both services.

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
sudo ./add_whitelists.sh whitelist.txt
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
