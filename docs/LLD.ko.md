# DeskMD LLD

[English](./LLD.md) | [한국어](./LLD.ko.md)

## 1. 시스템 구성

DeskMD는 두 레이어로 구성된다.

1. macOS 네이티브 래퍼
   - Objective-C로 작성된 `WKWebView` 기반 앱.
   - 앱 윈도우 생성, 로컬 HTML 로드, 파일 선택 패널, 네이티브 저장 패널, 외부 링크 처리를 담당한다.

2. 웹 편집 UI
   - HTML, CSS, JavaScript로 작성된 마크다운 편집기.
   - 편집, 미리보기 렌더링, 자동 저장, 파일 열기, 저장 요청 생성을 담당한다.

## 2. 디렉터리 구조

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
│   ├── notarize-macos-app.sh
│   ├── generate-app-icon.js
│   ├── recent-documents-test.js
│   ├── topbar-visual-test.js
│   └── ux-smoke-test.js
└── dist
    └── DeskMD.app
```

## 3. macOS 앱 설계

### 3.1 진입점

파일: `macos/App.m`

`main` 함수는 `NSApplication`을 생성하고 `AppDelegate`를 등록한 뒤 앱 이벤트 루프를 시작한다.

```objc
NSApplication *app = [NSApplication sharedApplication];
AppDelegate *delegate = [[AppDelegate alloc] init];
app.delegate = delegate;
[app setActivationPolicy:NSApplicationActivationPolicyRegular];
[app activateIgnoringOtherApps:YES];
[app run];
```

### 3.2 AppDelegate 책임

`AppDelegate`는 다음 프로토콜을 구현한다.

- `NSApplicationDelegate`
- `WKNavigationDelegate`
- `WKUIDelegate`
- `WKScriptMessageHandler`

주요 책임:

- 앱 실행 시 `NSWindow`와 `WKWebView` 생성.
- 앱 번들의 `Contents/Resources/Editor/index.html` 로드.
- 마지막 창이 닫히면 앱 종료.
- 외부 HTTP/HTTPS 링크를 기본 브라우저로 전달.
- 웹 파일 선택 요청을 `NSOpenPanel`로 처리.
- 웹 확인 요청을 네이티브 `NSAlert` confirm sheet로 처리.
- 웹 저장 요청을 `NSSavePanel`로 처리.
- 미리보기 선택 텍스트 복사를 `NSPasteboard`로 처리.
- `Open Recent`를 포함한 네이티브 `File` 메뉴 구성.
- 최근 문서 경로를 macOS user defaults에 최대 5개까지 저장.

### 3.3 윈도우 설정

초기 윈도우 크기:

- Width: `1180`
- Height: `820`
- Minimum width: `760`
- Minimum height: `560`

윈도우는 닫기, 최소화, 리사이즈 가능한 일반 macOS 창으로 구성된다.

### 3.4 파일 선택 처리

웹 UI의 `input type="file"` 요청은 `WKUIDelegate`의 `runOpenPanelWithParameters`에서 처리한다.

허용 타입:

- `UTTypePlainText`
- `.md`
- `.markdown`

동작:

1. `NSOpenPanel` 생성.
2. 파일 선택만 허용하고 디렉터리 선택은 차단.
3. WebKit 요청의 `allowsMultipleSelection` 값을 반영.
4. 사용자가 파일을 선택하면 `completionHandler(panel.URLs)` 호출.
5. 선택된 첫 파일을 `currentDocumentURL`에 저장.
6. 선택된 첫 파일의 부모 폴더를 `lastDocumentDirectoryURL`에 저장.
7. 선택된 파일을 최근 문서 목록에 추가.
8. 취소하면 `completionHandler(nil)` 호출.

### 3.5 최근 문서

최근 문서 상태는 macOS 래퍼가 관리한다. 그래서 툴바 버튼을 더 늘리지 않고 네이티브 메뉴에 기능을 둘 수 있다.

저장 방식:

- Key: `DeskMDRecentDocuments`
- 저장소: `NSUserDefaults.standardUserDefaults`
- 값: 정렬된 파일 경로 배열
- 최대 개수: `5`

갱신 지점:

- WebView 파일 선택기를 통한 파일 열기 성공.
- 네이티브 `File > Open...` 열기 성공.
- `Save` 또는 `Save As` 성공.

메뉴 동작:

1. 저장된 목록이 바뀔 때마다 `File > Open Recent`를 다시 구성한다.
2. 가장 최근 문서를 맨 위에 표시한다.
3. 이미 있는 문서를 다시 열면 중복 추가하지 않고 맨 위로 이동한다.
4. 존재하지 않는 파일은 사용자가 열려고 시도할 때 목록에서 제거한다.
5. `Clear Menu`는 최근 문서 경로를 모두 제거한다.

최근 문서를 네이티브 메뉴에서 열면 래퍼가 UTF-8 파일 내용을 읽고 WebView 안의 `window.deskMdOpenDocument(filename, content)`를 호출한다.

### 3.6 외부 링크 처리

`WKNavigationDelegate`에서 링크 클릭을 감지한다.

- `http`, `https` 링크이며 사용자가 클릭한 링크인 경우: `NSWorkspace.sharedWorkspace openURL`
- 그 외 로컬 파일 로드와 내부 리소스 로드: WebView 안에서 허용

## 4. 웹 UI 설계

### 4.1 HTML 구조

파일: `index.html`

주요 요소:

- `#documentName`: 현재 문서 파일명.
- `#status`: 저장/열기 상태 메시지.
- `#updateStatus`: 렌더링 라이브러리 업데이트 확인 상태 메시지. 주의가 필요한 경우에만 표시한다.
- `#newDoc`: 새 문서 버튼.
- `#openFileButton`: 열기 버튼.
- `#openFile`: 숨겨진 파일 입력.
- `#saveMd`: 마크다운 저장 버튼.
- `#saveAs`: Save As 버튼.
- `#editor`: 편집 textarea.
- `#preview`: 렌더링된 미리보기 영역.
- `#count`: 문자 수 표시.

### 4.2 스타일 구조

파일: `styles.css`

주요 레이아웃:

- `.shell`: 앱 전체 컨테이너.
- `.topbar`: 얇은 앱 상단 상태/액션 영역.
- `.document-strip`: 현재 문서 식별 정보와 저장 상태 영역.
- `.app-mark`: 원격 이미지 대신 사용하는 로컬 앱 마크.
- `.action-group`: 문서 액션과 저장 액션 그룹.
- `.workspace`: 편집/미리보기 2열 그리드.
- `.pane`: 각 패널 공통 구조.
- `.preview`: 마크다운 렌더링 결과 스타일.
- `.preview`: 텍스트 선택과 `Cmd+C` 복사를 위해 `user-select: text`를 명시.

색상 동작:

- `:root`는 공통 색상 토큰을 정의하고 `color-scheme: light dark`를 선언한다.
- `@media (prefers-color-scheme: dark)`는 같은 토큰을 다크 외관용 값으로 덮어쓴다.
- 앱 전용 테마 설정을 저장하지 않고 macOS 시스템 외관 설정을 따른다.

반응형 동작:

- `820px` 이하에서는 편집기와 미리보기가 세로 스택으로 전환된다.
- `460px` 이하에서는 앱 마크와 문서명이 줄어들고 버튼 너비가 조정된다.

### 4.3 미리보기 복사

미리보기 텍스트 선택 후 `Cmd+C`를 누르면 웹 UI가 선택 텍스트를 읽어 `copyText` message handler로 전달한다. macOS 래퍼는 전달받은 문자열을 `NSPasteboard.generalPasteboard`에 `NSPasteboardTypeString`으로 기록한다.

에디터 `textarea`가 포커스된 상태에서는 이 브릿지를 사용하지 않고 기본 편집 복사를 유지한다.

### 4.4 테스트 브릿지

웹 UI는 자동 사용성 테스트를 위해 `window.deskMdTest` 객체를 제공한다. 이 객체는 버튼 좌표에 의존하지 않고 실제 DOM 버튼의 `.click()` 경로와 상태를 검증하기 위한 얇은 테스트 API다.

주요 메서드:

- `setMarkdown(markdown, filename)`: 테스트 문서 주입.
- `getPreviewText()`: 미리보기 plain text 조회.
- `getStatus()`: 상태 텍스트 조회.
- `getStoredFileName()`: `localStorage`에 저장된 파일명 조회.
- `getUpdateStatus()`: 렌더링 라이브러리 업데이트 확인 메시지 조회.
- `setUpdateStatusForTest(message, tone)`: 다크 외관 테스트용 업데이트 상태 메시지를 주입하고 표시 상태를 반환.
- `getTopbarLayoutSnapshot()`: 레이아웃 회귀 테스트를 위한 viewport와 상단 툴바 geometry 조회.
- `clickNewDocument()`: `새 문서` DOM 버튼 클릭.
- `clickOpenFile()`: `열기` DOM 버튼 클릭.
- `clickSaveMarkdown()`: `Save` DOM 버튼 클릭.
- `clickSaveAs()`: `Save As` DOM 버튼 클릭.
- `completeSave(filename)`: 네이티브 저장 완료 경로를 호출하고 현재 문서명, 저장된 파일명, 상태를 반환.
- `selectAllPreviewText()`: 미리보기 전체를 실제 선택 상태로 만든 뒤 선택 문자열을 반환.
- `triggerPreviewCopyShortcut()`: 선택된 미리보기 텍스트에 대해 테스트용 `Cmd+C` 경로를 실행하고 결과를 반환.
- `copyPreviewTextForTest()`: 미리보기 텍스트를 네이티브 클립보드 브릿지로 복사.

macOS 앱은 `--ux-smoke-test` 실행 인자를 받으면 WebView 로드 후 내부 JS를 평가해 렌더링과 복사 브릿지를 검증하고 종료한다. `scripts/ux-smoke-test.js`는 `dist/DeskMD.app`의 실행 파일을 이 모드로 실행한 뒤 `pbpaste`로 클립보드 결과를 확인한다.

macOS 앱은 `--topbar-visual-test` 실행 인자를 받으면 앱 창을 데스크톱 폭과 좁은 폭으로 조정하고, 빌드된 WebView 안에서 상단 툴바 geometry를 평가한다. 상단 툴바, 작업 영역, 액션 버튼이 viewport 안에 보이고 서로 겹치지 않는지 확인한 뒤 종료한다. `scripts/topbar-visual-test.js`는 `dist/DeskMD.app`에 이 레이아웃 가드를 실행하고, `--force-dark-appearance`를 붙인 다크 외관 패스를 한 번 더 수행해 다크 토큰, 기본 텍스트 대비, 버전 배지와 업데이트 상태 같은 보조 텍스트 대비를 확인한다.

macOS 앱은 `--recent-documents-test` 실행 인자를 받으면 임시 Markdown 파일을 만들고 최근 문서 정렬, 메뉴 재구성, 누락 파일 제거, 메뉴 비우기를 검증한 뒤 종료한다. `scripts/recent-documents-test.js`는 `dist/DeskMD.app`에 이 가드를 실행한다.

현재 UX smoke test 검증 범위:

- 테스트 마크다운 주입 후 미리보기 렌더링 확인.
- 미리보기 선택 텍스트의 실제 `Cmd+C` 복사 경로 확인.
- 선택한 미리보기 텍스트의 공백과 줄바꿈이 macOS 클립보드까지 그대로 보존되는지 확인.
- `새 문서` 버튼의 confirm 경로 확인.
- `새 문서` 액션 호출 및 상태 확인.
- `.md`, `.markdown`, `.txt`, 무확장자 문서에 대한 `Save` 액션 호출 및 저장 payload 확인.
- `.md`, `.markdown`, `.txt`, 무확장자 문서에 대한 `Save As` 액션 호출 및 저장 payload 확인.
- 저장 완료 후 화면 파일명과 `localStorage` 파일명이 함께 갱신되는지 확인.
- `열기` 액션 호출 확인.

현재 topbar layout test 검증 범위:

- 데스크톱 폭 상단 툴바 geometry 확인.
- 좁은 창 폭 상단 툴바 geometry 확인.
- 상단 툴바, 문서 영역, 액션 영역, 작업 영역, `New`/`Open`/`Save`/`Save As` 버튼이 viewport 안에 보이는지 확인.
- 작업 영역이 상단 툴바와 겹치지 않는지 확인.
- 다크 외관 강제 실행 시 예상 CSS 토큰이 적용되고 핵심 텍스트 대비가 4.5:1 이상인지 확인.
- 다크 외관에서 버전 배지, 업데이트 상태, 문서 상태 같은 보조 텍스트 대비가 4.5:1 이상인지 확인.

현재 recent documents test 검증 범위:

- 최근 문서 목록이 최대 5개 경로로 제한되는지 확인.
- 최신 문서가 맨 위에 오는지 확인.
- 중복 항목은 반복 추가하지 않고 맨 위로 이동하는지 확인.
- 네이티브 `Open Recent` 메뉴가 저장된 경로 기준으로 재구성되는지 확인.
- 존재하지 않는 파일을 열려고 하면 최근 문서 목록에서 제거되는지 확인.
- 앱 재실행 후 `NSUserDefaults`에 저장된 최근 문서 목록이 다시 로드되는지 확인.
- `Clear Menu`가 저장된 목록을 비우는지 확인.

저장/열기 액션은 테스트 중 macOS 패널을 실제로 열지 않고 mock action log에 기록한다. 이는 모달 패널 때문에 자동 테스트가 멈추지 않게 하기 위한 테스트 전용 동작이며, 일반 실행 모드에는 적용되지 않는다.

### 4.5 JavaScript 모듈 책임

파일: `app.js`

주요 상태:

```js
const storageKey = "deskmd-document";
const fileNameKey = "deskmd-filename";
const legacyStorageKey = "markdown-desk-document";
const legacyFileNameKey = "markdown-desk-filename";
let currentFileName = localStorage.getItem(fileNameKey) || localStorage.getItem(legacyFileNameKey) || "document.md";
let saveTimer = 0;
```

주요 함수:

- `escapeHtml(value)`: HTML 특수문자 escape.
- `checkLibraryUpdates()`: 인터넷 연결이 있을 때 npm registry에서 최신 버전 여부 확인.
- `fallbackMarkdown(markdown)`: 번들 렌더러 로드 실패 시 사용하는 기본 마크다운 렌더러.
- `sanitizeHtml(html)`: DOMPurify 또는 기본 sanitization.
- `render()`: 편집 내용을 HTML로 변환하고 미리보기 갱신.
- `setStatus(message)`: 상태 메시지 갱신.
- `setUpdateStatus(message, tone)`: 문서 상태와 분리된 렌더링 라이브러리 업데이트 확인 메시지 갱신.
- `autosave()`: debounce 후 `localStorage` 저장.
- `filenameForSave()`: `.md`, `.markdown`, `.txt` 파일명은 유지하고, 지원 확장자가 없을 때만 `.md`를 붙인다.
- `downloadFile(content, filename, type, mode)`: 앱에서는 native save bridge로 저장 요청, 브라우저에서는 Blob 다운로드 실행.
- `window.deskMdSaveCompleted(filename)`: 네이티브 저장 완료 직후 화면 파일명과 `localStorage`에 저장된 파일명을 함께 갱신한다.
- `window.deskMdOpenDocument(filename, content)`: 네이티브 메뉴 열기 요청을 받아 에디터, 미리보기, 메타데이터, 자동 저장, 상태 텍스트를 갱신.
- `window.deskMdCreateNewDocument()`: 네이티브 `File > New` 메뉴가 툴바와 같은 새 문서 흐름을 재사용하도록 연결.

## 5. 렌더링 흐름

```text
사용자 입력
  -> editor input event
  -> render()
  -> bundled marked.parse() 또는 fallbackMarkdown()
  -> sanitizeHtml()
  -> preview.innerHTML 갱신
  -> 문자 수 갱신
  -> autosave()
  -> localStorage 저장
```

렌더러 선택:

- `window.marked`가 있으면 앱 번들에 포함된 `vendor/marked.umd.js` 사용.
- 로드 실패 시 내장 `fallbackMarkdown` 사용.

HTML 정리:

- `window.DOMPurify`가 있으면 DOMPurify 사용.
- 없으면 `script`, `style`, `iframe`, `object`, `embed` 제거 및 `on*`, `javascript:` 속성 제거.

### 5.1 라이브러리 업데이트 확인

앱은 런타임 렌더링에 원격 스크립트를 사용하지 않는다. 렌더링 라이브러리는 다음 로컬 파일을 사용한다.

- `vendor/marked.umd.js`: `marked 18.0.0`
- `vendor/purify.min.js`: `DOMPurify 3.3.3`
- `vendor/versions.js`: 번들 버전 메타데이터

인터넷 연결이 있으면 `checkLibraryUpdates()`가 npm registry의 `latest` metadata를 조회한다.

```text
앱 로드
  -> vendor/versions.js 로드
  -> vendor/purify.min.js 로드
  -> vendor/marked.umd.js 로드
  -> checkLibraryUpdates()
  -> https://registry.npmjs.org/{package}/latest 조회
  -> 번들 버전과 latest.version 비교
  -> 새 버전이 있으면 전용 업데이트 상태 영역에 표시
```

업데이트 확인은 알림 전용이며, 원격 JavaScript를 실행하거나 자동 교체하지 않는다.

## 6. 파일 열기 흐름

```text
열기 버튼 클릭
  -> openFile.click()
  -> WKWebView가 파일 선택 요청 생성
  -> macOS AppDelegate.runOpenPanelWithParameters()
  -> NSOpenPanel 표시
  -> 선택된 파일 URL을 WebKit에 반환
  -> input change event
  -> file.text()
  -> editor.value 갱신
  -> render()
  -> autosave()
  -> status 갱신
```

## 7. 저장 흐름

### 7.1 Save

```text
Save 버튼 또는 Cmd+S
  -> downloadFile(editor.value, filename, "text/markdown;charset=utf-8", "save")
  -> window.webkit.messageHandlers.saveFile.postMessage({ mode: "save", ... })
  -> AppDelegate.userContentController(...)
  -> currentDocumentURL이 있으면 해당 URL에 UTF-8 텍스트 저장
  -> currentDocumentURL이 없으면 NSSavePanel 표시
  -> 저장 성공 후 currentDocumentURL과 lastDocumentDirectoryURL 갱신
  -> evaluateJavaScript(...)로 저장 결과 상태 갱신
```

### 7.2 Save As

```text
Save As 버튼
  -> downloadFile(editor.value, filename, "text/markdown;charset=utf-8", "saveAs")
  -> window.webkit.messageHandlers.saveFile.postMessage({ mode: "saveAs", ... })
  -> AppDelegate.userContentController(...)
  -> NSSavePanel 표시
  -> lastDocumentDirectoryURL이 있으면 panel.directoryURL로 지정
  -> 선택한 URL에 UTF-8 텍스트 저장
  -> currentDocumentURL과 lastDocumentDirectoryURL 갱신
  -> evaluateJavaScript(...)로 저장 결과 상태 갱신
```

## 8. 자동 저장

자동 저장은 `localStorage` 기반이다.

저장 키:

- `deskmd-document`: 문서 본문.
- `deskmd-filename`: 현재 파일명.

기존 이름으로 저장된 자동 저장본이 있으면 `markdown-desk-document`, `markdown-desk-filename`을 fallback으로 읽어온다.

입력 이벤트마다 즉시 저장하지 않고 250ms debounce 후 저장한다.

앱 시작 시:

```text
localStorage에 저장본이 있으면 저장본 로드
없으면 starter 문서 로드
```

## 9. 빌드 설계

파일: `scripts/build-macos-app.sh`

빌드 산출물:

```text
dist/DeskMD.app
```

빌드 단계:

1. 기존 앱 번들 삭제.
2. `Contents/MacOS`, `Contents/Resources/Editor` 생성.
3. `clang`으로 `macos/App.m` 컴파일.
4. `Cocoa`, `WebKit`, `UniformTypeIdentifiers` 프레임워크 링크.
5. `Info.plist` 복사.
6. `index.html`, `styles.css`, `app.js`, `vendor`를 앱 리소스로 복사.
7. `AppIcon.icns`를 앱 리소스로 복사.
8. 실행 권한 부여.
9. 가능한 경우 ad-hoc codesign 수행.
10. 빌드용 `ModuleCache` 제거.

파일: `scripts/notarize-macos-app.sh`

공증 배포 단계:

1. `DEVELOPER_ID_APPLICATION`을 사용해 `build-macos-app.sh`를 hardened runtime/timestamp 서명 모드로 실행한다.
2. `dist/DeskMD.app.zip`을 생성한다.
3. `APPLE_NOTARY_PROFILE` 또는 `APPLE_ID`/`APPLE_TEAM_ID`/`APPLE_APP_SPECIFIC_PASSWORD`로 `xcrun notarytool submit --wait`를 실행한다.
4. 성공하면 `xcrun stapler staple`과 `xcrun stapler validate`를 수행한다.

release 스크립트 환경 변수:

- 필수: `DEVELOPER_ID_APPLICATION`
- 권장 인증: `APPLE_NOTARY_PROFILE`
- 대안 인증: `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`
- 선택: `DESKMD_NOTARY_PRIMARY_BUNDLE_ID`, `DESKMD_CODESIGN_ENTITLEMENTS`

## 10. 실행

현재 실행 대상:

```sh
open "dist/DeskMD.app"
```

## 11. 알려진 제약과 개선 방향

- 라이브러리 업데이트: 원격 스크립트는 실행하지 않고 최신 버전 여부만 확인한다.
- 저장 UX: 현재 문서 URL이 있으면 `Save`가 바로 저장하고, 최초 저장과 `Save As`는 `NSSavePanel`을 사용한다.
- 파일 권한: sandboxed App Store 배포를 목표로 하면 보안 스코프 북마크 처리가 필요하다.
- 테스트: 현재는 빌드/문법/서명 검증, UX smoke, 상단 툴바 레이아웃, 다크 외관 smoke, 최근 문서 메뉴 동작을 검증한다.
