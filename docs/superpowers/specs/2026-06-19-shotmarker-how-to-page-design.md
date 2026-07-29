# ShotMarker How-To Page Design

## Goal

Create a local static HTML page that explains how to use ShotMarker in simple Chinese, with real product screenshots and a clean product-page feel.

## Audience

People who have not used ShotMarker before and need to understand the basic flow quickly.

## Page Direction

Use the selected direction: product imagery plus three operation steps. The page should look closer to a concise product guide than a long manual.

## Content

- Hero: `ShotMarker`, one short sentence, Apple Watch and iPhone product screenshots.
- Step 1: use Apple Watch to start training and mark shots.
- Step 2: open the matching training record on iPhone.
- Step 3: choose training videos and generate the highlight.

## Assets

Use existing repository screenshots:

- `app-store-screenshots/upload-ready/apple-watch-49mm.jpg`
- `AppStoreScreenshots/2026-06-16-iphone-65/01-training-records.png`
- `AppStoreScreenshots/2026-06-16-iphone-65/03-highlight-ready.png`
- `AppStoreScreenshots/2026-06-16-iphone-65/04-highlight-generate.png`

Copy them into the how-to page asset directory so the page can be moved later with minimal path changes.

## Output

- `docs/how-to/shotmarker-how-to.html`
- `docs/how-to/assets/*`
- A small validation script that checks the local page structure and required copy.

## Constraints

- Static HTML only.
- No external network dependency.
- Chinese copy should be short and direct.
- Do not modify app source code.
- Do not touch existing uncommitted user changes.
