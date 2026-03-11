# Menubar Todo Pi Design

## Summary

This design builds a native macOS menubar app with a normal standalone window as the main workspace. The window combines two surfaces: a todo workspace for multiple lists or projects and a chat panel for talking to pi. The app, not pi, owns the todo domain. Swift code manages models, validation, persistence, and window state. pi runs as a background child process that is launched on first chat use.

The key design choice is a narrow boundary between the app and pi. pi can reason about user requests and ask for explicit todo operations, but it cannot write storage directly. All todo mutations flow through the app-owned command layer, then through an atomic JSON repository. That keeps the UI, persistence, and assistant behavior decoupled, which makes the first version simple enough to build while leaving room for richer local-agent features later.

## Definition of Done
- A native macOS menubar app exists that opens a normal standalone window when clicked.
- The app stores todo data locally in a simple file format, likely JSON, and supports multiple lists/projects.
- The main window shows the todo lists and includes a chat textbox for talking to pi.
- In v1, the app launches pi on first chat use, keeps it running in the background, and pi can directly add, edit, and complete todos through the app.

## Acceptance Criteria

### menubar-todo-pi.AC1: Menubar entry opens the app window
- **menubar-todo-pi.AC1.1 Success:** Launching the app shows a macOS menubar item.
- **menubar-todo-pi.AC1.2 Success:** Clicking the menubar item opens the main app window if it is closed.
- **menubar-todo-pi.AC1.3 Success:** Clicking the menubar item focuses the existing main window instead of creating duplicate windows.

### menubar-todo-pi.AC2: Local todo data persists in JSON across launches
- **menubar-todo-pi.AC2.1 Success:** The app loads multiple lists or projects from a local JSON file into the app-owned store.
- **menubar-todo-pi.AC2.2 Success:** Creating, updating, completing, or moving a todo updates in-memory state and persists to the JSON file.
- **menubar-todo-pi.AC2.3 Success:** Restarting the app restores the last successfully saved lists and todos.
- **menubar-todo-pi.AC2.4 Failure:** If the JSON file is missing or invalid, the app reports the problem and falls back to a safe recoverable state instead of crashing.
- **menubar-todo-pi.AC2.5 Failure:** Failed saves do not leave a partially written JSON file as the authoritative store.

### menubar-todo-pi.AC3: Main window shows todos and chat together
- **menubar-todo-pi.AC3.1 Success:** The main window shows list or project navigation and the todos for the selected list.
- **menubar-todo-pi.AC3.2 Success:** The main window includes a visible chat transcript area and a text input for talking to pi.
- **menubar-todo-pi.AC3.3 Success:** Switching lists updates the visible todo set without losing the current chat session state.

### menubar-todo-pi.AC4: pi launches on first chat use and can manage todos through the app
- **menubar-todo-pi.AC4.1 Success:** Sending the first chat message launches pi in the background if it is not already running.
- **menubar-todo-pi.AC4.2 Success:** The UI shows pi connection state such as starting, ready, busy, or unavailable.
- **menubar-todo-pi.AC4.3 Success:** pi can create, update, complete, and move todos only through explicit app RPC tools.
- **menubar-todo-pi.AC4.4 Success:** Successful pi-driven mutations return structured results that the app uses to update UI state and chat confirmations.
- **menubar-todo-pi.AC4.5 Failure:** Invalid or unsupported pi tool calls are rejected with typed errors and do not mutate stored data.
- **menubar-todo-pi.AC4.6 Failure:** If pi fails to start or disconnects, the app reports the failure and remains usable for viewing stored todos.

## Glossary

- **App-owned domain**: The design choice where the macOS app owns todo models, validation, persistence, and command handling instead of delegating those responsibilities to pi.
- **`NSStatusItem`**: The AppKit API used to place an item in the macOS menubar.
- **RPC**: Remote procedure call. Here it means the typed request and response boundary between the app and the background pi process.
- **Stable ID**: A persistent identifier for a list or todo that does not depend on its visible title or position.
- **`TodoCommandService`**: The app layer that validates and applies todo mutations such as create, update, complete, and move.
- **`JSONTodoRepository`**: The persistence component that loads and atomically saves the local JSON todo document.
- **`PiSessionManager`**: The component that launches, monitors, and reconnects the background pi process.

## Architecture

This app uses an app-owned domain with pi as a background assistant. The macOS app owns todo models, JSON persistence, validation, and window state. pi is a child process launched on first chat use. It never writes the todo file directly. It can only read or mutate todos through explicit RPC tools exposed by the app.

Planned project structure:
- `TodoPi.xcodeproj` — macOS app project.
- `TodoPi/App/TodoPiApp.swift` — app lifecycle and startup wiring.
- `TodoPi/App/MenuBarController.swift` — `NSStatusItem` setup and click handling.
- `TodoPi/App/MainWindowController.swift` — opens, focuses, and restores the main window.
- `TodoPi/UI/MainWindowView.swift` — top-level SwiftUI view.
- `TodoPi/UI/TodoSidebarView.swift` — list and project navigation.
- `TodoPi/UI/TodoListView.swift` — todos for the selected list.
- `TodoPi/UI/ChatPanelView.swift` — transcript, status, and chat input.
- `TodoPi/Domain/TodoModels.swift` — list, todo, and app document types.
- `TodoPi/Domain/TodoStore.swift` — in-memory source of truth for loaded state.
- `TodoPi/Domain/TodoCommandService.swift` — validated mutations such as create, update, complete, and move.
- `TodoPi/Persistence/JSONTodoRepository.swift` — load and atomically save the local JSON document.
- `TodoPi/Pi/PiSessionManager.swift` — launches pi lazily, tracks lifecycle, and restarts after failure.
- `TodoPi/Pi/PiRPCProtocol.swift` — request and response contracts between the app and pi.
- `TodoPi/Chat/ChatViewModel.swift` — sends user messages, receives replies, and bridges pi tool calls into app commands.
- `TodoPiTests/Domain/TodoCommandServiceTests.swift` — domain mutation coverage.
- `TodoPiTests/Persistence/JSONTodoRepositoryTests.swift` — JSON round-trip and atomic-save coverage.
- `TodoPiTests/Pi/PiRPCProtocolTests.swift` — RPC validation and mapping coverage.

The main window is split into two areas: a todo workspace and a chat panel. The todo workspace has a sidebar for lists or projects and a detail pane for the selected list. The chat panel shows transcript, pi status, and a single input field. The menubar item is only the entry point. The working surface lives in the normal window.

The app persists a single local JSON document and keeps an in-memory store while running. All changes flow through the same command layer, whether they come from the UI or from pi. That keeps validation, persistence, and future features in one place.

The RPC boundary should stay narrow and typed. A minimal v1 contract is:

```swift
struct PiToolRequest {
    let name: String
    let arguments: [String: String]
}

struct PiToolResult {
    let isSuccess: Bool
    let payload: String
    let errorCode: String?
}
```

Expected tool names:
- `getLists`
- `getTodos`
- `createList`
- `createTodo`
- `updateTodo`
- `completeTodo`
- `moveTodo`

`TodoCommandService` validates every mutation before `JSONTodoRepository` saves it. Invalid list IDs, invalid todo IDs, empty titles, malformed RPC arguments, and failed saves return typed errors to pi. The app remains usable even if pi is starting, busy, or unavailable.

## Existing patterns

Investigation found no existing app code or project structure in this repository. This design introduces the initial patterns for the codebase:
- SwiftUI views for the main interface.
- AppKit integration for the menubar item and window control.
- An app-owned domain and persistence layer under `TodoPi/Domain/` and `TodoPi/Persistence/`.
- A narrow RPC boundary under `TodoPi/Pi/` so assistant behavior stays separate from storage and UI concerns.

## Implementation phases

<!-- START_PHASE_1 -->
### Phase 1: App shell and menubar entry
**Goal:** Create the native macOS app shell, menubar item, and standalone window.

**Components:**
- `TodoPi.xcodeproj` — project definition for a macOS app target and test target.
- `TodoPi/App/TodoPiApp.swift` — app startup and dependency wiring.
- `TodoPi/App/MenuBarController.swift` — status item creation and click handling.
- `TodoPi/App/MainWindowController.swift` — open or focus a single main window instance.
- `TodoPi/UI/MainWindowView.swift` — placeholder top-level SwiftUI layout.

**Dependencies:** None.

**Done when:** The app builds and launches, the menubar item appears, and clicking it opens or focuses one standalone window.
<!-- END_PHASE_1 -->

<!-- START_PHASE_2 -->
### Phase 2: Todo domain and JSON persistence
**Goal:** Define the todo data model, local JSON document, and validated command layer.

**Components:**
- `TodoPi/Domain/TodoModels.swift` — app document, list, and todo types with stable IDs.
- `TodoPi/Domain/TodoStore.swift` — in-memory state container.
- `TodoPi/Domain/TodoCommandService.swift` — create, update, complete, and move operations.
- `TodoPi/Persistence/JSONTodoRepository.swift` — load, decode, encode, and atomically save JSON.
- `TodoPiTests/Domain/TodoCommandServiceTests.swift` — domain behavior and validation tests.
- `TodoPiTests/Persistence/JSONTodoRepositoryTests.swift` — persistence and recovery tests.

**Dependencies:** Phase 1.

**Done when:** The app can load and save multiple lists and todos from one local JSON file, invalid mutations are rejected, and tests cover the persistence and command behaviors introduced here.
<!-- END_PHASE_2 -->

<!-- START_PHASE_3 -->
### Phase 3: Main window todo interface
**Goal:** Render the local todo data in a window with list navigation and a chat panel shell.

**Components:**
- `TodoPi/UI/TodoSidebarView.swift` — list and project selection.
- `TodoPi/UI/TodoListView.swift` — selected-list todo presentation.
- `TodoPi/UI/ChatPanelView.swift` — transcript area, status indicator, and text input shell.
- `TodoPi/Chat/ChatViewModel.swift` — window-level state binding between UI and services.
- Updates in `TodoPi/UI/MainWindowView.swift` — split layout and view composition.

**Dependencies:** Phase 2.

**Done when:** The main window shows multiple lists, shows todos for the selected list, includes a visible chat panel with input, and UI tests or view-model tests cover the rendered state and selection behavior introduced here.
<!-- END_PHASE_3 -->

<!-- START_PHASE_4 -->
### Phase 4: pi process lifecycle and RPC boundary
**Goal:** Launch pi lazily on first chat use and expose a typed tool surface from the app.

**Components:**
- `TodoPi/Pi/PiSessionManager.swift` — child-process launch, readiness tracking, shutdown, and restart handling.
- `TodoPi/Pi/PiRPCProtocol.swift` — typed request and response contracts.
- `TodoPi/Chat/ChatViewModel.swift` — start-on-demand behavior and pi status updates.
- `TodoPiTests/Pi/PiRPCProtocolTests.swift` — request validation and error-mapping tests.

**Dependencies:** Phase 3.

**Done when:** First chat use starts pi in the background, the UI shows connection state, malformed or unsupported RPC calls are rejected cleanly, and tests cover the new protocol and lifecycle behavior.
<!-- END_PHASE_4 -->

<!-- START_PHASE_5 -->
### Phase 5: Chat-driven todo actions
**Goal:** Wire pi chat messages to app-owned todo commands and return structured results to the UI.

**Components:**
- Updates in `TodoPi/Chat/ChatViewModel.swift` — chat send, reply handling, and tool-call dispatch.
- Updates in `TodoPi/Domain/TodoCommandService.swift` — command responses shaped for chat confirmations.
- Updates in `TodoPi/UI/ChatPanelView.swift` — transcript rendering for success and failure states.
- Integration coverage in `TodoPiTests/Domain/TodoCommandServiceTests.swift`, `TodoPiTests/Persistence/JSONTodoRepositoryTests.swift`, and `TodoPiTests/Pi/PiRPCProtocolTests.swift`.

**Dependencies:** Phase 4.

**Done when:** pi can create, update, complete, and move todos through app commands, saved state survives relaunch, failures are surfaced without corrupting the JSON file, and tests cover the integrated mutation flows added in this phase.
<!-- END_PHASE_5 -->

## Additional considerations

- Save the JSON document atomically so crashes do not leave a partial file.
- Keep stable IDs in the persisted model so pi and the UI can refer to the same entities without title matching.
- Treat pi as an untrusted client of the app command layer. The app validates every request before mutating state.
- Keep `PiSessionManager` separate from todo storage so the assistant backend can change later without rewriting the domain layer.
