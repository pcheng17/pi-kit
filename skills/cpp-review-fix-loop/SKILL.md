---
name: cpp-review-fix-loop
description: Coordinates a C++ reviewer subagent and C++ author subagent in review/fix rounds until approval. For PRs, reviewer-recommended comments are posted; in PR comment mode, the author fixes each thread in a separate commit, pushes, and replies with commit links.
---

# C++ Review/Fix Loop

Use this skill to coordinate exactly two subagent roles:

- `cpp-reviewer` reviews C/C++ changes with the same broad dimensions as the package `code-review` skill, tailored for C++ correctness, undefined behavior, lifetime/ownership, RAII, templates, performance, tests, and maintainability.
- `cpp-author` edits code to address the reviewer findings, then runs focused verification. When the target is PR review comments, it also creates one commit per addressed thread, pushes it, and replies to that thread with a commit link.

For GitHub PR targets, the reviewer decides whether its findings or notes should be posted to the PR. The reviewer remains read-only and emits posting recommendations; the coordinator posts the recommended PR review/comments.

The main agent is the orchestrator. The reviewer and author do not talk directly; pass compact outputs between them.

## Preconditions

This skill expects the `subagent` tool to be available from the `pi-kit` package extension at:

- `extensions/subagent/`

Required package agents:

- `agents/cpp-reviewer.md`
- `agents/cpp-author.md`

Use `agentScope: "user"` so only package/user-level agents are used. Do not use project-local agents unless the user explicitly asks for them.

If the `subagent` tool is unavailable, tell the user to run `/reload` and retry. If it is still unavailable, fall back to a manual review/fix loop in the main agent and clearly mention that subagent isolation is not active.

## Target Inference

Infer the review target from the user's request:

- **Current working tree**: review unstaged and staged changes.
  - Reviewer should inspect `git status --short`, `git diff --stat`, `git diff`, and `git diff --cached` as needed.
- **Staged changes**: review `git diff --cached`.
- **Branch/PR-like changes**: compare against requested base, usually `main...HEAD`.
- **Commit/range**: review `git show <commit>` or `git diff <range>`.
- **Explicit files**: review only those files/diffs.
- **GitHub PR number/URL**: inspect the PR diff/read-only metadata as needed. If the user asks to address PR comments/review feedback/unresolved threads, use PR comment mode.

If the target is ambiguous but there is an obvious current working tree diff, proceed with current changes. Ask one concise clarifying question only when there is no safe default.

## Default Loop Policy

- Default maximum rounds: **3 reviewer passes**.
- A round means: reviewer pass, then author fix pass if the reviewer requests changes.
- Stop immediately when reviewer outputs `Status: APPROVED` or `Blocking findings: 0`.
- Stop if the author reports a blocker, unresolved failing verification, or cannot safely fix a finding.
- Stop at the max round limit and summarize remaining reviewer findings.
- The reviewer is read-only. Only `cpp-author` may mutate files.
- The coordinator does not edit files except to recover from an obvious subagent failure with user approval.
- For normal local review/fix loops, do not commit, push, or post PR comments unless explicitly requested.
- For PR comment mode, `cpp-author` must create one separate commit per addressed review thread, push each commit, and reply directly to the thread with a link to that commit's full SHA.

## Orchestration Workflow

1. Determine target and verification expectations from the user/project context.
2. Create a short round log in the main context.
3. Invoke `cpp-reviewer` with `subagent` in single mode:

```json
{
  "agentScope": "user",
  "agent": "cpp-reviewer",
  "task": "Review <target> as round 1 of a C++ review/fix loop. Use read-only commands. Return the required Verdict/Findings format."
}
```

4. Parse the reviewer verdict and PR comment recommendations.
5. For GitHub PR targets, inspect the reviewer's `PR Comment Recommendations`. If `Post: yes`, post the recommended review body and/or inline comments before moving to the author step or final response.
6. If the reviewer approved, finish with a concise summary after any recommended PR comments are posted.
7. If changes are requested, pass the complete reviewer output to `cpp-author`.
8. Invoke `cpp-author`:

```json
{
  "agentScope": "user",
  "agent": "cpp-author",
  "task": "Address these C++ review findings for <target>. Keep changes minimal, add focused tests where needed, and run focused verification. Reviewer output:\n\n<reviewer output>"
}
```

9. If the author reports blockers or failing verification, stop and report.
10. If the target is PR review comments, ensure the author summary includes the thread URL/topic, commit URL/full SHA, push result, and reply-posting result for each addressed thread.
11. Reinvoke `cpp-reviewer` for the next round. Include:
   - original target
   - previous reviewer output
   - author fix summary
   - instruction to verify whether findings were resolved and identify only remaining blockers/new regressions
12. Repeat until approved or the max round limit is reached.

## Reviewer PR Comment Posting

Use this behavior for GitHub PR targets, including normal PR reviews and post-author quality-gate reviews.

Reviewer responsibilities:

- Decide whether blocking findings or non-blocking notes should be posted.
- Recommend posting for actionable findings, important project-convention issues, and review notes that would be useful to preserve on the PR.
- Avoid posting duplicates, noisy nits, or speculation.
- Prefer inline comments for precise changed-file line locations.
- Put notes without exact changed-line locations in the review body.
- Output a `## PR Comment Recommendations` section with `Post: yes | no`.

Coordinator responsibilities:

1. If the reviewer recommends `Post: no`, do not post.
2. If the reviewer recommends `Post: yes`, post the recommended comments without asking for extra confirmation unless the user explicitly disabled PR posting.
3. Prefer one GitHub PR review containing inline comments plus a body.
4. Use `gh pr view <pr> --json number,title,headRefOid,baseRefName,headRefName,url` to confirm metadata.
5. For inline comments, use `gh api` to create a PR review with `commit_id`, `event: "COMMENT"`, `body`, and `comments` entries using `path`, `line`, `side: "RIGHT"`, and `body`.
6. Only inline-comment on lines present in the PR diff. If a recommended inline location is invalid or unchanged, move that comment to the review body.
7. If no inline comments are valid, post the review body with `gh pr review <pr> --comment --body-file <file>` or `gh pr comment <pr> --body-file <file>`.
8. Avoid duplicate reviewer comments in the same run. Do not repost the same note on later rounds unless it remains unresolved and still materially matters.
9. If posting fails because of authentication, permissions, missing `gh`, or invalid diff positions, do not retry destructively. Report the exact comment body that would have been posted.

Reviewer task additions for GitHub PR targets:

- Include the PR number/URL.
- Tell `cpp-reviewer` to decide whether to post findings or notes to the PR.
- Tell it to include `## PR Comment Recommendations`, with precise inline locations when appropriate.

## PR Comment Mode

Use this mode when the user asks to address PR comments, review feedback, or unresolved PR threads. It is inspired by the `address-pr-comments` skill but uses the C++ author/editor agent for implementation. In this mode, send the PR-thread task to `cpp-author` first; after the author finishes the per-thread fixes, run `cpp-reviewer` on the updated branch/diff as the rinse-and-repeat quality gate.

Coordinator responsibilities:

1. Confirm the work is on the PR branch, not `main`.
2. Prefer a clean working tree before starting. If unrelated local changes exist, ask the user how to proceed.
3. Pass the PR number/URL and the requirement to process unresolved review threads to `cpp-author`.
4. Instruct `cpp-author` to process one thread at a time and keep exactly one thread in progress.
5. Require one separate commit per addressed thread. Do not allow unrelated threads to be combined into one commit.
6. Require a push after each commit.
7. Require a direct reply to the review thread with a link to the commit using the full SHA.
8. If a thread is ambiguous, contradictory, stale, blocked, or requires user judgment, stop and ask the user before code changes for that thread.

Author task requirements for PR comment mode:

- Discover the PR if needed with `gh pr view --json number,url,title,headRefName,baseRefName,headRefOid`.
- Check `gh auth status` before attempting to post replies.
- Query unresolved review threads with GitHub GraphQL, including every comment in each thread.
- Page through results if there are more than 100 threads or comments.
- Read each full thread, diff hunk, surrounding code, and relevant tests/docs before deciding what to change.
- Implement only the current thread's clear requested change.
- Run focused validation required by the project.
- Stage only files relevant to the current thread.
- Commit with a concise message such as `Address PR feedback on <topic>`.
- Capture `git rev-parse HEAD` and build a commit URL from the repository URL and full SHA.
- Push the current branch with `git push` or `git push -u origin HEAD` if no upstream exists.
- Reply directly to the thread. Prefer GraphQL `addPullRequestReviewThreadReply`; fall back to the REST review-comment replies endpoint if necessary.
- Do not mark threads resolved unless the user explicitly asks or the repo workflow clearly expects it.

PR comment author task template:

```text
Address unresolved C++ PR review comments for <PR number/URL>. Use PR comment mode. For each clear unresolved thread: read the full thread, implement only that thread's change, validate, create one separate commit, push it, and reply directly to the thread with a link to the commit using the full SHA. Stop and report any ambiguous/blocking thread before changing code for that thread. Do not combine unrelated threads in one commit.
```

Use separate `subagent` calls per round rather than a single long chain when you need to inspect the verdict and decide whether to continue. A `chain` call is acceptable for a fixed two-step review-then-author pass only when the user explicitly asks for one pass.

## Reviewer Task Template

Include this information in each reviewer task:

- Target: `<target>`
- Round: `<n>` of `<max>`
- Read-only requirement
- C++ focus: correctness, undefined behavior, lifetime/ownership, RAII, templates, numeric precision, performance, tests, maintainability
- If re-reviewing: previous findings and author summary
- For GitHub PR targets: decide whether findings or notes should be posted and include `## PR Comment Recommendations`
- Output must use the `## Verdict` format and `Status: APPROVED | CHANGES_REQUESTED`

## Author Task Template

Include this information in each author task:

- Target: `<target>`
- Reviewer findings to address, including IDs
- Scope: minimal C++ changes only
- Verification expectation: focused tests/builds; use project conventions if obvious
- For normal local review/fix loops: do not commit/push/post comments unless explicitly requested
- For PR comment mode: commit, push, and reply to each addressed thread as described above
- Output must use the `## Fix Summary` format

## Final Output Format

If approved:

```markdown
## Result
Approved after <n> reviewer pass(es).

## Changes Made
- Short bullets from the author summaries, or `None` if no fixes were needed.

## Verification
- Commands run and result.

## Reviewer PR Comments
- Posted reviewer comments, skipped recommendations, or posting failures.

## PR Thread Replies
- Thread replies with commit links, or `Not applicable`.

## Notes
- Any non-blocking reviewer notes.
```

If stopped before approval:

```markdown
## Result
Stopped after <n> reviewer pass(es): <reason>.

## Remaining Findings
- Summarized blocking findings with file/line references.

## Changes Made
- Short bullets from author summaries.

## Verification
- Commands run and current status.

## Reviewer PR Comments
- Posted reviewer comments, skipped recommendations, or posting failures.

## PR Thread Replies
- Thread replies with commit links, failed reply text, or `Not applicable`.

## Next Step
- Recommended user action.
```

## Guidelines

- Keep the main context clean: do not paste large diffs into the final answer.
- Preserve reviewer/author separation: reviewer stays read-only; author mutates.
- Prefer definite C++ bugs and project-convention violations over speculation.
- Do not let the loop thrash on subjective nits; approve with notes when only non-blocking concerns remain.
- If a subagent fails because an agent is unknown, tell the user to run `/reload` so Pi discovers the new package agents.
