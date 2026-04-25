# DeskMD PRD

[English](./PRD.md) | [한국어](./PRD.ko.md)

## 1. Overview

DeskMD is a lightweight Markdown editor for macOS. Users can open `DeskMD.app` directly to write Markdown, preview rendered output, and save Markdown files without opening a browser tab.

The product packages a web-based editor UI inside a local macOS app bundle and runs it through a native `WKWebView` wrapper.

## 2. Goals

- Provide a Markdown writing environment that runs like a macOS app.
- Show editing and rendered preview side by side.
- Run from a local app bundle without a separate server or package install step for end users.
- Open `.md`, `.markdown`, and `.txt` files, then save Markdown changes with `Save` or `Save As`.
- Preserve in-progress work with local autosave.

## 3. Non-Goals

- Full IDE-level project or folder management.
- Multi-tab document editing.
- Git integration, sync, or cloud storage.
- App Store distribution or notarization with an Apple Developer certificate.
- A custom implementation of complete CommonMark or GFM rendering.

## 4. Users

- People who want to write Markdown quickly on a MacBook.
- Users writing README files, notes, blog drafts, or lightweight technical documents.
- Users who want an independent app window instead of another browser tab.

## 5. Main Scenarios

### 5.1 Create a New Document

1. The user opens `DeskMD.app`.
2. The default document or the latest autosaved draft appears.
3. The user writes Markdown in the left editor pane.
4. The right preview pane updates immediately.

### 5.2 Open an Existing File

1. The user clicks `Open`.
2. The macOS file picker appears.
3. The user selects a `.md`, `.markdown`, or `.txt` file.
4. The file content loads into the editor and the preview updates.

### 5.3 Save Markdown

1. The user clicks `Save` or presses `Cmd+S`.
2. If the document already has a file URL, DeskMD writes directly to that file.
3. If the document has no file URL yet, DeskMD opens the macOS save panel.
4. The status text reports that the save completed.

### 5.4 Save As

1. The user clicks `Save As`.
2. DeskMD always opens the macOS save panel.
3. The user chooses a save location.
4. DeskMD saves the document to the selected path and uses that path for future `Save` actions.

## 6. Functional Requirements

| ID | Requirement | Status |
| --- | --- | --- |
| FR-001 | The app must run as a macOS app bundle. | Implemented |
| FR-002 | The app must provide a left editor pane and right preview pane. | Implemented |
| FR-003 | The preview must update whenever the user edits the document. | Implemented |
| FR-004 | The app must autosave the current content to local browser storage. | Implemented |
| FR-005 | The app must open `.md`, `.markdown`, and `.txt` files. | Implemented |
| FR-006 | The app must save the current document as Markdown. | Implemented |
| FR-007 | The app must keep export functionality out of the primary toolbar until a broader Export flow is revisited. | Implemented |
| FR-008 | `Cmd+S` must trigger Markdown save. | Implemented |
| FR-009 | External links must open in the default browser, not inside the app. | Implemented |
| FR-010 | Markdown preview must work without internet access through bundled renderer libraries. | Implemented |
| FR-011 | When internet access is available, the app must only check whether bundled renderer libraries have newer versions. | Implemented |
| FR-012 | When saving an opened document, the default save location must be the source document folder. | Implemented |
| FR-013 | Users must be able to select preview text and copy it with the standard copy shortcut. | Implemented |
| FR-014 | The app must provide an automated usability test path that does not depend on button coordinates. | Implemented |
| FR-015 | Users must be able to see the current app version from within the app. | Implemented |
| FR-016 | Users must be able to see the current document filename in the app UI. | Implemented |
| FR-017 | Toolbar buttons must use short English labels. | Implemented |
| FR-018 | Renderer library update check results must be shown separately from document save/open status. | Implemented |
| FR-019 | `Save` must write directly to the current document when a file URL is known, and fall back to a save panel for new documents. | Implemented |
| FR-020 | `Save As` must always show a save panel and update the current document path after a successful save. | Implemented |
| FR-021 | The top toolbar must have lightweight layout regression coverage at desktop and narrow window widths. | Implemented |
| FR-022 | The UI must support light and dark appearances based on the macOS system color scheme. | Implemented |
| FR-023 | Users must be able to reopen up to five recent documents from the macOS `File > Open Recent` menu. | Implemented |

## 7. Non-Functional Requirements

| ID | Requirement | Criteria |
| --- | --- | --- |
| NFR-001 | Launch convenience | Runs from the built app bundle. |
| NFR-002 | Low install overhead | Runs without Node, Electron, or a local server for end users. |
| NFR-003 | Performance | Preview updates without noticeable input lag for normal documents. |
| NFR-004 | Security | Rendered HTML removes script-capable content. |
| NFR-005 | Offline support | App UI, `marked`, and `DOMPurify` work without internet access. |
| NFR-006 | Maintainability | A single build script can regenerate the app bundle. |
| NFR-007 | Release access | README links to a downloadable app bundle for users who do not want to build from source. |
| NFR-008 | App identity | The app bundle includes a dedicated app icon. |

## 8. Current Constraints

- The app uses bundled `marked 18.0.0` and `DOMPurify 3.3.3` as the default renderer stack.
- If internet access is available, the app only checks npm registry metadata for newer versions.
- Light and dark appearances follow the macOS system color scheme through CSS media queries.
- `Save As` and first-time saves are handled through the native macOS save panel.
- Default developer builds use ad-hoc signing, while notarized distribution requires a separate release script and Apple Developer credentials.
- Autosave data is stored in the app WebView's `localStorage`.
- Recent document paths are stored in macOS user defaults and are limited to five entries.

## 9. Future Improvements

- Low priority: revisit a broader Export flow with HTML/PDF choices later.
- Long-term: explore an optional WYSIWYG editing mode for the preview pane, while keeping the Markdown source editor as the primary editing model unless the product direction changes.
