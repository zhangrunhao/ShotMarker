# ShotMarker How-To Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local static HTML page that explains ShotMarker usage with concise Chinese text and real screenshots.

**Architecture:** The page lives under `docs/how-to/` with copied local image assets. A Node validation script checks required text, local asset references, and no external dependencies.

**Tech Stack:** Static HTML, CSS, repository screenshot assets, Node.js built-in modules.

---

### Task 1: Validation Script

**Files:**
- Create: `docs/how-to/validate-shotmarker-how-to.mjs`

- [ ] **Step 1: Create the validation script**

The script should fail before the HTML exists and later validate:

- `shotmarker-how-to.html` exists.
- Required step copy is present.
- Referenced image files exist locally.
- No `http://` or `https://` references are present.

- [ ] **Step 2: Run validation and verify RED**

Run: `node docs/how-to/validate-shotmarker-how-to.mjs`

Expected: failure because `docs/how-to/shotmarker-how-to.html` does not exist.

### Task 2: Static Page and Assets

**Files:**
- Create: `docs/how-to/shotmarker-how-to.html`
- Copy: `docs/how-to/assets/apple-watch-49mm.jpg`
- Copy: `docs/how-to/assets/iphone-training-records.png`
- Copy: `docs/how-to/assets/iphone-highlight-ready.png`
- Copy: `docs/how-to/assets/iphone-highlight-generate.png`

- [ ] **Step 1: Copy image assets**

Copy selected screenshots into `docs/how-to/assets/` so the HTML is self-contained within the folder.

- [ ] **Step 2: Create the HTML**

The HTML should use a product-style hero, a three-step guide, and local image references only.

- [ ] **Step 3: Run validation and verify GREEN**

Run: `node docs/how-to/validate-shotmarker-how-to.mjs`

Expected: validation passes.

### Task 3: Browser Verification

**Files:**
- Read: `docs/how-to/shotmarker-how-to.html`

- [ ] **Step 1: Open via a local static server**

Run: `python3 -m http.server 8765 --directory docs/how-to`

- [ ] **Step 2: Capture screenshots with Playwright**

Open `http://localhost:8765/shotmarker-how-to.html` at desktop and mobile widths. Confirm the page is nonblank, images load, and text does not overlap.
