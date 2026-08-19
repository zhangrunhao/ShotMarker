# AGENTS.md

## Development Rules

- This is a personal project. Do all development directly on `main`.
- Do not create or use git worktrees for this project.
- Do not create feature branches unless the user explicitly asks for one.
- Before editing files, confirm the current branch is `main`.
- Never discard or overwrite uncommitted user changes without explicit approval.

## Documentation Governance

- Start at `docs/README.md`, read the relevant files under `docs/current/`, and check `docs/changes/` for an existing Change on the same topic.
- Treat `docs/current/` as the concise source of current project facts and effective decisions.
- Keep current documents clear, evidence-backed, suitable for human readers, and free of development history. Explicitly distinguish implementation facts from effective decisions.
- Keep each current document at or below 300 lines. If it grows beyond that limit, split it according to topic boundary rather than compressing paragraphs.
- Give current documents stable, undated, short names made from common words; avoid complex terms, long combinations, and unnecessary abbreviations.
- Determine implementation, build, release, and external-service facts from current code, tests, builds, and fresh verification. Do not infer current implementation from decisions or old documents.
- Treat effective decisions, contracts, and policies recorded in `docs/current/` as normative. Current implementation does not silently cancel them.
- If implementation conflicts with an effective decision, record both the decision and the verified implementation gap in current, and handle the fix as an active Change.
- Store active change specifications and plans as flat files in `docs/changes/` using:
  - `YYYY-MM-DD-topic-spec.md`
  - `YYYY-MM-DD-topic-plan.md`
- After implementing and verifying a Change, update the affected `docs/current/` files first, then move its completed spec and plan into the `docs/archive/YYYY-MM/` directory matching the files' date prefix.
- Store completed discussions, investigations, root causes, historical validations, superseded documents, and other finished records as dated files in the matching `docs/archive/YYYY-MM/` directory.
- Create archive month directories only when needed. Their names must match each contained file's `YYYY-MM` prefix, and they must not contain deeper topic- or record-type directories.
- Record only evidence-backed test, build, release, and external-service results.
- Never present changing external state as current unless it was checked in the current task; otherwise include the last verified date or mark it unverified.
- Pure formatting or comment-only changes that do not alter project state do not require current-document updates.

## Public and Private Boundaries

- Keep public product behavior, code architecture, tests, build results, data contracts, and privacy boundaries in this repository.
- When `docs/private.local/` is available, treat `docs/private.local/shotmarker/` as the private source for App Store Connect, TestFlight, signed Archive, real-device, Analytics production, and GlitchTip project verification facts.
- Public documentation must remain complete without the private repository.
- Keep one authoritative current source for each fact across repositories; other repositories may retain only the necessary summary or link.
- `docs/private.local/` is an independent Git repository. Check, commit, and push it separately from this public repository.
- Synchronize the private repository before editing; never overwrite a dirty private working copy.
- Never store passwords, private keys, tokens, access keys, database credentials, Apple API keys, actual `.env` values, raw user identifiers, tester emails, or device UDIDs in either documentation repository.
