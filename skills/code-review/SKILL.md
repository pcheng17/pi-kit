---
name: code-review
description: Reviews code changes using isolated subagents for correctness, security, tests, maintainability, and performance. Use when asked to review diffs, PRs, commits, branches, staged changes, or current changes while keeping the main context clean.
---

# Code Review with Isolated Subagents

Use this skill to review code changes without loading all review context into the main conversation. The main agent acts as coordinator. Specialized subagents inspect the code in separate Pi processes and return compact findings.

## Preconditions

This skill expects the `subagent` tool to be available. It is provided by the `pi-kit` package extension at:

- `extensions/subagent/`

Available review subagents are bundled in this package at:

- `agents/review-correctness.md`
- `agents/review-security.md`
- `agents/review-tests.md`
- `agents/review-maintainability.md`
- `agents/review-performance.md`

The subagent extension also supports user-level agents in `~/.pi/agent/agents/`; user agents with the same name override bundled package agents. If the `subagent` tool is unavailable, tell the user to run `/reload` and retry. If it is still unavailable, fall back to a normal review and mention that isolation is not active.

## Review Targets

Infer the target from the user's request:

- **Current working tree**: review unstaged and staged changes.
  - Use `git status --short`, `git diff --stat`, `git diff`, and `git diff --cached`.
- **Staged changes**: use `git diff --cached`.
- **Branch/PR**: compare against the requested base, usually `main...HEAD`.
- **Commit/range**: use `git show <commit>` or `git diff <range>`.
- **Explicit files**: review only those files/diffs.

Do not run mutating commands during review. Do not edit files unless the user explicitly asks for fixes after the review.

## Subagent Workflow

Delegate review in parallel with the `subagent` tool. Use `agentScope: "user"` so only trusted bundled/package and user-level review agents are loaded. Do not use project-local agents for this global review workflow unless the user explicitly asks for them.

Recommended parallel tasks:

1. `review-correctness` — logic bugs, regressions, edge cases, API contracts.
2. `review-security` — auth, injection, secrets, privacy, unsafe boundaries.
3. `review-tests` — missing/brittle tests and verification plan.
4. `review-maintainability` — readability, architecture, conventions, coupling.
5. `review-performance` — scalability, resource usage, concurrency, reliability.

Construct each task with:

- The review target.
- Any user-specified focus areas.
- Instructions to use read-only commands only.
- Instructions to return at most 5 compact findings.
- Instructions not to include full diffs or large code excerpts.

Example tool shape:

```json
{
  "agentScope": "user",
  "tasks": [
    {
      "agent": "review-correctness",
      "task": "Review current working tree changes for correctness bugs. Use git status --short, git diff --stat, git diff, and git diff --cached as needed. Return at most 5 compact findings with file:line references."
    },
    {
      "agent": "review-security",
      "task": "Review current working tree changes for security/privacy risks. Use read-only commands only. Return at most 5 compact findings with file:line references."
    },
    {
      "agent": "review-tests",
      "task": "Review current working tree changes for missing or brittle tests. Use read-only commands only. Return at most 5 compact findings and a short suggested test plan."
    },
    {
      "agent": "review-maintainability",
      "task": "Review current working tree changes for maintainability, readability, architecture, and convention issues. Use read-only commands only. Return at most 5 compact findings."
    },
    {
      "agent": "review-performance",
      "task": "Review current working tree changes for performance, scalability, concurrency, and reliability risks. Use read-only commands only. Return at most 5 compact findings."
    }
  ]
}
```

## Main-Agent Synthesis

After subagents finish, synthesize their outputs. Do not dump raw subagent output unless the user asks.

Prioritize findings by severity and confidence:

- **Critical**: security vulnerability, data loss, production outage, broken build/release.
- **High**: likely user-visible bug or serious regression.
- **Medium**: important edge case, missing test, maintainability risk.
- **Low**: minor improvement or nit with clear value.

Merge duplicates across subagents. Prefer definite bugs over speculation. Mention uncertainty when a finding depends on assumptions.

## Final Output Format

```markdown
## Findings

### High: Short title
- Location: `path:line`
- Source: correctness/security/tests/maintainability/performance
- Issue: what is wrong
- Why it matters: concrete impact
- Suggested fix: concise direction

## Tests
- Existing coverage observed: ...
- Suggested tests or commands: ...

## Summary
One short paragraph with overall risk and whether there are blockers.
```

If no meaningful findings exist:

```markdown
No blocking issues found.

## Notes
- Any minor suggestions or test plan items.
```

## Guidelines

- Keep the main context clean: delegate broad inspection to subagents and only synthesize compact results.
- Do not read entire large diffs in the main agent unless needed to resolve conflicting subagent findings.
- Use file/line references whenever possible.
- Avoid vague comments like “consider improving this.”
- Distinguish definite problems from speculative risks.
- Do not modify code during review unless the user explicitly asks for fixes.
