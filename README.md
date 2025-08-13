# MIAB Whitelists

Automate adding domains and IP addresses to Postfix and Postgrey whitelists on Mail-in-a-Box (MIAB) servers with a single Bash script.

## Overview

`addwhitelists.sh` accepts either a single target (domain or IP) or a text file (`whitelists.txt`) with one entry per line, then:

1) **Automatically creates missing files** if they don’t exist:
   - /etc/postfix/client_whitelist
   - /etc/postgrey/whitelist_clients.local
2) Makes timestamped backups of existing whitelist files (if present).
3) Adds entries to Postfix (/etc/postfix/client_whitelist) with `OK` suffix.
4) Adds **domains** to Postgrey (/etc/postgrey/whitelist_clients.local).
5) Skips duplicates.
6) Rebuilds Postfix hash map and restarts Postfix/Postgrey **only when changes are made**.
7) Supports dry-run mode (`-n`) to preview changes.

Keeping entries in a separate file lets you share this repo safely without exposing private data.

## Prerequisites

- OS: Debian/Ubuntu
- Services: Postfix & Postgrey installed
- Permissions: root or sudo access to `/etc/postfix` and `/etc/postgrey`

## Installation

    git clone https://github.com/Anton-Babaskin/miab-whitelists.git
    cd miab-whitelists
    sudo chmod +x addwhitelists.sh

Or install directly into `/usr/local/bin`:

    cd /usr/local/bin
    sudo wget -O addwhitelists.sh https://raw.githubusercontent.com/Anton-Babaskin/miab-whitelists/main/addwhitelists.sh
    sudo chmod +x addwhitelists.sh

## Usage

Add a single domain or IP:

    sudo ./addwhitelists.sh example.com
    sudo ./addwhitelists.sh 203.0.113.7

Add multiple entries from a file:

    # whitelists.txt
    example.com
    example.org
    203.0.113.7

    sudo ./addwhitelists.sh -f whitelists.txt

Dry-run mode (no changes applied):

    sudo ./addwhitelists.sh -n -f whitelists.txt

## File Formats

Postfix whitelist (`/etc/postfix/client_whitelist`):

    example.com OK
    203.0.113.7 OK

Postgrey whitelist (`/etc/postgrey/whitelist_clients.local`):

    example.com

## CIDR Support

Postfix **hash/lmdb** maps do **not** support CIDR (e.g., `203.0.113.0/24`) directly.  
For networks, create a separate CIDR table and include it in `main.cf`:

    # /etc/postfix/client_whitelist.cidr  (example)
    203.0.113.0/24 OK

    # /etc/postfix/main.cf (snippet)
    smtpd_client_restrictions =
        check_client_access hash:/etc/postfix/client_whitelist,
        check_client_access cidr:/etc/postfix/client_whitelist.cidr,
        permit

## Postfix Configuration Check

Ensure `main.cf` references the map:

    smtpd_client_restrictions =
        check_client_access hash:/etc/postfix/client_whitelist,
        permit

## License

MIT

Author: https://github.com/Anton-Babaskin
