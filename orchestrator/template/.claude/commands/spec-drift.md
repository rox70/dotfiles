---
description: Detect drift between the local OpenSpec specs and the current code of a child repo (read-only)
argument-hint: <alias> [capability] [--since <date|commit>]
---
Check whether the local OpenSpec specs still describe the real behaviour of the code: $ARGUMENTS

This command is READ-ONLY: do not edit, create or commit any file.

1. Resolve the repo folder from the alias in `repos.conf`. If missing or ambiguous, ask.
2. List the capabilities in `<repo>/openspec/specs/` (only the given one, if provided).
   If there are none, say so and stop.
3. Scope what may have drifted, per capability:
   - Baseline date = `--since` if given, otherwise the date of the most recent archived change
     that touched it (`openspec/changes/archive/YYYY-MM-DD-*/specs/<capability>/`).
   - Run `git -C <repo> log --since=<baseline> --format='%h %an %ad %s' --date=short` on the
     current branch and on `origin/develop` (after `git fetch`), and keep the commits that touch
     code related to the capability. Highlight commits by other authors: they never update the
     local specs.
4. For every requirement and scenario of the capability, locate the implementing code and compare.
   Classify each one:
   - ALIGNED - code matches the spec.
   - DRIFT-SPEC - the code changed on purpose (recent commit, ticket, tests updated): the spec is outdated.
   - DRIFT-CODE - the spec looks right and the code deviates: possible bug.
   - UNVERIFIABLE - implementing code not found or behaviour not determinable statically.
5. List relevant behaviour of the capability that the code has but the spec does not describe
   (UNSPECIFIED). Only list it; do not propose new requirements unless asked.
6. For capabilities involved in a contract between child repos, also compare with `contracts/`
   and `docs/integration.md` in the orchestrator and report inconsistencies.
7. Report, per capability: a table (requirement / scenario, status, evidence as `file:line`,
   related commit hash and author), then a short summary with counts.
8. Recommend next steps, without executing them:
   - DRIFT-SPEC -> a spec-only OpenSpec change `sync-<capability>-spec-<YYYYMMDD>` with MODIFIED
     requirements (openspec-new-change -> openspec-sync-specs -> openspec-archive-change, no apply).
   - DRIFT-CODE -> candidate Jira bug (ddi-feedback-ticket-triage) or ddi-bug-cycle.
   - UNSPECIFIED on an area about to change -> include it as ADDED baseline in that change.
   Ask the user before starting any of them.

Report in the user's language; any artifact created afterwards must be written in English.