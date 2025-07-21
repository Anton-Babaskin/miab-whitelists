---

### 6.2. Issues templates

Create a `.github/ISSUE_TEMPLATE/` folder and inside it two files:

1. **`bug_report.md`**

```markdown
---
name: Bug report
about: Report a problem with the script or docs
title: "[BUG] "
labels: bug
assignees: ''

---

**Problem description**
Describe what exactly is broken.

**Steps to reproduce**
1. …
2. …
3. …

**Expected behavior**
What you would like to see.

**Screenshots/logs**
If you have any, please include them.

**Environment (please specify)**
- OS: Debian/Ubuntu version
- Script version/tag: v1.0.0
- ShellCheck status: pass/fail
```

2. **`feature_request.md`**

```markdown
---
name: Feature request
about: Suggestions for enhancements or new features
title: "[FEATURE] "
labels: enhancement
assignees: ''

---

**Goal**
What do you want to achieve?

**Why is this important**
Who needs it and why?

**Use cases**
Describe how you plan to use the feature.

**Additional information**
Any details or links to documentation/issues.
```

---

### 6.3. Pull Request Template

In the root of `.github/`, create a file `PULL_REQUEST_TEMPLATE.md`:

```markdown
# Pull Request

## Description
Brief: what was changed and why?

## Type of changes
- [ ] Bugfix
- [ ] New feature
- [ ] Docs
- [ ] CI/CD
- [ ] Other: ________

## How to test
1. What steps should I take to make sure everything works?

2. …

## Checklist
- [ ] Code passed ShellCheck
- [ ] README.md updated if needed
- [ ] CHANGELOG.md in the _Unreleased_ section
