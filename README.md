# pi-kit

Personal Pi extensions, skills, and subagents.

## Contents

- `skills/` - Pi skills.
- `agents/` - Custom agent prompts exposed to the `pi-subagents` package.
- `pi-subagents` - Third-party subagent extension, loaded from `node_modules`.
- `pi-mcp-adapter` - Bundled Pi MCP extension, loaded from `node_modules`.

## Install locally

```bash
/path/to/pi-kit/scripts/install.sh
```

The installer installs locked dependencies, registers this checkout with Pi, and links the global Pi instructions. It is safe to rerun. If an existing `~/.pi/agent/AGENTS.md` differs from pi-kit's canonical instructions, reconcile it manually before running the installer.

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

The code review skill uses `pi-subagents` to run focused review agents with isolated context:

- `review-correctness`
- `review-security`
- `review-tests`
- `review-maintainability`
- `review-performance`

## C++ review/fix loop

```text
/skill:cpp-review-fix-loop review and fix my current C++ changes
/skill:cpp-review-fix-loop review branch main...HEAD and iterate until approved
/skill:cpp-review-fix-loop address unresolved C++ PR comments on PR 123
```

The C++ loop coordinates two package agents:

- `cpp-reviewer` - read-only C++ reviewer piggybacking on the broad `code-review` dimensions. For PR targets, it recommends when findings/notes should be posted and the coordinator posts them.
- `cpp-author` - scoped editor that fixes reviewer findings and runs focused verification. In PR comment mode, it creates one commit per addressed thread, pushes it, and replies with the commit link.

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
