# ShotMarker Analytics Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing `zhangrh.shop` first-party Track pipeline so it accepts and aggregates ShotMarker events, and publish an accurate ShotMarker privacy disclosure without changing the current single-JSONL storage model.

**Architecture:** Nginx continues to accept `GET /track` and append schema-v1 records to one `events.jsonl`. The Node backend only adds `shotmarker` to its validation and query allowlists. The ShotMarker public privacy page and Track operator documentation describe the four fixed native events, the random installation identifier, and the current no-fixed-expiration retention policy.

**Tech Stack:** Node.js 24, Express 5, Node test runner, TypeScript 5.9, React content data, npm.

---

## Scope and repository boundary

This plan implements the server and public-policy half of the approved design in
`/Users/runhaozhang/Documents/project/ShotMarker/docs/superpowers/specs/2026-08-16-shotmarker-analytics-design.md`.

All implementation commands in this plan run in:

```text
/Users/runhaozhang/Documents/project/zhangrh.shop
```

The plan intentionally does not:

- change Nginx `/track` ingestion;
- add Track logrotate, automatic deletion, a database, or a fixed retention window;
- expose raw `device_id` values in the public summary;
- deploy Backend or Frontend without a separate explicit publishing authorization;
- claim to complete the separate GlitchTip crash-reporting disclosure; preserve that disclosure if it is present when this plan runs.

## File map

- Modify: `backend/projects/track.js`
- Modify: `backend/projects/track-query.js`
- Modify: `backend/tools/track-route.test.mjs`
- Modify: `backend/tools/track-query.test.mjs`
- Modify: `frontend/project/shotmarker/content.ts`
- Modify: `frontend/project/shotmarker/content.test.ts`
- Modify: `frontend/docs/track.md`
- Modify: `RUNBOOK.md`

### Task 0: Protect the current single-JSONL and GlitchTip work

- [ ] **Step 1: Confirm the repository and branch**

Run:

```bash
pwd
git branch --show-current
git status --short
```

Expected:

- `pwd` is `/Users/runhaozhang/Documents/project/zhangrh.shop`;
- the branch is `main`;
- the worktree is clean before this plan starts.

The August 16 single-JSONL documentation edits must already be committed. If a GlitchTip privacy-policy edit is in progress when this plan runs, complete and commit it first; do not stash, discard, or rewrite it to make the worktree clean. If no GlitchTip policy edit exists yet, analytics implementation may proceed, but the release handoff must continue to flag that separate disclosure as incomplete.

- [ ] **Step 2: Verify the accepted storage baseline**

Run:

```bash
rg -n "single|单一|32 MiB|64 MiB|不自动|does not automatically" \
  frontend/docs/track.md RUNBOOK.md docs/deploy/README.md
```

Expected: the documents describe one append-only `events.jsonl`, no Track-specific automatic cleanup, review at `32 MiB`, and the Backend `64 MiB` decoded-input limit.

- [ ] **Step 3: Record the preflight result**

If the branch is not `main`, the worktree is still dirty, or the accepted storage wording is absent, stop and reconcile that state with the owner. Do not create a branch or worktree for this personal project.

### Task 1: Allow `shotmarker` in the summary route and parser

**Files:**

- Modify: `backend/tools/track-route.test.mjs`
- Modify: `backend/tools/track-query.test.mjs`
- Modify: `backend/projects/track.js`
- Modify: `backend/projects/track-query.js`

- [ ] **Step 1: Add a failing route allowlist test**

In `accepts only the exact lowercase summary route and valid query values`, append this request after the existing `hub` and `cardgame` assertions:

```js
  const shotMarkerResponse = await fetch(
    `${origin}/api/track/summary?days=30&project=shotmarker`,
  )
  assert.equal(shotMarkerResponse.status, 200)
  assert.equal(calls.at(-1).project, 'shotmarker')
```

Add a separate error-contract test so the public validation message lists every accepted value:

```js
test('documents every accepted project when project validation fails', async (t) => {
  const origin = await startApp(t)

  const response = await fetch(`${origin}/api/track/summary?project=all`)

  assert.equal(response.status, 400)
  assert.deepEqual(await response.json(), {
    error: {
      code: 'invalid_project',
      message: 'project must be hub, cardgame, or shotmarker',
    },
  })
})
```

- [ ] **Step 2: Add a failing parser and aggregation test**

Append this test to `backend/tools/track-query.test.mjs` near the existing valid-record aggregation tests:

```js
test('summarizes ShotMarker events by installation without exposing identifiers', async (t) => {
  const logDir = await createLogDir(t)
  await writeCurrent(
    logDir,
    jsonl(
      record({
        request_id: requestId(101),
        project: 'shotmarker',
        device_id: 'Shot00000001',
        event: 'app_launch',
        params_encoded: encodeParams({}),
      }),
      record({
        request_id: requestId(102),
        project: 'shotmarker',
        device_id: 'Shot00000001',
        event: 'training_sync_succeeded',
        params_encoded: encodeParams({}),
      }),
      record({
        request_id: requestId(103),
        project: 'shotmarker',
        device_id: 'Shot00000002',
        event: 'app_launch',
        params_encoded: encodeParams({}),
      }),
    ),
  )

  const result = await summarizeTrackEvents({
    logDir,
    days: 2,
    project: 'shotmarker',
    now: FIXED_NOW,
  })

  assert.deepEqual(result.filter, { project: 'shotmarker' })
  assert.equal(result.totals.events, 3)
  assert.equal(result.totals.devices, 2)
  assert.deepEqual(result.projects, [
    { project: 'shotmarker', events: 3, devices: 2 },
  ])
  assert.deepEqual(result.event_breakdown, [
    { project: 'shotmarker', event: 'app_launch', events: 2, devices: 2 },
    {
      project: 'shotmarker',
      event: 'training_sync_succeeded',
      events: 1,
      devices: 1,
    },
  ])
  assert.deepEqual(result.page_breakdown, [])
  assert.deepEqual(result.button_breakdown, [])
  assert.doesNotMatch(JSON.stringify(result), /Shot0000000[12]/)
})
```

The two fixture IDs are exactly 12 alphanumeric characters, matching the existing schema-v1 validator.

- [ ] **Step 3: Run the focused tests and verify RED**

Run:

```bash
node --test \
  --test-name-pattern='ShotMarker|valid query values|documents every accepted project' \
  backend/tools/track-route.test.mjs \
  backend/tools/track-query.test.mjs
```

Expected: failures because the route rejects `project=shotmarker`, the parser rejects ShotMarker records, and the error message still lists only the two web projects.

- [ ] **Step 4: Extend both production allowlists**

In both `backend/projects/track.js` and `backend/projects/track-query.js`, use the same allowlist:

```js
const PROJECTS = new Set(['hub', 'cardgame', 'shotmarker'])
```

In `backend/projects/track.js`, update only the project validation message:

```js
  invalid_project: 'project must be hub, cardgame, or shotmarker',
```

Do not loosen `DEVICE_ID_PATTERN`, `EVENT_PATTERN`, query ranges, size limits, or returned fields.

- [ ] **Step 5: Run focused and backend tests and verify GREEN**

Run:

```bash
node --test \
  --test-name-pattern='ShotMarker|valid query values|documents every accepted project' \
  backend/tools/track-route.test.mjs \
  backend/tools/track-query.test.mjs
npm --prefix backend test
```

Expected: all selected tests pass, then the full Backend suite passes.

- [ ] **Step 6: Commit the backend change**

Run:

```bash
git add \
  backend/projects/track.js \
  backend/projects/track-query.js \
  backend/tools/track-route.test.mjs \
  backend/tools/track-query.test.mjs
git diff --cached --check
git commit -m "feat: 支持ShotMarker埋点查询"
```

Expected: one commit containing only the four Backend files.

### Task 2: Disclose first-party analytics on the ShotMarker privacy page

**Files:**

- Modify: `frontend/project/shotmarker/content.test.ts`
- Modify: `frontend/project/shotmarker/content.ts`

- [ ] **Step 1: Add a failing disclosure contract test**

Add `EFFECTIVE_DATE` and `LAST_UPDATED` to the existing import from `./content`, then append:

```ts
test("privacy page discloses ShotMarker's first-party product analytics", () => {
  const text = pageText(privacyPage);

  assert.equal(EFFECTIVE_DATE, "August 16, 2026");
  assert.equal(LAST_UPDATED, "2026-08-16");
  assert.match(text, /random 12-character installation identifier/);
  assert.match(text, /app_launch/);
  assert.match(text, /training_sync_succeeded/);
  assert.match(text, /highlight_generate_succeeded/);
  assert.match(text, /highlight_save_succeeded/);
  assert.match(text, /empty parameter object/);
  assert.match(text, /does not have a fixed automatic expiration period/);
  assert.match(text, /32 MiB/);
  assert.match(text, /does not immediately delete prior server events/);
  assert.match(text, /not used for advertising or cross-company tracking/);
  assert.match(
    text,
    /do not include training records, marker timestamps, videos, HealthKit data, or diagnostic logs/,
  );
});
```

- [ ] **Step 2: Run the content test and verify RED**

Run:

```bash
./frontend/node_modules/.bin/tsx \
  --test \
  --test-concurrency=1 \
  frontend/project/shotmarker/content.test.ts
```

Expected: the new test fails because the effective date and analytics disclosure have not been updated.

- [ ] **Step 3: Update the policy date and scope**

At the top of `frontend/project/shotmarker/content.ts`, set:

```ts
export const EFFECTIVE_DATE = "August 16, 2026";
export const LAST_UPDATED = "2026-08-16";
```

Extend the English and Chinese `scope` paragraphs so they also name first-party product analytics. Preserve any GlitchTip/crash-reporting text already present in the clean preflight baseline.

- [ ] **Step 4: Add the exact first-party analytics disclosure**

Inside the `data` section, insert these blocks after `WatchConnectivity` and before local diagnostic/crash-reporting blocks:

```ts
        { kind: "heading", text: "First-Party Product Analytics" },
        {
          kind: "paragraph",
          text: "On iPhone Release builds, ShotMarker sends four first-party product analytics events to zhangrh.shop: app_launch, training_sync_succeeded, highlight_generate_succeeded, and highlight_save_succeeded. Each event includes its name, client and server timestamps, the project name, an empty parameter object, and a random 12-character installation identifier stored in UserDefaults. The identifier is linked only to the current app installation and is used to count approximate unique installations.",
        },
        {
          kind: "paragraph",
          text: "These events do not include training records, marker timestamps, videos, HealthKit data, or diagnostic logs. They also do not include an advertising identifier, device model, or operating-system version. The events are used only for product analytics, are not used for advertising or cross-company tracking, and are not shared with third-party analytics providers.",
        },
        {
          kind: "paragraph",
          className: "language-block",
          text: "在 iPhone Release 构建中，ShotMarker 会向 zhangrh.shop 发送四个一方产品分析事件：app_launch、training_sync_succeeded、highlight_generate_succeeded 和 highlight_save_succeeded。每条事件包含事件名、客户端与服务器时间、项目名、空参数对象，以及保存在 UserDefaults 中的随机 12 位安装标识。该标识只关联当前 App 安装，用于估算独立安装数。事件不包含训练记录、打点时间、视频、HealthKit 数据或诊断日志，也不包含广告标识、设备型号或系统版本。事件仅用于产品分析，不用于广告或跨公司跟踪，也不会共享给第三方分析服务商。",
        },
```

Keep the existing statements that ShotMarker has no account, no ads, no third-party analytics SDK, and does not upload videos or training records. Those statements remain accurate.

- [ ] **Step 5: Add the exact server-retention disclosure**

Append these blocks to the existing `retention` section without replacing the local-data paragraphs:

```ts
        {
          kind: "paragraph",
          text: "First-party analytics events are stored on the developer's server in a single append-only events.jsonl file. The current implementation does not have a fixed automatic expiration period. The storage approach will be reevaluated when the file reaches 32 MiB, before the Backend query limit of 64 MiB is reached. Deleting ShotMarker resets the local installation identifier but does not immediately delete prior server events. Public analytics summaries do not expose raw installation identifiers.",
        },
        {
          kind: "paragraph",
          className: "language-block",
          text: "一方分析事件保存在开发者服务器的单一追加式 events.jsonl 文件中。当前实现没有固定的自动过期时间；文件达到 32 MiB 时会重新评估存储方案，并在 Backend 的 64 MiB 查询上限前完成调整。删除 ShotMarker 会重置本地安装标识，但不会立即删除此前已写入服务器的事件。公开分析汇总不会返回原始安装标识。",
        },
```

- [ ] **Step 6: Run focused policy checks and verify GREEN**

Run:

```bash
./frontend/node_modules/.bin/tsx \
  --test \
  --test-concurrency=1 \
  frontend/project/shotmarker/content.test.ts
npm --prefix frontend run typecheck
```

Expected: the ShotMarker content tests and the full Frontend typecheck pass.

- [ ] **Step 7: Commit the privacy disclosure**

Run:

```bash
git add \
  frontend/project/shotmarker/content.ts \
  frontend/project/shotmarker/content.test.ts
git diff --cached --check
git commit -m "docs: 更新ShotMarker匿名分析隐私说明"
```

Expected: one commit containing only the ShotMarker public-policy content and its contract test.

### Task 3: Document the native event contract and operator query

**Files:**

- Modify: `frontend/docs/track.md`
- Modify: `RUNBOOK.md`

- [ ] **Step 1: Update the shared field table without describing ShotMarker as a browser client**

Keep the existing Hub/Cardgame browser description, then extend the field table to say:

```md
| `project` | string | `hub`、`cardgame` 或 `shotmarker` |
| `device_id` | string | 12 位字母数字标识；网页端复用 localStorage/Cookie，ShotMarker 复用当前安装的 UserDefaults 随机值 |
```

Under the browser `Image` transport description, add:

```md
ShotMarker iPhone Release 构建使用临时 `URLSession` 向同一个 HTTPS 地址发送 GET 请求；Debug、测试、非 iPhone 平台和 Apple Watch 不发送。原生请求同样使用 schema v1，不设置持久 Cookie 或响应缓存。
```

- [ ] **Step 2: Add the four-event ShotMarker section**

Insert this section before `持久化与查询边界`:

```md
## ShotMarker iPhone

ShotMarker 只在业务结果已经成功时发送以下事件，所有事件固定使用 `params={}`：

| event | 成功语义 |
| --- | --- |
| `app_launch` | iPhone Release App 进程启动并完成埋点依赖组装 |
| `training_sync_succeeded` | Watch payload 已成功导入 iPhone 本地存储；发生在 ACK 之前 |
| `highlight_generate_succeeded` | 集锦任务最终状态为 completed，输出文件已进入正式任务路径 |
| `highlight_save_succeeded` | 视频已写入系统相册，保存时间已写入并持久化 |

ShotMarker 不上传训练 ID、训练时间、打点时间、视频信息、任务 ID、错误、诊断日志、系统版本或设备型号。事件失败时直接丢弃，不缓存、不批量、不重试，也不影响业务成功结果。
```

- [ ] **Step 3: Update query wording and the operator example**

Change the documented query union to:

```text
GET /api/track/summary?days=<1-90>&project=<hub|cardgame|shotmarker>
```

Describe `devices` as approximate browser/device installations rather than only browser devices. Keep the explicit statement that raw identifiers are not returned and input is untrusted.

In `RUNBOOK.md`, change the project-filtered example to:

```bash
curl --fail-with-body \
  'https://zhangrh.shop/api/track/summary?days=30&project=shotmarker' \
  --output track-summary.json
```

Do not change the single-file, no-automatic-cleanup, `32 MiB` review, or `64 MiB` query-limit wording.

- [ ] **Step 4: Verify the documentation contract**

Run:

```bash
rg -n "shotmarker|app_launch|training_sync_succeeded|highlight_generate_succeeded|highlight_save_succeeded" \
  frontend/docs/track.md RUNBOOK.md
rg -n "单一|32 MiB|64 MiB|不自动" \
  frontend/docs/track.md RUNBOOK.md docs/deploy/README.md
```

Expected:

- all four ShotMarker events and the `project=shotmarker` query are present;
- the accepted single-JSONL storage decision is still present;
- no document claims a fixed automatic retention period.

- [ ] **Step 5: Commit the protocol documentation**

Run:

```bash
git add frontend/docs/track.md RUNBOOK.md
git diff --cached --check
git commit -m "docs: 记录ShotMarker埋点协议"
```

Expected: one documentation-only commit.

### Task 4: Run repository-wide verification

- [ ] **Step 1: Confirm only the intended commits and files changed**

Run:

```bash
git status --short
git log --oneline -3
git diff HEAD~3..HEAD --stat
```

Expected: the worktree is clean and the last three commits correspond to Backend allowlisting, privacy disclosure, and Track documentation.

- [ ] **Step 2: Run the full repository gate**

Run:

```bash
npm run check
```

Expected: automation tests, Frontend tests, Backend tests, lint, TypeScript checks, and all Frontend builds pass.

- [ ] **Step 3: Inspect the built ShotMarker privacy page**

Run:

```bash
rg -n "First-Party Product Analytics|random 12-character|32 MiB" \
  frontend/dist/shotmarker
```

Expected: the generated ShotMarker site contains the analytics and retention disclosure.

### Task 5: Prepare—but do not execute—the release handoff

- [ ] **Step 1: Record the Backend verification query**

After a separately authorized Backend publish, the read-only production check is:

```bash
curl --fail-with-body \
  'https://zhangrh.shop/api/track/summary?days=1&project=shotmarker'
```

Expected: HTTP 200 with `filter.project` equal to `shotmarker`, aggregate counts only, and no raw `device_id`.

- [ ] **Step 2: Record the Frontend verification URL**

After a separately authorized Frontend publish, inspect:

```text
https://zhangrh.shop/shotmarker/privacy
```

Expected: the updated effective date, first-party analytics disclosure, and no-fixed-expiration retention disclosure are visible in both English and Chinese.

Before publishing a policy for a build that already includes GlitchTip, separately verify that the same page also discloses automatic crash/error reporting. This analytics plan does not supply or test that wording.

- [ ] **Step 3: Stop at the publishing boundary**

Do not run `npm run publish`, `npm --prefix backend run publish`, or any server mutation as part of this implementation plan unless the user explicitly authorizes deployment. Hand the clean, verified commits back with the two production verification checks above.
