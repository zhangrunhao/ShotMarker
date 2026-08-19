# ShotMarker Documentation Governance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Migrate all ShotMarker documentation into concise current facts, flat active changes, and a flat historical archive without changing product code.

**Architecture:** Create five focused current Markdown documents and retain the multi-file how-to bundle under current. Move the only approved but unimplemented design to changes, mechanically preserve every completed or superseded document in archive, and route future work through README.md and AGENTS.md.

**Tech Stack:** Markdown, Git, Node.js how-to validation, shell-based structure and link checks

**Spec:** docs/changes/2026-08-19-document-governance-spec.md

## Global Constraints

- Work directly on main; do not create a branch or worktree.
- Preserve every historical document and all uncommitted user changes.
- Keep docs/changes and docs/archive flat for Markdown files.
- Do not modify Swift, Xcode project, configuration, screenshot source, or external services.
- Record only evidence-backed test, build, release, and external-service results.
- Leave changes uncommitted unless the user explicitly requests a commit.

---

### Task 1: Create the current-document layer

**Files:**

- Create: docs/README.md
- Create: docs/current/status.md
- Create: docs/current/product.md
- Create: docs/current/architecture.md
- Create: docs/current/quality.md
- Create: docs/current/release.md

**Interfaces:**

- Consumes: current code at 9d6938f, the evidence baseline in the spec, and existing docs/current-codebase-status.md
- Produces: the stable current facts that README.md and AGENTS.md route readers to

- [x] **Step 1: Create the five focused current documents**

Write concise, non-historical facts under the exact responsibilities in the spec. Distinguish implemented behavior from confirmed but unimplemented decisions.

- [x] **Step 2: Create docs/README.md**

Link every current topic, the how-to bundle, the active voice-command spec, and explain the flat changes/archive lifecycle.

- [x] **Step 3: Check current-document scope**

Run:

~~~bash
if rg -n '最近进展|提交历史|docs/superpowers|current-codebase-status' docs/current docs/README.md; then exit 1; fi
~~~

Expected: no historical progress section, old routing path, or tool-specific directory reference.

### Task 2: Move current assets and the active design

**Files:**

- Move: docs/how-to/ to docs/current/how-to/
- Modify: docs/current/how-to/validate-shotmarker-how-to.mjs
- Move: docs/superpowers/specs/2026-07-29-ios-voice-command-marking-design.md to docs/changes/2026-07-29-ios-voice-command-marking-spec.md

**Interfaces:**

- Consumes: the self-contained relative asset paths in the current how-to bundle
- Produces: a current user guide and the only unfinished Change

- [x] **Step 1: Move the complete how-to bundle**

Move HTML, validation script, and all four assets together so relative image references remain unchanged.

- [x] **Step 2: Update validator diagnostics**

Change only the two diagnostic strings that name docs/how-to so they name docs/current/how-to.

- [x] **Step 3: Move the voice-command design**

Preserve its content and rename the -design suffix to -spec.

- [x] **Step 4: Validate the moved bundle**

Run:

~~~bash
node docs/current/how-to/validate-shotmarker-how-to.mjs
~~~

Expected: ShotMarker how-to page validation passed.

### Task 3: Preserve every historical Markdown document

**Files:**

- Move: the 23 source documents listed in the spec migration table
- Create directory: docs/archive

**Interfaces:**

- Consumes: all completed, superseded, or historical Markdown outside the active voice spec
- Produces: a flat, dated archive with unchanged historical content

- [x] **Step 1: Create docs/archive**

Create the flat archive directory without category or per-topic subdirectories.

- [x] **Step 2: Move the three root documents**

Move PRD.md, app-review-note.md, and current-codebase-status.md to their exact dated snapshot names in the spec.

- [x] **Step 3: Move the four legacy plans**

Move docs/plans files without changing their contents.

- [x] **Step 4: Move the eight generated plans**

Move each docs/superpowers/plans file and add the -plan suffix where required by the mapping.

- [x] **Step 5: Move the eight completed generated specs**

Move every completed docs/superpowers/specs file except the voice-command spec, replacing -design with -spec.

- [x] **Step 6: Verify archive coverage**

Run:

~~~bash
find docs/archive -maxdepth 1 -type f -name '*.md' | sort
~~~

Expected: exactly the 23 mapped historical files before the governance spec and plan are archived.

### Task 4: Update project routing rules

**Files:**

- Modify: AGENTS.md
- Verify: docs/README.md

**Interfaces:**

- Consumes: the completed current/changes/archive structure
- Produces: durable agent and human entry points for future tasks

- [x] **Step 1: Replace the obsolete status-page rules**

Preserve all branch and user-change protections. Replace references to docs/current-codebase-status.md with the approved current/changes/archive rules.

- [x] **Step 2: Verify routing references**

Run:

~~~bash
if rg -n 'docs/current-codebase-status|docs/superpowers' +  AGENTS.md +  docs/README.md +  docs/current +  docs/changes/2026-07-29-ios-voice-command-marking-spec.md
then
  exit 1
fi
~~~

Expected: no matches.

### Task 5: Validate the governed documentation

**Files:**

- Verify: AGENTS.md
- Verify: docs/README.md
- Verify: docs/current/**
- Verify: docs/changes/**
- Verify: docs/archive/**

**Interfaces:**

- Consumes: the complete migrated documentation tree
- Produces: evidence that structure, links, content preservation, and repository scope match the spec

- [x] **Step 1: Validate docs top-level structure**

Run:

~~~bash
find docs -mindepth 1 -maxdepth 1 -print | sort
~~~

Expected: docs/README.md, docs/archive, docs/changes, and docs/current only.

- [x] **Step 2: Validate active Change count**

Run before archiving this governance Change:

~~~bash
find docs/changes -maxdepth 1 -type f -name '*.md' | sort
~~~

Expected: voice-command spec plus this governance spec and plan.

- [x] **Step 3: Validate Markdown links**

Resolve every relative Markdown link in AGENTS.md, docs/README.md, docs/current, and docs/changes; fail if any local target is missing.

- Use a read-only Node script to collect Markdown files, extract local link targets, resolve them relative to each source file, and exit nonzero for every missing path.
- Ignore HTTP(S), mailto, and same-page anchor targets.

- [x] **Step 4: Validate file preservation**

Parse the 23 source/destination rows from the spec migration table. For each row, compare the destination bytes with git show HEAD:<source>. Compare the moved voice spec the same way.

Expected: all 24 Markdown comparisons are byte-identical. Only the two diagnostic strings in the moved how-to validator may differ inside mechanically moved content.

- [x] **Step 5: Validate repository scope**

Run:

~~~bash
git diff --check
git status --short
git diff --name-only
~~~

Expected: no whitespace errors; changes are limited to AGENTS.md and documentation paths.

### Task 6: Archive this governance Change

**Files:**

- Move: docs/changes/2026-08-19-document-governance-spec.md to docs/archive/2026-08-19-document-governance-spec.md
- Move: docs/changes/2026-08-19-document-governance-plan.md to docs/archive/2026-08-19-document-governance-plan.md

**Interfaces:**

- Consumes: a fully verified documentation migration
- Produces: a completed governance record in archive while the unfinished voice-command spec remains in changes

- [x] **Step 1: Move the governance spec and plan**

Move both files into the flat archive without changing their names.

- [x] **Step 2: Run final verification**

Run:

~~~bash
node docs/current/how-to/validate-shotmarker-how-to.mjs
git diff --check
git status --short --branch
find docs/changes -maxdepth 1 -type f -name '*.md' -print
~~~

Expected: how-to validation passes, diff check passes, docs/changes contains only the voice-command spec, and no product-code file changed.

- [x] **Step 3: Mark every completed plan checkbox**

After every verification has passed, replace each completed - [ ] marker in the archived plan with - [x].

Run:

~~~bash
if rg -n '^- \[ \]' docs/archive/2026-08-19-document-governance-plan.md; then exit 1; fi
~~~

Expected: no unchecked steps remain.
