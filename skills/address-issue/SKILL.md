---
name: address-issue
description: Implements a GitHub issue by reading and clarifying requirements first, confirming a clear design with the user, creating a worktree from latest main, doing the work off main, committing, pushing, and opening a PR. Use when asked to address, implement, fix, or work on an issue.
---

# Address Issue

Use this skill when the user asks you to address, implement, fix, or work on a GitHub issue.

## Core Requirements

- Read the issue before making any changes.
- Understand the requested behavior, acceptance criteria, discussion, linked context, and relevant code.
- Do not make product, API, UX, architecture, compatibility, or scope decisions yourself.
- If anything is ambiguous, ask the user specific questions before proceeding.
- Produce a clear design/implementation plan based only on the issue and the conversation with the user.
- Create a new git worktree before editing files. Never do implementation work on `main`.
- Branch the worktree from the latest state of `main`, preferably `origin/main` after fetching.
- Implement the issue, validate it, commit it, push it, and create a pull request.
- All new code must have unit tests. CI checks unit tests and coverage, and coverage must remain at 100% for both line coverage and function coverage.

## Preconditions

- Ensure `gh` is installed and authenticated:
  ```bash
  gh auth status
  ```
- Ensure the current repository and target repository are correct:
  ```bash
  git rev-parse --show-toplevel
  gh repo view --json owner,name,url
  ```
- If the repository has project-specific workflow instructions, follow them for worktree naming, hooks, formatting, tests, coverage, and commit style.
- Inspect local status before starting. Do not overwrite, stage, commit, or otherwise modify unrelated user changes:
  ```bash
  git status --short --branch
  ```

## Identify and Read the Issue

If the user provides an issue number or URL, use it. Otherwise ask which issue to address.

Read the full issue, including comments and metadata:

```bash
gh issue view <ISSUE> --comments --json number,title,state,url,body,labels,assignees,milestone,comments
```

Also inspect linked context before designing or implementing:

- Linked issues, PRs, discussions, commits, or documentation referenced in the issue body/comments.
- Relevant files, tests, README/docs, and existing implementation patterns.
- Recent changes on `main` if they affect the issue.

If the issue is closed, duplicated, already fixed, or not in the expected repository, stop and ask the user how to proceed.

## Clarify Before Designing

Ask the user for clarification whenever the issue leaves any material choice open. Do not choose silently.

Clarify when any of these are unclear:

- Expected behavior, inputs, outputs, edge cases, or error handling.
- API names, data model, public surface area, or backwards compatibility.
- UI/UX, product behavior, performance trade-offs, or migration behavior.
- Scope boundaries, non-goals, or whether to include adjacent cleanup/refactors.
- Test expectations, fixtures, or acceptance criteria.
- Conflicting statements between the issue body, comments, code, or project instructions.
- Branch/worktree naming if the deterministic names below would conflict.

When asking, include:

- The issue URL and a short summary.
- The exact ambiguity.
- 2-4 concrete options when possible.
- No hidden recommendation unless it follows directly from explicit project instructions.

Do not create the implementation worktree until all blocking ambiguities are resolved.

## Design Gate

Before editing code, present a concise plan and ask the user to confirm it. The plan must be clear from the issue plus user clarifications, not from assumptions.

Include:

- Issue summary and intended outcome.
- Explicit acceptance criteria.
- Proposed implementation steps.
- Files or areas expected to change.
- Unit tests to add or update for every new code path.
- Coverage validation to confirm 100% line and function coverage when required by the repository.
- Tests/validation to run.
- Worktree path and branch name.
- PR title/body outline.

If the user changes the plan, update it and ask again if any meaningful ambiguity remains. Proceed only after the user confirms the plan or explicitly instructs you to continue.

## Create the Worktree from Latest Main

After the design gate passes, create a dedicated worktree from the latest `main`.

1. Fetch latest main:
   ```bash
   git fetch origin main
   ```
2. Choose deterministic names unless project instructions say otherwise:
   - Branch: `issue/<ISSUE_NUMBER>-<short-slug>`
   - Worktree path: `../<repo-name>-issue-<ISSUE_NUMBER>-<short-slug>`
3. If the branch or worktree path already exists, stop and ask the user for the replacement name or cleanup preference.
4. Create the worktree from `origin/main`, not local `main`:
   ```bash
   git worktree add ../<repo-name>-issue-<ISSUE_NUMBER>-<short-slug> \
     -b issue/<ISSUE_NUMBER>-<short-slug> origin/main
   ```
5. Move into the new worktree and verify that it is not `main`:
   ```bash
   cd ../<repo-name>-issue-<ISSUE_NUMBER>-<short-slug>
   git branch --show-current
   git merge-base --is-ancestor origin/main HEAD
   ```
6. Configure any required repository hooks or setup inside the worktree.

Never edit files in the original `main` worktree while addressing the issue.

## Implement the Issue

- Keep changes limited to the confirmed issue scope.
- Follow project-specific conventions exactly.
- Add or update unit tests for all new code, behavior changes, and public APIs.
- Ensure tests exercise every new function and every new line so CI coverage remains at 100% line and function coverage.
- Avoid opportunistic refactors and unrelated cleanup.
- If new ambiguity appears during implementation, stop and ask the user before continuing.
- If the implementation cannot follow the confirmed plan, stop, explain why, and ask for an updated decision.

## Validate

Run the smallest useful validation commands first, then any required project-level commands. For repositories with enforced coverage, run the appropriate coverage target/report before opening the PR and do not proceed while line or function coverage is below 100%.

Examples:

```bash
cmake --build --preset debug-tests
ctest --preset debug-tests
```

If validation fails, fix failures that are within the confirmed scope. If failures are unrelated, environmental, or require new decisions, stop and ask the user.

## Commit and Push

Before committing:

```bash
git status --short
git diff
git diff --cached
```

Stage only relevant files. Do not stage unrelated user changes.

Commit with a concise message that references the issue, following repository conventions when present. Example:

```bash
git commit -m "Address issue #<ISSUE_NUMBER>: <short topic>"
```

Push the branch:

```bash
git push -u origin HEAD
```

If the user or repository workflow explicitly requires publishing the branch before implementation, push an empty or setup commit only after asking the user; otherwise push after the implementation commit.

## Create the Pull Request

Create a PR against `main` after pushing:

```bash
gh pr create \
  --base main \
  --head <branch-name> \
  --title "<clear issue-based title>" \
  --body-file <pr-body-file>
```

The PR body should include:

- Link to the issue and `Closes #<ISSUE_NUMBER>` when appropriate.
- Summary of changes.
- Tests/validation run.
- Any known limitations or follow-up work explicitly approved by the user.

If PR creation fails due to authentication, permissions, or network issues, report the exact command/output and provide the prepared PR title/body.

## Final Response

Summarize:

```markdown
## Issue Addressed
- Issue: <issue URL>
- Branch: <branch name>
- Worktree: <path>
- Commit: <commit SHA or URL>
- PR: <PR URL>

## Validation
- <commands run and results>

## Notes
- <ambiguities resolved, limitations, or follow-ups>
```
