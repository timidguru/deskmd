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
│   ├── generate-app-icon.js
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
5. 선택된 첫 파일의 부모 폴더를 `lastDocumentDirectoryURL`에 저장.
6. 취소하면 `completionHandler(nil)` 호출.

### 3.5 외부 링크 처리

`WKNavigationDelegate`에서 링크 클릭을 감지한다.

- `http`, `https` 링크이며 사용자가 클릭한 링크인 경우: `NSWorkspace.sharedWorkspace openURL`
- 그 외 로컬 파일 로드와 내부 리소스 로드: WebView 안에서 허용

## 4. 웹 UI 설계

### 4.1 HTML 구조

파일: `index.html`

주요 요소:

- `#status`: 저장/열기 상태 메시지.
- `#newDoc`: 새 문서 버튼.
- `#openFileButton`: 열기 버튼.
- `#openFile`: 숨겨진 파일 입력.
- `#saveMd`: 마크다운 저장 버튼.
- `#saveHtml`: HTML 저장 버튼.
- `#editor`: 편집 textarea.
- `#preview`: 렌더링된 미리보기 영역.
- `#count`: 문자 수 표시.

### 4.2 스타일 구조

파일: `styles.css`

주요 레이아웃:

- `.shell`: 앱 전체 컨테이너.
- `.topbar`: 앱 상단 상태/액션 영역.
- `.workspace`: 편집/미리보기 2열 그리드.
- `.pane`: 각 패널 공통 구조.
- `.preview`: 마크다운 렌더링 결과 스타일.
- `.preview`: 텍스트 선택과 `Cmd+C` 복사를 위해 `user-select: text`를 명시.

### 4.4 미리보기 복사

미리보기 텍스트 선택 후 `Cmd+C`를 누르면 웹 UI가 선택 텍스트를 읽어 `copyText` message handler로 전달한다. macOS 래퍼는 전달받은 문자열을 `NSPasteboard.generalPasteboard`에 `NSPasteboardTypeString`으로 기록한다.

에디터 `textarea`가 포커스된 상태에서는 이 브릿지를 사용하지 않고 기본 편집 복사를 유지한다.

### 4.5 테스트 브릿지

웹 UI는 자동 사용성 테스트를 위해 `window.deskMdTest` 객체를 제공한다. 이 객체는 버튼 좌표에 의존하지 않고 실제 DOM 버튼의 `.click()` 경로와 상태를 검증하기 위한 얇은 테스트 API다.

주요 메서드:

- `setMarkdown(markdown, filename)`: 테스트 문서 주입.
- `getPreviewText()`: 미리보기 plain text 조회.
- `getStatus()`: 상태 텍스트 조회.
- `clickNewDocument()`: `새 문서` DOM 버튼 클릭.
- `clickOpenFile()`: `열기` DOM 버튼 클릭.
- `clickSaveMarkdown()`: `MD 저장` DOM 버튼 클릭.
- `clickSaveHtml()`: `HTML 저장` DOM 버튼 클릭.
- `copyPreviewTextForTest()`: 미리보기 텍스트를 네이티브 클립보드 브릿지로 복사.

macOS 앱은 `--ux-smoke-test` 실행 인자를 받으면 WebView 로드 후 내부 JS를 평가해 렌더링과 복사 브릿지를 검증하고 종료한다. `scripts/ux-smoke-test.js`는 `dist/DeskMD.app`의 실행 파일을 이 모드로 실행한 뒤 `pbpaste`로 클립보드 결과를 확인한다.

현재 UX smoke test 검증 범위:

- 테스트 마크다운 주입 후 미리보기 렌더링 확인.
- 미리보기 텍스트 복사 브릿지 확인.
- `새 문서` 버튼의 confirm 경로 확인.
- `새 문서` 액션 호출 및 상태 확인.
- `MD 저장` 액션 호출 및 저장 payload 확인.
- `HTML 저장` 액션 호출 및 저장 payload 확인.
- `열기` 액션 호출 확인.

저장/열기 액션은 테스트 중 macOS 패널을 실제로 열지 않고 mock action log에 기록한다. 이는 모달 패널 때문에 자동 테스트가 멈추지 않게 하기 위한 테스트 전용 동작이며, 일반 실행 모드에는 적용되지 않는다.

반응형:

- `820px` 이하에서는 편집/미리보기를 세로 스택으로 전환.
- `460px` 이하에서는 브랜드 이미지를 숨기고 버튼 폭을 조정.

### 4.3 JavaScript 모듈 책임

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
- `autosave()`: debounce 후 `localStorage` 저장.
- `downloadFile(content, filename, type)`: 앱에서는 native save bridge로 저장 요청, 브라우저에서는 Blob 다운로드 실행.
- `htmlDocument()`: 내보내기용 독립 HTML 문서 생성.

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
  -> 새 버전이 있으면 상태 영역에 업데이트 가능 표시
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

### 7.1 MD 저장

```text
MD 저장 버튼 또는 Cmd+S
  -> downloadFile(editor.value, filename, "text/markdown;charset=utf-8")
  -> window.webkit.messageHandlers.saveFile.postMessage(...)
  -> AppDelegate.userContentController(...)
  -> NSSavePanel 표시
  -> lastDocumentDirectoryURL이 있으면 panel.directoryURL로 지정
  -> 선택한 URL에 UTF-8 텍스트 저장
  -> 저장된 파일의 부모 폴더를 lastDocumentDirectoryURL로 갱신
  -> evaluateJavaScript(...)로 저장 결과 상태 갱신
```

### 7.2 HTML 저장

```text
HTML 저장 버튼
  -> htmlDocument()
  -> preview.innerHTML을 독립 HTML 문서에 삽입
  -> downloadFile(..., "text/html;charset=utf-8")
  -> window.webkit.messageHandlers.saveFile.postMessage(...)
  -> NSSavePanel 표시
  -> 선택한 URL에 UTF-8 HTML 저장
  -> 저장 결과 상태 갱신
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

## 10. 실행

현재 실행 대상:

```sh
open "dist/DeskMD.app"
```

## 11. 알려진 제약과 개선 방향

- 라이브러리 업데이트: 원격 스크립트는 실행하지 않고 최신 버전 여부만 확인한다.
- 저장 UX: 현재 저장은 JavaScript bridge와 `NSSavePanel`로 처리한다. 향후에는 기존 파일 덮어쓰기와 `Save As` 구분을 추가할 수 있다.
- 파일 권한: sandboxed App Store 배포를 목표로 하면 보안 스코프 북마크 처리가 필요하다.
- 앱 아이콘: 현재 전용 앱 아이콘이 없다.
- 테스트: 현재는 빌드/문법/서명 검증 중심이다. UI 동작 자동화 테스트는 별도 추가가 필요하다.
