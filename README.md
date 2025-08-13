MIAB Whitelists

Automate adding domains and IP addresses to Postfix and Postgrey whitelists on Mail-in-a-Box servers with a single, universal Bash script.
📝 Overview
The add_whitelists.sh script simplifies whitelisting domains and IP addresses for Postfix and Postgrey on Mail-in-a-Box servers. It supports:

Reading a text file (whitelist.txt) with one domain or IP per line.
Adding a single domain or IP directly via command-line argument.
Dry-run mode to preview changes without modifying files.
Creating timestamped backups of existing whitelist files.
Adding entries to Postfix (/etc/postfix/client_whitelist) with OK suffix.
Adding domain entries to Postgrey (/etc/postgrey/whitelist_clients.local).
Rebuilding the Postfix hash database and restarting services as needed.

The whitelist entries are stored in a separate file or provided as arguments, ensuring sensitive data is not hardcoded in the script.
⚙️ Prerequisites

OS: Debian / Ubuntu
Services: Postfix and Postgrey installed
Permissions: Root or sudo access to modify /etc/postfix and /etc/postgrey
Input Format: Domains (e.g., example.com, mail.partner-domain.org) or IPv4 addresses (e.g., 198.51.100.1). CIDR notation (e.g., 198.51.100.0/24) is not supported in Postfix hash maps and will be skipped with a warning.

🚀 Installation

Clone the repository:
git clone https://github.com/Anton-Babaskin/miab-whitelists.git
cd miab-whitelists


Create a whitelist.txt file (optional, for bulk entries):
# whitelist.txt
example.com
198.51.100.1
mail.partner-domain.org


Make the script executable:
chmod +x add_whitelists.sh



🛠️ Configuration
Customize file paths in the script header if needed:
# add_whitelists.sh
POSTFIX_FILE="/etc/postfix/client_whitelist"
POSTGREY_FILE="/etc/postgrey/whitelist_clients.local"

Ensure /etc/postfix/main.cf includes the Postfix whitelist in smtpd_client_restrictions, e.g.:
smtpd_client_restrictions = ..., check_client_access hash:/etc/postfix/client_whitelist, ...

▶️ Usage
Add entries from a file
Run the script with a whitelist file:
sudo ./add_whitelists.sh -f whitelist.txt

Add a single entry
Add a single domain or IP directly:
sudo ./add_whitelists.sh example.com
sudo ./add_whitelists.sh 198.51.100.1

Dry-run mode
Preview changes without applying them:
sudo ./add_whitelists.sh -n -f whitelist.txt
sudo ./add_whitelists.sh -n example.com

What happens

Backups: Creates timestamped backups of whitelist files (e.g., client_whitelist.bak_YYYY-MM-DD_HHMMSS).
Processing:
Skips empty lines, comments (#), or invalid entries.
Warns about unsupported CIDR entries and skips them.
Adds valid IPs or domains to Postfix (ENTRY OK).
Adds valid domains (not IPs) to Postgrey (ENTRY).


Application:
Runs postmap on the Postfix whitelist if modified.
Restarts postfix and postgrey services if changes are made.



🛡️ Backup & Safety
The script creates timestamped backups before modifying files. To restore:
sudo cp /etc/postfix/client_whitelist.bak_YYYY-MM-DD_HHMMSS /etc/postfix/client_whitelist
sudo cp /etc/postgrey/whitelist_clients.local.bak_YYYY-MM-DD_HHMMSS /etc/postgrey/whitelist_clients.local
sudo postmap /etc/postfix/client_whitelist
sudo systemctl restart postfix postgrey

To automatically delete backups older than 30 days, add to the script or run separately:
find /etc/postfix -name "client_whitelist.bak_*" -mtime +30 -delete
find /etc/postgrey -name "whitelist_clients.local.bak_*" -mtime +30 -delete

💡 Examples
Bulk add via file
echo -e "partner.com\n198.51.100.1" > whitelist.txt
sudo ./add_whitelists.sh -f whitelist.txt

Single entry
sudo ./add_whitelists.sh mail.example.org

Automate via cron
# /etc/cron.daily/miab-whitelist
#!/bin/bash
cd /opt/miab-whitelists
git pull --ff-only
/opt/miab-whitelists/add_whitelists.sh -f /opt/miab-whitelists/whitelist.txt

⚠️ Notes

CIDR Limitation: CIDR notation (e.g., 198.51.100.0/24) is not supported in Postfix hash maps. Use a separate CIDR table in /etc/postfix/main.cf (e.g., check_client_access cidr:/etc/postfix/client_whitelist.cidr).
Validation: The script validates domains and IPv4 addresses, skipping invalid entries with warnings.
Case Handling: Entries are converted to lowercase to ensure consistency.
Main.cf Check: The script checks if client_whitelist is referenced in /etc/postfix/main.cf and warns if missing.

🤝 Contributing
Contributions are welcome! Please follow the standard fork → branch → pull request workflow. Report issues or suggest improvements via GitHub Issues.
📜 License
MIT © Anton Babaskin. See LICENSE for details.
