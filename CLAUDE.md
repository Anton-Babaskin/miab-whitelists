# CLAUDE.md

Guidance for AI assistants (including Claude) working in this repository.

## Commit attribution — strict rules

When creating commits, tags, or any Git metadata in this repository, you **MUST NOT**
add any AI, assistant, or bot attribution. Specifically, never add:

- `Co-authored-by:` trailers of any kind
- `Generated-by` / `Generated with` lines
- Claude attribution (e.g. `Claude`, `noreply@anthropic.com`, `claude.ai` links)
- Any AI attribution
- Any bot attribution

All commits **must** be authored and committed using **only the repository owner's
configured Git identity**:

```
Anton Babaskin <me@fy-consulting.net>
```

Do not set the author or committer name/email to `Claude`, `Anthropic`, any bot
account, or `noreply@anthropic.com`. Do not append assistant sign-offs, session
links, or "🤖 Generated with" footers to commit messages.

If a Git identity is not already configured for the owner, configure it explicitly
before committing:

```bash
git config user.name  "Anton Babaskin"
git config user.email "me@fy-consulting.net"
```

## Scope rules

- Do not modify application logic in `add_whitelists.sh` or the configured
  `PROVIDERS` list in `refresh_cloud_senders.sh` unless explicitly asked.
- Keep documentation accurate to the actual behavior of the scripts.
- Never commit real corporate domains, IP addresses, mail logs, tokens, or other
  private infrastructure data. Use RFC 5737 / RFC 2606 placeholders in examples.

## Quality checks

Before committing changes to either script, run and ensure both pass:

```bash
bash -n add_whitelists.sh && shellcheck add_whitelists.sh
bash -n refresh_cloud_senders.sh && shellcheck refresh_cloud_senders.sh
```
