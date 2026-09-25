# Smart Organiser

A background macOS utility for the Focus experiment. **Control–Option–Space** summons a small panel asking **“What are you planning to do?”** Type the task, optionally enable **Set the vibe**, and press **Return**. GLM 5.3 Flash plans the workspace, the utility closes the current windows and opens the chosen apps, and the panel disappears. No dashboard, Dock window, or credential-entry UI.

## Run

Requires macOS 14+, Swift 6, and Xcode for tests. No third-party dependencies.

```sh
./scripts/build-app.sh
open "dist/Smart Organiser.app"
```

On first launch, a borderless overlay fills the display under the pointer. A clear-to-frosted center gradient frames a floating logo with a quiet system chime. The shortcut and permission status then fade in sequentially on the same screen, without pages or progress dots. Accessibility is checked before any permission controls appear. The check verifies read-only window access to another running app. Reading our own focused input panel cannot prove permission to control other apps. Explicit cross-process denial takes precedence over the trust flag. Granted access shows a checkmark; only confirmed denial shows Enable. Inconclusive checks offer Retry, not Enable. Status is refreshed on activation and when the panel becomes key. Enable opens System Settings and temporarily hides the overlay. It returns when access is granted. Permission status updates automatically. **Let’s begin** records completion and dismisses onboarding. Later launches show only the menu-bar item. Summon the task prompt with **⌃⌥Space** or that item. Onboarding completion is permanent: later permission changes never replay it. Permissions needed for arranging windows are checked when submitting a task. Closing onboarding before finishing leaves it available on the next summon. Escape dismisses the panel; Stop cancels pending work. This reset closes windows and cannot be undone.

Accessibility is the only macOS permission this utility requests. It is required to control other apps’ windows. Onboarding completion is stored in local UserDefaults; no key is requested during onboarding. The illumination respects Reduce Motion.

## Environment

Put the key in the project-root `.env`:

```dotenv
OPENROUTER_API_KEY=your-key
```

`.env` is git-ignored and reread on every submitted task. Credentials are read from the process environment first, then `.env`. There is no Keychain access or key-entry UI. Finder-launched apps normally do not inherit terminal environment variables.

The app in `dist/` resolves `.env` from this project. If you move the app elsewhere, use `~/Library/Application Support/Smart Organiser/.env` instead. The parser supports plain, quoted, and `export` assignments and comments. It does not execute shell syntax or interpolate values. Keep the file private (`chmod 600 .env`).

## Vibe

The everyday prompt is a single compact input bar with **“What are you planning to do?”** as its placeholder, a **Vibe** switch, and an adjacent Return button. There is no heading, footer, or helper text. Summoning activates the utility and explicitly focuses its native text editor; Escape restores focus to the previous app. Errors appear only when needed in an error popover; the submit button becomes a stop control while arranging. When enabled, GLM chooses an installed music player and includes it in the arrangement. There is no genre, playlist, or app picker. Recognized players include Music, Spotify, TIDAL, Deezer, Amazon Music, YouTube Music, and other common desktop players. The model chooses a player to open after existing windows are closed. Validation requires an actual music-player action before any changes apply. Playback is not automated, and progress describes actual app operations rather than claiming that music is playing.

Mention other preferences, like including chat or a video app, in the task itself.

## Relevant pages and display grids

The agent chooses relevant websites and search queries whenever it selects a browser. macOS supplies browser capability information from installed apps; there is no task-to-website or browser-name lookup table. The controller opens the chosen HTTP(S) addresses in the selected browser, then places its window. If the model does not know an exact page, it is instructed to choose a relevant search URL instead of inventing a video ID or article path. It has no live search tool, so page contents and availability are not verified. Pages may require sign-in; opening a page does not start playback. Multiple URLs open as tabs or windows according to the browser’s behavior. The controller waits for the window inventory to settle and tiles every resulting standard window within the browser’s allocated region; four windows occupy four quadrants.

The agent specifies display assignments, rows and relative cell sizes. Local geometry fills each used display's usable area edge to edge, without overlapping cells or unused strips. The main task can occupy a larger tile while supporting apps occupy smaller ones; one app fills its display. Extra displays are used when useful, without launching irrelevant apps merely to fill them. App minimum sizes can still constrain an arrangement and are reported through the existing placement check.

URL schemes, browser capability, grid membership, display IDs and cell sizes are validated before any current window is closed. Credentials and executable/local-file URL schemes are rejected. URLs may be opened externally only after the task is submitted, as part of its workspace setup.

## Fresh workspace reset

Submitting a task now means **choose apps → close current windows → reopen the chosen apps → place their new windows**. The plan is generated and validated before any window closes. Only installed apps, connected displays, valid geometry, and launch actions are accepted. An invalid plan or provider error leaves the current workspace untouched.

The controller closes all accessible standard windows from other regular apps through their native close buttons. For full-screen windows it first leaves full-screen mode automatically and waits for the Space transition to settle. The Organiser prompt and system dialogs are excluded. It verifies that each old window disappears from the owning app’s Accessibility inventory before moving on. If a save prompt appears, an app refuses to close, or closure cannot be verified, that entire app is preserved. Its remaining windows are skipped, and it is excluded from reopening or document creation during this run. Other windows still close and the remaining selected apps still open. Preserved apps are reported as warnings after setup. Save/Discard dialogs remain entirely under the user’s control. No force-quit, automatic discard, or synthetic save keystrokes are used.

Once every captured window has been closed or its app preserved, the remaining selected apps are reopened in plan order. Supporting apps open first, the main task app last. App reopening can produce a blank window, a document picker, or restored content depending on the app; previous files, projects, and tabs are not guaranteed to return. Apps are not terminated. Each app gets up to ten seconds to expose a window. Some apps need the user to choose or create a document.

Only newly opened windows are resized. If an app restores its new window into full-screen mode, the controller exits that mode before placement. Geometry respects monitor positions, negative origins, menu bars, and the Dock. Minimum size constraints or refused Accessibility requests produce a partial-failure report.

**Closing windows cannot be undone.** The old Undo command has been removed. Cancellation stops further actions; windows already closed stay closed. The Enter button’s tooltip identifies the reset behavior, while the normal input bar stays minimal.

Tests simulate the close/open boundary and verify that all windows close before any app opens, invalid plans cannot close anything, a save prompt preserves its app while the rest of setup continues, and cancellation stops the sequence. They do not close the developer’s live workspace during automated tests.

## Model and data

Uses `z-ai/glm-5.3-flash` through OpenRouter with low-effort reasoning, matching the iPhone guide. Only on submission, your task, selected preferences, app names/IDs, window titles/geometry, and display geometry go to OpenRouter and its model provider. No screenshots, file contents, or Focus history are read. Plans and window inventories stay in memory; no request data or credentials are logged.

## Development

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./scripts/build-app.sh
```

`LauncherDelegate` owns the global Carbon hotkey, floating panel, and menu-bar item. `OnboardingView` owns the illuminating welcome, shortcut introduction, and live permission status on a full-display frosted overlay; completion is stored once. `SummonView` is the input bar; `PromptInput` and `PromptInputFocus` attach a native AppKit field editor and establish keyboard focus on every summon. `OrganiserModel` runs plan → validate → reset. `WorkspaceReset` guarantees close-before-open ordering. `WorkspaceRequest` builds preferences and enforces music inclusion. `WindowController` performs local Accessibility actions. `OrganiserCore` owns geometry and plan validation.

Keep the app in a stable location before granting Accessibility. Builds reuse `CODE_SIGN_IDENTITY` when provided, otherwise the existing **Omega Local Signing** certificate or an Apple Development identity. They do not silently fall back to ad-hoc signatures, whose build-specific identity invalidates prior grants. Switching from the old ad-hoc build to a certificate-backed build can require refreshing its existing Accessibility entry once; subsequent builds retain the same signing requirement. This is a local background utility, not an App Store extension or notarized distribution.

Regression tests cover delayed full-screen exit, already-windowed and unsupported windows, restoring full screen, refused/stuck transitions, cancellation, and model-chosen music apps. These use simulated Accessibility state at the production transition boundary; real app-specific Accessibility behavior still depends on macOS and the target app.

Permission regression checks cover the initial checking state, granted access, stale false trust with a successful read-only probe, inconclusive reads, and confirmed denial. Apple documents build-specific ad-hoc requirements in [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

Onboarding regression tests exercise the actual application state: a saved completion always bypasses onboarding during permission rechecks, and finishing persists across new instances/relaunches.

### Live Music regression (2026-09-25)

A signed-app probe using the production controller reproduced three failures: a stale Accessibility grant returned `AXError.apiDisabled` while the old focused-app permission probe falsely reported success; Music acknowledged its hidden full-screen close control without closing; Enhanced UI animation caused successful geometry writes to return to the old frame. Refreshing the existing grant, automatically exiting full screen before closing, and temporarily suspending `AXEnhancedUserInterface` during placement fixed the observed sequence. The mode is restored on completion, failure, and cancellation. [Rectangle documents the same animated-frame behavior](https://github.com/rxhanson/Rectangle/blob/main/TerminalCommands.md#control-enhanced-ui-handling).

Live verification passed from both windowed Music and `AXFullScreen = true`: close, reopen, exit restored full screen, and verify the final frame on the Q24h-10 display. Other app windows were not closed by the probe. Temporary probe code and UI were removed afterward. These native Space and app-animation behaviors are verified live, not claimed to be covered by mocked unit tests. Automated permission tests prevent our own process from establishing cross-process authorization and preserve external access denials. Window-read failures now stop setup instead of being reported as an empty workspace or a missing app window.

The planner can request `createNewDocument: true` for note-taking or document apps. The controller invokes the enabled native Command-N menu action once (not synthetic typing), waits for the app’s windows, and arranges them. Notes uses this to create a fresh blank note. Apps without an exposed native New command are still arranged and report a preparation warning. A Notion URL alone does not create a new page; native New support depends on the installed app. Existing documents are never overwritten or given placeholder text.

## Demo recordings

See [the three recorded workflows](demos/README.md). Enter now hides the input bar immediately, before permissions, scanning, or planning. Summoning again allows inspection of progress or any warnings.

When a coding task refers to this repo, the planner may set `projectPath` to the locally discovered project directory. Validation only permits that exact directory; it is opened in the selected editor through macOS. No arbitrary local path or command is accepted. The project path is included in the planner context alongside the existing app/window metadata.
