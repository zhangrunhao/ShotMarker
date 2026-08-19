# AGENTS.md

## Development Rules

- This is a personal project. Do all development directly on `main`.
- Do not create or use git worktrees for this project.
- Do not create feature branches unless the user explicitly asks for one.
- Before editing files, confirm the current branch is `main`.
- Never discard or overwrite uncommitted user changes without explicit approval.

## Documentation Governance

- Start at `docs/README.md`, then read the relevant files under `docs/current/`.
- Treat `docs/current/` as the concise source of current project facts and effective decisions.
- Prefer current code and fresh verification over documentation when resolving conflicts.
- Keep current documents clear, evidence-backed, and free of development history.
- Store active change specifications and plans as flat files in `docs/changes/` using:
  - `YYYY-MM-DD-topic-spec.md`
  - `YYYY-MM-DD-topic-plan.md`
- After implementing and verifying an important feature or bug fix, update the affected `docs/current/` files first, then move its completed spec and plan into `docs/archive/`.
- Store completed discussions, investigations, root causes, historical validations, superseded documents, and other finished records as flat dated files in `docs/archive/`.
- Do not create per-topic directories for one or two Markdown files in `docs/changes/` or `docs/archive/`.
- Record only evidence-backed test, build, release, and external-service results.
- Never present changing external state as current unless it was checked in the current task; otherwise include the last verified date or mark it unverified.
