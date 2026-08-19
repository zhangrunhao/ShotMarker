# Filter Unusable Training Videos Design

Date: 2026-06-14
Status: Approved for implementation

## Goal

After the user selects training videos, ShotMarker should not show or use videos that cannot produce clips for the selected training session. The highlight generation flow should only work with usable videos.

## Current Behavior

`TrainingSessionHighlightView.loadSelectedVideos(from:)` loads every selected `PhotosPickerItem` into `SelectedTrainingVideo`. If any video fails to load, the whole selection fails. If a loaded video does not cover any marker, it still contributes to the selected video count even though it cannot generate clips.

## Desired Behavior

When the user finishes selecting videos:

- Load selected videos one by one.
- Keep only videos that can be read and can produce at least one clip for the current training session.
- Filter out videos that are not downloaded or otherwise cannot be read without waiting on network download.
- Filter out videos that lack a recorded start time, have invalid duration, or do not cover any marker in the current session.
- Do not add filtered videos to `selectedVideos`.
- Show one summary alert if any selected videos were filtered.
- If all selected videos are filtered, clear the picker selection and show an actionable message.

The UI should only display the usable videos count and clip coverage based on retained videos.

## Availability Rules

A video is usable when all of these are true:

- Its metadata can be loaded locally enough to obtain recorded start time and duration.
- Its duration is finite and greater than zero.
- At least one `ShotMarkerEvent.markedAt` falls within `[recordedStartAt, recordedEndAt]`.

The marker coverage check should be a lightweight date-range check, not a full highlight clip planning pass.

## User Feedback

If some videos are usable and some are filtered, keep the usable videos and show a summary alert such as:

`已忽略 2 个不可用视频。请确认视频已下载、包含拍摄时间，并覆盖本次训练时间。`

If no videos are usable, clear selection and show:

`没有可用于本次训练的视频。请确认视频已下载、包含拍摄时间，并覆盖本次训练时间。`

The flow should avoid showing each skipped video individually.

## Logging

Keep existing successful load logging for retained videos. Add summary logging for filtered videos with counts only, avoiding file paths, file names, or raw Photos identifiers.

Useful context:

- requested item count
- retained video count
- filtered video count
- failed-to-load count
- no-marker-coverage count

## Testing

Add focused tests for the pure availability helper:

- Keeps a video whose time range covers a marker.
- Filters a video whose time range covers no markers.
- Treats boundary markers at video start and end as covered.

If the loading flow is refactored into a testable helper, add tests that mixed usable and unusable videos return only usable videos and report accurate counts.

## Out of Scope

- Building a local video library.
- Persisting selected videos.
- Displaying unavailable videos in a separate list.
- Pre-filtering the system Photos picker before the user selects videos.
- Automatically downloading iCloud videos.
