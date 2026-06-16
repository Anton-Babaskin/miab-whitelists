# Contributing to miab-whitelists

Thank you for considering a contribution. This document explains how to get involved.

## Getting started

1. **Fork** the repository and clone your fork locally.
2. **Create a branch** with a descriptive name:
   ```bash
   git checkout -b fix/backup-rotation-edge-case
   git checkout -b docs/update-troubleshooting
   git checkout -b feat/ipv6-support
   ```
3. **Make your changes** in small, focused commits. Each commit should do one logical thing.

## Bash style

- Target Bash 4+; use `#!/usr/bin/env bash` and `set -Eeuo pipefail`.
- Prefer `[[ ]]` over `[ ]` for conditionals.
- Quote all variable expansions unless you explicitly need word-splitting.
- Keep functions short and single-purpose.

## Before opening a pull request

Run both checks locally and make sure they pass cleanly:

```bash
bash -n add_whitelists.sh
shellcheck add_whitelists.sh
```

If you changed documented behavior:

- Update **README.md** and **README_RU.md** to match.
- Add an entry under `[Unreleased]` in **CHANGELOG.md**.

## Privacy and security

**Never include in issues or pull requests:**

- Real corporate domains, IP addresses, or CIDR ranges.
- Authentication tokens, API keys, or credentials.
- Mail server logs or configuration files.
- Any private infrastructure details.

If you have found a security issue, please report it privately — see [SECURITY.md](./SECURITY.md).

## Opening a pull request

Push your branch to your fork and open a PR against `main`. Fill in the pull request template completely, including the checklist items.

Please read our [Code of Conduct](./CODE_OF_CONDUCT.md) before participating.
