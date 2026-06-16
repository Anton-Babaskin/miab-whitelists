# Security Policy

## Supported versions

| Version | Supported |
| ------- | --------- |
| 2.x     | Yes       |
| 1.x     | No        |

## Reporting a vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Report security issues privately via [GitHub Security Advisories](https://github.com/Anton-Babaskin/miab-whitelists/security/advisories/new).

Include:
- a description of the issue;
- steps to reproduce;
- the potential impact.

You will receive a response within a reasonable time. If the issue is confirmed, a fix will be prepared before any public disclosure.

## Whitelist safety notice

This tool modifies Postfix and Postgrey whitelist files, which directly affect mail filtering on your server. Entries added to these files may allow selected senders to bypass greylisting or other restrictions.

- Only add entries you control or have independently verified.
- Use the smallest possible CIDR network range.
- Run dry-run mode (`-n`) before applying a large list.
- Audit both whitelist files periodically.

## What not to share

When reporting issues or opening pull requests, **never include**:

- Real corporate domains or hostnames.
- Real IP addresses or network ranges from your infrastructure.
- Mail server logs or Postfix/Postgrey configuration files.
- Authentication tokens, API keys, or credentials of any kind.

Use placeholder values from RFC 5737 (`203.0.113.x`, `198.51.100.x`) and RFC 2606 (`example.com`) instead.
