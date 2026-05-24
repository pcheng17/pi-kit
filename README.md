# pi-kit

Personal Pi extensions, skills, and subagents.

## Contents

- `extensions/` - Pi TypeScript extensions.
- `skills/` - Pi skills.
- `agents/` - Subagent prompts used by the bundled `subagent` extension.

## Install locally

```bash
pi install /Users/pcheng/pi-kit
```

Then reload Pi:

```text
/reload
```

Local package installs reference this directory in `~/.pi/agent/settings.json`; files are not copied. New skills/extensions are picked up after `/reload`.

## Code review workflow

```text
/skill:code-review review my current changes
/skill:code-review review staged changes
/skill:code-review review branch main...HEAD
```

The code review skill uses the `subagent` extension to run focused review agents with isolated context:

- `review-correctness`
- `review-security`
- `review-tests`
- `review-maintainability`
- `review-performance`

## Version control

```bash
git init
git add .
git commit -m "Initial pi-kit"
git remote add origin git@github.com:pcheng17/pi-kit.git
git push -u origin main
```

## Security

Only install or pull this repo from trusted sources. Pi extensions run with your user permissions, and skills/agents can instruct the model to run powerful local tools.
