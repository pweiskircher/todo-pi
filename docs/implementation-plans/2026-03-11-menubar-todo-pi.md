# Menubar Todo Pi implementation plan

## Inputs

- Design document: `docs/design-plans/2026-03-11-menubar-todo-pi.md`
- Pi RPC docs: `README.md` section "RPC Mode" and `docs/rpc.md`
- Pi extensions docs: `docs/extensions.md`

## Verified current repo state

- The repository currently contains the design document and no app code.
- There is no Xcode project, no Swift source tree, and no test target yet.
- The first implementation step is project scaffolding, not feature work.

## Working assumptions

- v1 is a local-only single-user app.
- pi CLI is already installed and configured on the machine running the app.
- The app launches pi lazily with RPC mode over stdin/stdout.
- v1 keeps chat transcript and pi session history in memory only. Todo data persists; chat history does not.
- The todo store lives at `~/Library/Application Support/TodoPi/todos.json`.
- The app launches pi with built-in file and shell tools disabled so pi only manages todos through explicit app tools.
- The app bundles a pi extension source file and loads it at process start with `--extension`.
- The pi extension forwards todo tool calls back into the app over a local authenticated Unix domain socket. If that transport becomes awkward in Swift, fall back to loopback HTTP on `127.0.0.1` with the same request and response model.

## Implementation decisions to lock before coding

- Launch command shape:
  - `pi --mode rpc --no-session --no-tools --extension <bundled-extension-path>`
- Runtime environment passed to pi:
  - `TODO_PI_SOCKET` for the socket path.
  - `TODO_PI_TOKEN` for a per-launch auth token.
- Initial pi tool set exposed by the bundled extension:
  - `getLists`
  - `getTodos`
  - `createList`
  - `createTodo`
  - `updateTodo`
  - `completeTodo`
  - `moveTodo`
- Todo mutations remain app-owned. The extension only forwards typed requests and returns typed results.

## Phase 1: App shell and menubar entry

**Goal:** Create a buildable macOS app with a menubar item and one standalone main window.

**Files to create**
- `TodoPi.xcodeproj`
- `TodoPi/App/TodoPiApp.swift`
- `TodoPi/App/MenuBarController.swift`
- `TodoPi/App/MainWindowController.swift`
- `TodoPi/UI/MainWindowView.swift`
- `TodoPiTests/`

**Tasks**
1. Create a native macOS app target and unit test target.
2. Wire `TodoPiApp.swift` to create app services once at startup.
3. Implement `MenuBarController` using `NSStatusItem`.
4. Implement `MainWindowController` so repeated menubar clicks focus the same window instead of creating duplicates.
5. Add a placeholder `MainWindowView` with a split layout shell for todos and chat.
6. Confirm the app can build and launch from Xcode and `xcodebuild`.

**Acceptance criteria covered**
- `menubar-todo-pi.AC1.1`
- `menubar-todo-pi.AC1.2`
- `menubar-todo-pi.AC1.3`

**Verification**
- `xcodebuild -project TodoPi.xcodeproj -scheme TodoPi -destination 'platform=macOS' build`
- Manual smoke test: launch app, confirm menubar item appears, click twice, verify only one window is used.

## Phase 2: Todo domain and JSON persistence

**Goal:** Create the app-owned todo model, validated command layer, and atomic JSON persistence.

**Files to create**
- `TodoPi/Domain/TodoModels.swift`
- `TodoPi/Domain/TodoStore.swift`
- `TodoPi/Domain/TodoCommandService.swift`
- `TodoPi/Persistence/JSONTodoRepository.swift`
- `TodoPiTests/Domain/TodoCommandServiceTests.swift`
- `TodoPiTests/Persistence/JSONTodoRepositoryTests.swift`

**Tasks**
1. Define `TodoDocument`, `TodoList`, and `TodoItem` with stable IDs, ordering, timestamps, and completion state.
2. Implement `TodoStore` as the in-memory source of truth for the loaded document.
3. Implement `JSONTodoRepository` to:
   - create the Application Support directory,
   - load existing JSON,
   - handle missing or malformed files safely,
   - save atomically with temp-file replacement.
4. Implement `TodoCommandService` for create, update, complete, move, and create-list operations.
5. Keep persistence behind the command layer so all mutations follow the same validation path.
6. Add unit tests for valid mutations, invalid IDs, empty titles, malformed JSON recovery, and atomic save behavior.

**Acceptance criteria covered**
- `menubar-todo-pi.AC2.1`
- `menubar-todo-pi.AC2.2`
- `menubar-todo-pi.AC2.3`
- `menubar-todo-pi.AC2.4`
- `menubar-todo-pi.AC2.5`

**Verification**
- `xcodebuild -project TodoPi.xcodeproj -scheme TodoPi -destination 'platform=macOS' test`
- Manual smoke test: create a sample JSON document, relaunch app, verify state reloads.

## Phase 3: Main window todo interface

**Goal:** Replace the placeholder window with a working todo workspace plus chat shell.

**Files to create**
- `TodoPi/UI/TodoSidebarView.swift`
- `TodoPi/UI/TodoListView.swift`
- `TodoPi/UI/ChatPanelView.swift`
- `TodoPi/Chat/ChatViewModel.swift`
- updates in `TodoPi/UI/MainWindowView.swift`

**Tasks**
1. Build a sidebar for lists or projects.
2. Build a selected-list todo view with ordering and completion status.
3. Build a chat panel shell with transcript area, status indicator, text field, and send action.
4. Connect `ChatViewModel` to view state without starting pi yet.
5. Bind `TodoStore` into the UI so list selection and todo rendering stay in sync.
6. Add tests for view-model state changes and selection behavior.

**Acceptance criteria covered**
- `menubar-todo-pi.AC3.1`
- `menubar-todo-pi.AC3.2`
- `menubar-todo-pi.AC3.3`

**Verification**
- `xcodebuild -project TodoPi.xcodeproj -scheme TodoPi -destination 'platform=macOS' test`
- Manual smoke test: switch between multiple lists, confirm todo pane updates and chat shell remains visible.

## Phase 4: pi process lifecycle and host bridge

**Goal:** Launch pi on demand, parse RPC events, and expose app-owned todo tools through a bundled pi extension.

**Files to create**
- `TodoPi/Pi/PiSessionManager.swift`
- `TodoPi/Pi/PiRPCProtocol.swift`
- `TodoPi/Pi/PiBridgeServer.swift`
- `TodoPi/Pi/PiLaunchConfiguration.swift`
- `TodoPi/Resources/pi-extension/todo-app-tools.ts`
- `TodoPiTests/Pi/PiRPCProtocolTests.swift`
- `TodoPiTests/Pi/PiBridgeServerTests.swift`

**Tasks**
1. Implement `PiLaunchConfiguration` for locating the pi executable and assembling launch arguments.
2. Implement `PiSessionManager` using `Process`, stdin, and stdout pipes.
3. Parse RPC output using strict LF-delimited JSONL framing only, as required by pi RPC mode.
4. Track session state: idle, starting, ready, busy, failed, stopped.
5. Implement `PiBridgeServer` as a local authenticated request/response server owned by the app.
6. Create `todo-app-tools.ts` that registers the todo tools inside pi and forwards each request to the app bridge using `TODO_PI_SOCKET` and `TODO_PI_TOKEN`.
7. Disable built-in pi tools at launch with `--no-tools` so v1 scope remains limited to todo operations.
8. Add tests for JSONL parsing, unsupported RPC events, auth failures on the host bridge, and clean failure when `pi` is unavailable.

**Acceptance criteria covered**
- `menubar-todo-pi.AC4.1`
- `menubar-todo-pi.AC4.2`
- `menubar-todo-pi.AC4.5`
- `menubar-todo-pi.AC4.6`

**Verification**
- Unit tests for protocol parsing and bridge auth.
- Manual smoke test: first send attempts to start pi, missing `pi` executable surfaces a clear UI error, successful startup transitions through starting to ready.

## Phase 5: Chat-driven todo actions

**Goal:** Connect chat input, pi responses, and app-owned todo mutations end to end.

**Files to update**
- `TodoPi/Chat/ChatViewModel.swift`
- `TodoPi/UI/ChatPanelView.swift`
- `TodoPi/Domain/TodoCommandService.swift`
- `TodoPi/Pi/PiSessionManager.swift`
- test updates under `TodoPiTests/Domain/`, `TodoPiTests/Persistence/`, and `TodoPiTests/Pi/`

**Tasks**
1. Send user chat text into the RPC `prompt` command.
2. Render assistant text responses from streamed RPC events.
3. Route extension tool requests through `PiBridgeServer` into `TodoCommandService`.
4. Return structured mutation results to pi and update UI state from the same command results.
5. Make failure states visible in chat without corrupting todo state.
6. Keep the app usable when pi stops responding or disconnects mid-session.
7. Add integration tests with a fake pi transport or recorded RPC fixtures for:
   - create todo,
   - update todo,
   - complete todo,
   - invalid tool arguments,
   - pi disconnect during chat.

**Acceptance criteria covered**
- `menubar-todo-pi.AC4.3`
- `menubar-todo-pi.AC4.4`

**Verification**
- `xcodebuild -project TodoPi.xcodeproj -scheme TodoPi -destination 'platform=macOS' test`
- Manual smoke test: ask pi to create, edit, and complete todos; relaunch app; verify persisted state remains correct.

## Cross-cutting verification checklist

Run this before calling v1 done:
- `xcodebuild -project TodoPi.xcodeproj -scheme TodoPi -destination 'platform=macOS' build`
- `xcodebuild -project TodoPi.xcodeproj -scheme TodoPi -destination 'platform=macOS' test`
- Manual smoke test for menubar launch and single-window behavior.
- Manual smoke test for malformed JSON recovery.
- Manual smoke test for pi missing from PATH.
- Manual smoke test for create, update, complete, and move flows through chat.
- Manual smoke test for app relaunch with persisted todo data.

## Risks and fallback plans

- **pi executable discovery:** If `pi` is not on PATH, add a user-configurable executable path in app settings before deeper integration work.
- **Socket transport complexity:** If authenticated Unix domain sockets slow down implementation, switch to loopback HTTP with the same request and response payloads.
- **RPC event handling complexity:** Start with only the event subset needed for chat text, status, and tool execution. Do not implement full RPC surface up front.
- **Scope creep:** Do not persist chat history, add syncing, or widen pi permissions in v1.

## Recommended execution slice

Implement only Phase 1 first. Stop once the app builds, the menubar item appears, and the main window opens and refocuses correctly.

That keeps the repository in a runnable state and gives the rest of the plan a stable shell to build on.
