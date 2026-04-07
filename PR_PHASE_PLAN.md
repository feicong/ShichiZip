# PR-Sized Refactor Plan

This file tracks the worker/session/UI refactor as reviewable pull requests.

Status:
- Completed on current branch: Phases 1-5

## Ground Rules

- One operation family per PR.
- Temporary adapters are allowed if they reduce risk.
- Callback code in `Bridge/` should stop talking to UI directly.
- User-visible behavior should stay stable unless a PR is explicitly about behavior changes.
- The Windows 7-Zip interaction model remains the spec for threading, timing, and prompt ownership.

## Phase 1: Session Foundation

Goal: introduce a non-UI operation session that owns progress state, cancellation checks, and prompt request plumbing while keeping the current dialog/progress behavior through adapters.

Scope:
- add `SZOperationSession` as the bridge-safe state and request object
- route open/extract/update callbacks through the session instead of calling progress delegates or dialog presenters directly
- keep `ProgressDialogController` and `SZDialogPresenter` as compatibility handlers behind the session

Out of scope:
- timer-driven UI coordinator
- new async Swift APIs
- behavior changes to progress timing or prompt flow

Merge criteria:
- no user-visible regression in password prompts, overwrite prompts, cancel behavior, or progress windows
- build stays green
- callbacks no longer import or call UI types directly, aside from compatibility setup in shared bridge helpers

## Phase 2: Archive Open Vertical Slice

Goal: migrate archive open to a session-driven coordinator so open progress and password prompts follow the Windows wait-dialog ownership model.

Scope:
- add a main-thread coordinator that observes an operation session snapshot
- move archive-open wait-mode visibility and password prompt sequencing onto that coordinator
- remove archive-open specific UI work from the open callback path

Out of scope:
- extract/test/compress migration
- broader call-site cleanup

Merge criteria:
- direct encrypted open shows the right wait/progress behavior
- the file-manager pane commits archive state only after success
- password prompting during open no longer depends on callback-to-UI calls

## Phase 3: Extract/Test Migration

Goal: move extract/test onto the same session/coordinator pattern.

Scope:
- port extract progress snapshots, cancel checks, overwrite prompts, and password requests to the session layer
- remove remaining extract/test callback UI calls
- keep password reuse semantics on `SZArchive`

Out of scope:
- compress/copy/move migration

Merge criteria:
- extract/test use the shared session pipeline end-to-end
- overwrite and password prompts still behave like the current app
- bridge callbacks remain non-UI

## Phase 4: Compress And File Operations

Goal: replace the ad hoc progress/dialog orchestration in compress, copy, and move flows with the shared coordinator.

Scope:
- migrate compress progress to the shared session/coordinator path
- migrate file-manager copy/move progress and overwrite prompts to the same model
- reduce duplicated progress-window setup in Swift call sites

Out of scope:
- API cleanup and async wrappers

Merge criteria:
- compress/copy/move no longer create bespoke progress/prompt plumbing at each call site
- the shared coordinator covers all long-running file-manager operations

## Phase 5: Boundary Cleanup And Async API

Goal: finish the separation so bridge code exposes only bridge-safe state and request surfaces, with Swift async wrappers at the top boundary.

Scope:
- remove bridge imports of dialog presenter types from headers
- add async Swift runners around blocking archive operations where helpful
- tighten public interfaces around session snapshots and request handling

Out of scope:
- unrelated UI redesign

Merge criteria:
- bridge headers are UI-agnostic
- Swift call sites can opt into async wrappers without changing lower-level ownership
- the session/coordinator split is the default path for new work