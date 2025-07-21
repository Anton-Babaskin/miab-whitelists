MIAB Whitelists

A simple, universal Bash script to automate adding domains and IP addresses to Postfix and Postgrey whitelists on Mail-in-a-Box servers.

Table of Contents

Overview

Prerequisites

Installation

Configuration

Usage

Backup and Safety

Examples

Contributing

License

Overview

This repository provides a single, easy-to-use script (add_whitelists.sh) that reads a plain-text file containing domains and IP addresses, then automatically:

Backs up your existing Postfix and Postgrey whitelist files.

Adds entries to Postfix (/etc/postfix/client_whitelist) with the OK flag.

Adds domain entries to Postgrey (/etc/postgrey/whitelist_clients.local).

Rebuilds the Postfix hash database and restarts both services.

By separating your whitelist entries into a simple text file, you can maintain this script in a public repository without exposing your own domains or IPs.

Prerequisites

Debian/Ubuntu-based system

Postfix installed and configured

Postgrey installed and configured

Root or sudo privileges to modify /etc/postfix and /etc/postgrey

Installation

Clone the repository

git clone https://github.com/Anton-Babaskin/miab-whitelists.git
cd miab-whitelists

Prepare your whitelist file

Create a file named whitelist.txt in the repository root.

Add one domain or IP (CIDR notation supported) per line. Do not include comments or blank lines.

Example whitelist.txt:

example.com
203.0.113.0/24
mail.partner-domain.org

Make the script executable

chmod +x add_whitelists.sh

Configuration

If your Postfix whitelist file is located elsewhere, edit the POSTFIX_FILE variable at the top of add_whitelists.sh.

If your Postgrey whitelist file has a different path or filename, update the POSTGREY_FILE variable accordingly.

# In add_whitelists.sh
POSTFIX_FILE="/etc/postfix/client_whitelist"
POSTGREY_FILE="/etc/postgrey/whitelist_clients.local"

Usage

Run the script with your whitelist file as its only argument:

sudo ./add_whitelists.sh whitelist.txt

What the script does:

Creates timestamped backups:

/etc/postfix/client_whitelist.bak_YYYY-MM-DD_HH:MM:SS

/etc/postgrey/whitelist_clients.local.bak_YYYY-MM-DD_HH:MM:SS

Reads each line from whitelist.txt:

If an entry is not present in Postfix, appends ENTRY OK to the Postfix file.

If an entry is a valid domain (not an IP/CIDR) and not present in Postgrey, appends ENTRY to the Postgrey file.

Runs:

postmap "$POSTFIX_FILE"
systemctl restart postfix
systemctl restart postgrey

Backup and Safety

Before making any changes, the script ensures you have backups of both whitelist files. In case of any mistakes, simply restore the .bak_... files:

sudo cp /etc/postfix/client_whitelist.bak_2025-07-21_12:00:00 /etc/postfix/client_whitelist
sudo cp /etc/postgrey/whitelist_clients.local.bak_2025-07-21_12:00:00 /etc/postgrey/whitelist_clients.local

Then rebuild and restart:

sudo postmap /etc/postfix/client_whitelist
sudo systemctl restart postfix postgrey

Examples

Adding a single whitelist

echo -e "partner.com
198.51.100.0/24" > whitelist.txt
sudo ./add_whitelists.sh whitelist.txt

In a cron job

To automatically apply updates from a central repo:

# /etc/cron.daily/miab-whitelist
#!/bin/bash
cd /opt/miab-whitelists
git pull --ff-only
/opt/miab-whitelists/add_whitelists.sh /opt/miab-whitelists/whitelist.txt

Contributing

Contributions, issues, and feature requests are welcome!Feel free to open a pull request or issue in this repository.

License

This project is licensed under the MIT License. See LICENSE for details.

