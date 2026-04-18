# DeskMD

[English](./README.md) | [한국어](./README.ko.md)

DeskMD is a lightweight Markdown editor for macOS. Write on the left, preview on the right, and save when ready.

## Features

- Split Markdown editor and live preview
- Open `.md`, `.markdown`, and `.txt` files
- Reopen recent files from `File > Open Recent`
- Save Markdown with `Cmd+S`
- Local autosave through WebView `localStorage`
- Preview text selection and `Cmd+C` clipboard copy
- Light and dark appearances that follow the macOS system setting
- Offline rendering with bundled `marked` and `DOMPurify`
- Optional latest-version check for bundled renderer libraries when internet access is available

## Requirements

- macOS 12 or later
- Xcode Command Line Tools for building
- Node.js for test scripts

DeskMD does not require Electron, a local server, or an internet connection to edit and preview Markdown.

## Download

Download the latest runnable app bundle:

- [DeskMD.app.zip](https://github.com/timidguru/deskmd/releases/download/v1.0.1/DeskMD.app.zip)

After downloading, unzip the file and open `DeskMD.app`.

## Quick Start

Build the macOS app:

```sh
npm run build:mac
```

Run it from the build output:

```sh
open "./dist/DeskMD.app"
```

The generated app bundle is:

```text
dist/DeskMD.app
```

## Development

Install dependencies:

```sh
npm install
```

Run syntax checks:

```sh
npm run check
```

Build the app:

```sh
npm run build:mac
```

Run all checks against the built app:

```sh
npm run verify
```

Run individual app tests:

```sh
npm run test:ux
npm run test:topbar
npm run test:recent
```

The UX smoke test launches `dist/DeskMD.app/Contents/MacOS/DeskMD` with `--ux-smoke-test`, verifies rendering, preview copy, and core button actions, then checks the macOS clipboard with `pbpaste`. The topbar test runs the built app at desktop and narrow window widths to guard the toolbar layout, then repeats the pass with forced dark appearance to verify dark tokens and basic text contrast. The recent documents test verifies recent file ordering, deduplication, maximum size, missing-file removal, and clearing.

## Offline Rendering

DeskMD renders Markdown with vendored browser libraries:

- `vendor/marked.umd.js`
- `vendor/purify.min.js`
- `vendor/versions.js`

The app never loads remote JavaScript for rendering. If the device is online, it only checks npm registry metadata to report whether newer bundled library versions are available.

## Project Layout

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
│   ├── recent-documents-test.js
│   ├── topbar-visual-test.js
│   └── ux-smoke-test.js
├── docs
│   ├── PRD.md
│   ├── PRD.ko.md
│   ├── LLD.md
│   └── LLD.ko.md
└── dist
    └── DeskMD.app
```

## Documents

- [Product Requirements Document](./docs/PRD.md)
- [Low-Level Design](./docs/LLD.md)

## License

[ISC](./LICENSE)
