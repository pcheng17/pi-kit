---
name: address-pr-comments
description: Resolves unresolved GitHub PR review comment threads by reading each full thread, implementing agreed changes, committing each thread separately, pushing once after all commits are made, and replying with commit links. Use when asked to address PR comments, review feedback, or unresolved PR threads.
---

# Address PR Comments

Use this skill when the user asks you to address, fix, resolve, or respond to comments on a GitHub pull request.

## Core Requirements

- Address only PR review threads that have not already been resolved.
- Read the entire thread before deciding what to do. Use all comments, diffs, and surrounding code to understand context.
- If the thread reaches a clear implementation decision, implement that decision.
- If the expected implementation is ambiguous, blocked, contradictory, or requires product/design judgment, ask the user for clarification before changing code for that thread.
- Create one separate commit per addressed comment thread. Do not combine unrelated threads into one commit.
- Do not push after each commit. Push only once, after all planned per-thread commits have been created, to avoid triggering GitHub Actions/CI separately for each code-changing commit and to be mindful of CI usage.
- After the single push, reply to each addressed PR thread with a link to its commit using its SHA so reviewers can reference the exact change.

## Preconditions

- Work on the PR branch, not `main`.
- Ensure `gh` is installed and authenticated (`gh auth status`).
- Ensure the working tree is clean before starting. If there are existing user changes, stop and ask how to proceed.
- If the repository has project-specific workflow instructions, follow them for formatting, tests, hooks, branch/worktree rules, and commit style.

## Discover the PR and Unresolved Threads

If the user provides a PR number or URL, use it. Otherwise infer the PR for the current branch:

```bash
gh pr view --json number,url,title,headRefName,baseRefName,headRefOid
```

Fetch unresolved review threads with GraphQL. First get the repository owner/name:

```bash
gh repo view --json owner,name
```

Then query all review threads and filter to unresolved ones. Include every comment in each thread:

```bash
gh api graphql -f owner='<OWNER>' -f repo='<REPO>' -F number='<PR_NUMBER>' -f query='\
query($owner: String!, $repo: String!, $number: Int!) {\
  repository(owner: $owner, name: $repo) {\
    pullRequest(number: $number) {\
      number\
      url\
      headRefName\
      headRefOid\
      reviewThreads(first: 100) {\
        nodes {\
          id\
          isResolved\
          path\
          line\
          originalLine\
          diffSide\
          isOutdated\
          comments(first: 100) {\
            nodes {\
              id\
              databaseId\
              url\
              author { login }\
              createdAt\
              body\
              path\
              line\
              originalLine\
              diffHunk\
            }\
          }\
        }\
      }\
    }\
  }\
}'
```

If there are more than 100 threads or comments, page through results before acting. Do not ignore threads because of pagination.

## Per-Thread Workflow

Process threads one at a time. Keep exactly one thread in progress.

1. **Read the full thread**
   - Read every comment in chronological order.
   - Inspect the referenced file, diff hunk, surrounding code, and any related tests/docs.
   - Determine whether later replies supersede earlier suggestions.

2. **Decide whether action is clear**
   - Clear: the thread contains an agreed code/test/docs change, a direct bug report, or a reviewer request with an obvious implementation.
   - Not clear: multiple incompatible suggestions, missing requirements, scope uncertainty, stale comments whose relevance is unclear, or any decision that needs user judgment.
   - If not clear, ask the user a specific clarification question and wait. Do not guess.

3. **Implement only that thread's change**
   - Keep the diff minimal and limited to the thread.
   - Add or update tests when the change affects behavior or when project rules require tests.
   - Avoid opportunistic refactors and unrelated cleanup.

4. **Validate**
   - Run the smallest useful formatter/test command for the changed area.
   - If project instructions require a broader command, run it.
   - If validation fails, fix the failure before committing. If blocked, ask the user.

5. **Commit only this thread's changes**
   - Re-check the diff and stage only files relevant to this thread.
   - Commit with a concise message referencing the PR thread or topic, for example:
     ```bash
     git commit -m "Address PR feedback on <topic>"
     ```
   - Capture the full SHA:
     ```bash
     git rev-parse HEAD
     ```

6. **Record the commit for later push/reply**
   - Do not push yet.
   - Record the thread URL/ID, commit SHA, validation command, and intended reply text so you can reply after the final push.

7. **Move to the next unresolved thread**
   - Refresh thread status if needed, especially after user clarification or if reviewers are active.
   - Never include changes for the next thread in the previous thread's commit.

## After All Thread Commits Are Ready

1. **Push all commits once**
   - Push the current branch only after all planned per-thread commits have been created. Each push with code changes can trigger GitHub Actions/CI, so batching the push saves CI time and keeps usage mindful:
     ```bash
     git push
     ```
   - If the branch has no upstream, set it explicitly:
     ```bash
     git push -u origin HEAD
     ```

2. **Reply to each addressed thread with its commit link**
   - Build a commit URL from the PR/repo URL and each full SHA, e.g. `https://github.com/OWNER/REPO/commit/FULL_SHA`.
   - Reply directly to the review thread, not as a top-level PR comment.
   - Use a short reply such as:
     ```markdown
     Addressed in https://github.com/OWNER/REPO/commit/FULL_SHA (`FULL_SHA`).
     ```
   - Prefer the GraphQL thread reply mutation:
     ```bash
     gh api graphql -f threadId='<THREAD_NODE_ID>' -f body='Addressed in https://github.com/OWNER/REPO/commit/FULL_SHA (`FULL_SHA`).' -f query='\
     mutation($threadId: ID!, $body: String!) {\
       addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: $threadId, body: $body }) {\
         comment { url }\
       }\
     }'
     ```
   - If GraphQL reply is unavailable, use the REST reply endpoint against a comment in the thread:
     ```bash
     gh api -X POST /repos/OWNER/REPO/pulls/PR_NUMBER/comments/COMMENT_DATABASE_ID/replies -f body='Addressed in https://github.com/OWNER/REPO/commit/FULL_SHA (`FULL_SHA`).'
     ```

## Clarification Guidance

Ask the user before implementing when any of these are true:

- The thread asks a question but no final answer exists.
- Reviewers disagree or the author has not accepted a suggestion.
- The change could be implemented in multiple materially different ways.
- The comment appears stale/outdated and the correct action is uncertain.
- The requested change conflicts with project instructions, tests, or another thread.
- Validation requires credentials, services, or commands that are unavailable.

When asking, include:

- PR thread URL and short summary.
- The ambiguity.
- 2-4 concrete implementation options when possible.
- Your recommended option if one is safest.

## Safety and Git Hygiene

- Never commit unrelated local changes.
- Before each commit, inspect `git status --short` and `git diff --staged`.
- If multiple files changed because of formatting, ensure every formatted change belongs to the current thread.
- If a later thread requires modifying code changed by an earlier thread, create a new commit on top and mention the new SHA in that later thread.
- Do not mark a GitHub thread resolved unless the user explicitly asks or the repository workflow clearly expects it.
- If posting a reply fails due to permissions, authentication, or API limitations, report the exact reply text and thread URL to the user.

## Final Response

Summarize work by thread:

```markdown
## PR Comment Resolution
- Thread: <thread URL or file/topic>
  - Commit: <commit URL> (`<full SHA>`)
  - Reply posted: yes/no
  - Validation: <commands run>

## Notes
- Any unresolved threads needing user clarification or external action.
```
