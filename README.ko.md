# DeskMD

[English](./README.md) | [한국어](./README.ko.md)

DeskMD는 macOS용 가벼운 마크다운 에디터입니다. 왼쪽에서 문서를 작성하고, 오른쪽에서 미리보기를 확인한 뒤, 필요한 시점에 저장할 수 있습니다.

## 기능

- 마크다운 편집기와 실시간 미리보기 분할 화면
- `.md`, `.markdown`, `.txt` 파일 열기
- `Cmd+S`로 마크다운 저장
- 현재 미리보기를 HTML로 내보내기
- WebView `localStorage` 기반 로컬 자동 저장
- 미리보기 텍스트 선택 후 `Cmd+C`로 클립보드 복사
- 앱에 포함된 `marked`, `DOMPurify`를 사용하는 오프라인 렌더링
- 인터넷 연결이 있을 때 렌더링 라이브러리 최신 버전 여부 확인

## 요구사항

- macOS 12 이상
- 빌드를 위한 Xcode Command Line Tools
- 테스트 스크립트 실행을 위한 Node.js

DeskMD는 Markdown을 편집하고 미리보기 위해 Electron, 로컬 서버, 인터넷 연결을 요구하지 않습니다.

## 다운로드

바로 실행할 수 있는 앱 번들을 내려받을 수 있습니다:

- [DeskMD.app.zip](https://github.com/timidguru/deskmd/releases/download/v1.0.1/DeskMD.app.zip)

다운로드 후 압축을 풀고 `DeskMD.app`을 실행하면 됩니다.

## 빠른 시작

macOS 앱을 빌드합니다:

```sh
npm run build:mac
```

빌드된 앱을 실행합니다:

```sh
open "./dist/DeskMD.app"
```

생성되는 앱 번들은 다음 위치에 있습니다:

```text
dist/DeskMD.app
```

## 개발

의존성을 설치합니다:

```sh
npm install
```

문법 검사를 실행합니다:

```sh
npm run check
```

앱을 빌드합니다:

```sh
npm run build:mac
```

빌드된 앱을 대상으로 UX smoke test를 실행합니다:

```sh
npm run test:ux
```

UX smoke test는 `dist/DeskMD.app/Contents/MacOS/DeskMD`를 `--ux-smoke-test` 인자로 실행합니다. 렌더링, 미리보기 복사, 주요 버튼 동작을 검증한 뒤 macOS 클립보드를 `pbpaste`로 확인합니다.

## 오프라인 렌더링

DeskMD는 앱에 포함된 브라우저 라이브러리로 Markdown을 렌더링합니다:

- `vendor/marked.umd.js`
- `vendor/purify.min.js`
- `vendor/versions.js`

렌더링을 위해 원격 JavaScript를 로드하지 않습니다. 기기가 온라인이면 npm registry metadata만 조회해 포함된 라이브러리보다 새로운 버전이 있는지 알려줍니다.

## 프로젝트 구조

```text
.
├── app.js
├── index.html
├── styles.css
├── vendor
├── macos
│   ├── App.m
│   └── Info.plist
├── scripts
│   ├── build-macos-app.sh
│   └── ux-smoke-test.js
├── docs
│   ├── PRD.md
│   ├── PRD.ko.md
│   ├── LLD.md
│   └── LLD.ko.md
└── dist
    └── DeskMD.app
```

## 문서

- [제품 요구사항 문서](./docs/PRD.ko.md)
- [Low-Level Design](./docs/LLD.ko.md)

## 라이선스

[ISC](./LICENSE)
