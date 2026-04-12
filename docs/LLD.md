# DeskMD LLD

[English](./LLD.md) | [한국어](./LLD.ko.md)

## 1. System Structure

DeskMD has two layers.

1. Native macOS wrapper
   - An Objective-C app based on `WKWebView`.
   - Owns window creation, local HTML loading, file picker handling, native save panels, and external link routing.

2. Web editor UI
   - A Markdown editor written with HTML, CSS, and JavaScript.
   - Owns editing, preview rendering, autosave, file loading, and save request creation.

## 2. Directory Structure

```text
.
├── app.js
├── index.html
├── styles.css
├── README.md
├── README.ko.md
├── package-lock.json
├── package.json
├── vendor
│   ├── marked.umd.js
│   ├── purify.min.js
│   └── versions.js
├── docs
│   ├── PRD.md
│   ├── PRD.ko.md
│   ├── LLD.md
│   └── LLD.ko.md
├── macos
│   ├── AppIcon.icns
│   ├── App.m
│   └── Info.plist
├── scripts
│   ├── build-macos-app.sh
│   ├── generate-app-icon.js
│   └── ux-smoke-test.js
└── dist
    └── DeskMD.app
```

## 3. macOS App Design

### 3.1 Entry Point

File: `macos/App.m`

The `main` function creates `NSApplication`, registers `AppDelegate`, and starts the app event loop.

```objc
NSApplication *app = [NSApplication sharedApplication];
appDelegate = [[AppDelegate alloc] init];
app.delegate = appDelegate;
[app setActivationPolicy:NSApplicationActivationPolicyRegular];
[app activateIgnoringOtherApps:YES];
[app run];
```

### 3.2 AppDelegate Responsibilities

`AppDelegate` implements these protocols:

- `NSApplicationDelegate`
- `WKNavigationDelegate`
- `WKUIDelegate`
- `WKScriptMessageHandler`

Main responsibilities:

- Create `NSWindow` and `WKWebView` on app launch.
- Load `Contents/Resources/Editor/index.html` from the app bundle.
- Quit when the last window closes.
- Forward external HTTP/HTTPS links to the default browser.
- Handle web file selection requests through `NSOpenPanel`.
- Handle web confirm requests through a native `NSAlert` sheet.
- Handle web save requests through `NSSavePanel`.
- Copy selected preview text through `NSPasteboard`.

### 3.3 Window Configuration

Initial window size:

- Width: `1180`
- Height: `820`
- Minimum width: `760`
- Minimum height: `560`

The window is a normal macOS window that can be closed, minimized, and resized.

### 3.4 File Picker Handling

The web UI's `input type="file"` request is handled by `WKUIDelegate` through `runOpenPanelWithParameters`.

Allowed types:

- `UTTypePlainText`
- `.md`
- `.markdown`

Flow:

1. Create `NSOpenPanel`.
2. Allow file selection and block directory selection.
3. Apply WebKit's `allowsMultipleSelection` value.
4. If the user selects a file, call `completionHandler(panel.URLs)`.
5. Save the first selected file's parent folder to `lastDocumentDirectoryURL`.
6. If the user cancels, call `completionHandler(nil)`.

### 3.5 External Link Handling

`WKNavigationDelegate` detects link clicks.

- If the user clicks an `http` or `https` link: open it with `NSWorkspace.sharedWorkspace openURL`.
- Otherwise: allow local file loading and internal resource loading inside the WebView.

## 4. Web UI Design

### 4.1 HTML Structure

File: `index.html`

Main elements:

- `#status`: save/open status text.
- `#newDoc`: new document button.
- `#openFileButton`: open button.
- `#openFile`: hidden file input.
- `#saveMd`: Markdown save button.
- `#saveHtml`: HTML save button.
- `#editor`: editor textarea.
- `#preview`: rendered preview area.
- `#count`: character count.

### 4.2 Style Structure

File: `styles.css`

Main layout:

- `.shell`: whole app container.
- `.topbar`: top status/action area.
- `.workspace`: two-column editor/preview grid.
- `.pane`: shared pane structure.
- `.preview`: rendered Markdown styling.
- `.preview`: explicitly uses `user-select: text` so preview text can be selected and copied with `Cmd+C`.

Responsive behavior:

- At `820px` or below, the editor and preview switch to a vertical stack.
- At `460px` or below, the brand image is hidden and button widths are adjusted.

### 4.3 JavaScript Module Responsibilities

File: `app.js`

Main state:

```js
const storageKey = "deskmd-document";
const fileNameKey = "deskmd-filename";
const legacyStorageKey = "markdown-desk-document";
const legacyFileNameKey = "markdown-desk-filename";
let currentFileName = localStorage.getItem(fileNameKey) || localStorage.getItem(legacyFileNameKey) || "document.md";
let saveTimer = 0;
```

Main functions:

- `escapeHtml(value)`: Escapes HTML special characters.
- `checkLibraryUpdates()`: Checks newer library versions from npm registry when internet access is available.
- `fallbackMarkdown(markdown)`: Basic Markdown renderer used if the bundled renderer fails to load.
- `sanitizeHtml(html)`: Uses DOMPurify or fallback sanitization.
- `render()`: Converts editor content to HTML and updates the preview.
- `setStatus(message)`: Updates status text.
- `autosave()`: Debounces and writes to `localStorage`.
- `downloadFile(content, filename, type)`: Requests native save in the app, or uses Blob download in a browser.
- `htmlDocument()`: Creates a standalone HTML document for export.

### 4.4 Preview Copy

When the user selects preview text and presses `Cmd+C`, the web UI reads the selection and sends it to the `copyText` message handler. The macOS wrapper writes the string to `NSPasteboard.generalPasteboard` as `NSPasteboardTypeString`.

If the editor `textarea` is focused, the bridge is skipped and the default editor copy behavior remains active.

### 4.5 Test Bridge

The web UI exposes `window.deskMdTest` for automated usability tests. It is a thin test API that verifies the real DOM button `.click()` path and state changes without depending on button coordinates.

Main methods:

- `setMarkdown(markdown, filename)`: Injects a test document.
- `getPreviewText()`: Returns preview plain text.
- `getStatus()`: Returns status text.
- `clickNewDocument()`: Clicks the `New Document` DOM button.
- `clickOpenFile()`: Clicks the `Open` DOM button.
- `clickSaveMarkdown()`: Clicks the `Save MD` DOM button.
- `clickSaveHtml()`: Clicks the `Save HTML` DOM button.
- `copyPreviewTextForTest()`: Copies preview text through the native clipboard bridge.

When the macOS app receives the `--ux-smoke-test` argument, it evaluates internal JavaScript after the WebView finishes loading, verifies rendering and clipboard bridging, then exits. `scripts/ux-smoke-test.js` runs the executable in `dist/DeskMD.app` with this mode and verifies the clipboard result through `pbpaste`.

Current UX smoke test coverage:

- Inject test Markdown and verify preview rendering.
- Verify preview text copy through the native bridge.
- Verify the `New Document` confirm path.
- Verify the `New Document` action and status update.
- Verify `Save MD` action and save payload.
- Verify `Save HTML` action and save payload.
- Verify `Open` action.

During tests, save/open actions are recorded to a mock action log instead of opening macOS panels. This is test-only behavior to avoid blocking automation on modal panels and does not apply in normal app mode.

## 5. Rendering Flow

```text
user input
  -> editor input event
  -> render()
  -> bundled marked.parse() or fallbackMarkdown()
  -> sanitizeHtml()
  -> update preview.innerHTML
  -> update character count
  -> autosave()
  -> write localStorage
```

Renderer selection:

- If `window.marked` exists, use bundled `vendor/marked.umd.js`.
- If it fails to load, use the built-in `fallbackMarkdown`.

HTML sanitization:

- If `window.DOMPurify` exists, use DOMPurify.
- Otherwise remove `script`, `style`, `iframe`, `object`, and `embed`, plus `on*` and `javascript:` attributes.

### 5.1 Library Update Check

The app does not use remote scripts for runtime rendering. Rendering libraries are loaded from local files:

- `vendor/marked.umd.js`: `marked 18.0.0`
- `vendor/purify.min.js`: `DOMPurify 3.3.3`
- `vendor/versions.js`: bundled version metadata

When internet access is available, `checkLibraryUpdates()` fetches `latest` metadata from npm registry.

```text
app load
  -> load vendor/versions.js
  -> load vendor/purify.min.js
  -> load vendor/marked.umd.js
  -> checkLibraryUpdates()
  -> fetch https://registry.npmjs.org/{package}/latest
  -> compare bundled version with latest.version
  -> show update-available text in the status area
```

The update check is informational only. It does not execute remote JavaScript or automatically replace bundled files.

## 6. File Open Flow

```text
Open button click
  -> openFile.click()
  -> WKWebView creates file selection request
  -> macOS AppDelegate.runOpenPanelWithParameters()
  -> show NSOpenPanel
  -> return selected file URL to WebKit
  -> input change event
  -> file.text()
  -> update editor.value
  -> render()
  -> autosave()
  -> update status
```

## 7. Save Flow

### 7.1 Save Markdown

```text
Save MD button or Cmd+S
  -> downloadFile(editor.value, filename, "text/markdown;charset=utf-8")
  -> window.webkit.messageHandlers.saveFile.postMessage(...)
  -> AppDelegate.userContentController(...)
  -> show NSSavePanel
  -> set panel.directoryURL when lastDocumentDirectoryURL exists
  -> write UTF-8 text to the selected URL
  -> update lastDocumentDirectoryURL to the saved file's parent folder
  -> evaluateJavaScript(...) to update save result status
```

### 7.2 Save HTML

```text
Save HTML button
  -> htmlDocument()
  -> insert preview.innerHTML into standalone HTML document
  -> downloadFile(..., "text/html;charset=utf-8")
  -> window.webkit.messageHandlers.saveFile.postMessage(...)
  -> show NSSavePanel
  -> write UTF-8 HTML to the selected URL
  -> update save result status
```

## 8. Autosave

Autosave is based on `localStorage`.

Storage keys:

- `deskmd-document`: document body.
- `deskmd-filename`: current filename.

If an autosaved document exists under the previous app name, the app reads `markdown-desk-document` and `markdown-desk-filename` as fallback keys.

The app does not save on every input event immediately. It debounces writes by 250ms.

On app start:

```text
load localStorage draft if it exists
otherwise load starter document
```

## 9. Build Design

File: `scripts/build-macos-app.sh`

Build output:

```text
dist/DeskMD.app
```

Build steps:

1. Remove the existing app bundle.
2. Create `Contents/MacOS` and `Contents/Resources/Editor`.
3. Compile `macos/App.m` with `clang`.
4. Link `Cocoa`, `WebKit`, and `UniformTypeIdentifiers`.
5. Copy `Info.plist`.
6. Copy `index.html`, `styles.css`, `app.js`, and `vendor` into app resources.
7. Copy `AppIcon.icns` into app resources.
8. Set executable permissions.
9. Run ad-hoc codesign when available.
10. Remove the build `ModuleCache`.

## 10. Run

Current run target:

```sh
open "dist/DeskMD.app"
```

## 11. Known Constraints and Future Improvements

- Library updates: the app only checks whether newer versions exist and never executes remote scripts.
- Save UX: saving currently uses the JavaScript bridge and `NSSavePanel`; a future version can separate overwrite behavior from `Save As`.
- File permissions: sandboxed App Store distribution would require security-scoped bookmarks.
- App icon: there is no dedicated app icon yet.
- Tests: current tests focus on build checks, syntax checks, signing verification, and the built-in UX smoke path.
