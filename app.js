const editor = document.querySelector("#editor");
const preview = document.querySelector("#preview");
const count = document.querySelector("#count");
const status = document.querySelector("#status");
const appVersion = document.querySelector("#appVersion");
const documentName = document.querySelector("#documentName");
const updateStatus = document.querySelector("#updateStatus");
const openFileButton = document.querySelector("#openFileButton");
const openFile = document.querySelector("#openFile");
const saveMd = document.querySelector("#saveMd");
const newDoc = document.querySelector("#newDoc");

const storageKey = "deskmd-document";
const fileNameKey = "deskmd-filename";
const legacyStorageKey = "markdown-desk-document";
const legacyFileNameKey = "markdown-desk-filename";

let currentFileName = localStorage.getItem(fileNameKey) || localStorage.getItem(legacyFileNameKey) || "document.md";
let saveTimer = 0;
let testActionMocks = false;
let testActions = [];

const starter = `# 새 문서

맥에서 바로 쓰는 마크다운 편집기입니다.

## 할 일

- 왼쪽에서 작성
- 오른쪽에서 미리보기
- \`⌘S\`로 .md 저장

> 파일은 브라우저에 자동 저장됩니다.
`;

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function fallbackMarkdown(markdown) {
  const lines = markdown.split("\n");
  const html = [];
  let inList = false;
  let inCode = false;
  let codeBuffer = [];

  function closeList() {
    if (inList) {
      html.push("</ul>");
      inList = false;
    }
  }

  function inline(value) {
    return escapeHtml(value)
      .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
      .replace(/\*(.+?)\*/g, "<em>$1</em>")
      .replace(/`(.+?)`/g, "<code>$1</code>")
      .replace(/\[(.+?)\]\((https?:\/\/[^)]+)\)/g, '<a href="$2" target="_blank" rel="noreferrer">$1</a>');
  }

  for (const line of lines) {
    if (line.trim().startsWith("```")) {
      if (inCode) {
        html.push(`<pre><code>${escapeHtml(codeBuffer.join("\n"))}</code></pre>`);
        codeBuffer = [];
        inCode = false;
      } else {
        closeList();
        inCode = true;
      }
      continue;
    }

    if (inCode) {
      codeBuffer.push(line);
      continue;
    }

    if (/^###\s+/.test(line)) {
      closeList();
      html.push(`<h3>${inline(line.replace(/^###\s+/, ""))}</h3>`);
    } else if (/^##\s+/.test(line)) {
      closeList();
      html.push(`<h2>${inline(line.replace(/^##\s+/, ""))}</h2>`);
    } else if (/^#\s+/.test(line)) {
      closeList();
      html.push(`<h1>${inline(line.replace(/^#\s+/, ""))}</h1>`);
    } else if (/^-\s+/.test(line)) {
      if (!inList) {
        html.push("<ul>");
        inList = true;
      }
      html.push(`<li>${inline(line.replace(/^-\s+/, ""))}</li>`);
    } else if (/^>\s?/.test(line)) {
      closeList();
      html.push(`<blockquote>${inline(line.replace(/^>\s?/, ""))}</blockquote>`);
    } else if (line.trim()) {
      closeList();
      html.push(`<p>${inline(line)}</p>`);
    } else {
      closeList();
    }
  }

  closeList();
  return html.join("\n");
}

function sanitizeHtml(html) {
  if (window.DOMPurify) {
    return DOMPurify.sanitize(html, {
      USE_PROFILES: { html: true },
      ADD_ATTR: ["target"]
    });
  }

  const template = document.createElement("template");
  template.innerHTML = html;

  template.content.querySelectorAll("script, style, iframe, object, embed").forEach((node) => {
    node.remove();
  });

  template.content.querySelectorAll("*").forEach((node) => {
    for (const attribute of [...node.attributes]) {
      const name = attribute.name.toLowerCase();
      const value = attribute.value.trim().toLowerCase();
      if (name.startsWith("on") || value.startsWith("javascript:")) {
        node.removeAttribute(attribute.name);
      }
    }
  });

  return template.innerHTML;
}

function render() {
  const markdown = editor.value;
  let html = "";

  if (window.marked) {
    marked.setOptions({
      breaks: true,
      gfm: true
    });
    html = marked.parse(markdown);
  } else {
    html = fallbackMarkdown(markdown);
  }

  preview.innerHTML = sanitizeHtml(html);
  count.textContent = `${markdown.length.toLocaleString("ko-KR")}자`;
}

function setStatus(message) {
  status.textContent = message;
}

function setUpdateStatus(message, tone = "neutral") {
  updateStatus.textContent = message;
  updateStatus.dataset.tone = tone;
}

function updateDocumentMeta() {
  const displayName = currentFileName || "document.md";
  documentName.textContent = displayName;
  document.title = `DeskMD - ${displayName}`;
}

async function checkLibraryUpdates() {
  const versions = window.deskMdVendorVersions;
  if (!versions) {
    setUpdateStatus("Renderer version metadata unavailable", "muted");
    return;
  }

  if (versions.app) {
    appVersion.textContent = `v${versions.app}`;
  }

  const checks = [
    ["marked", versions.marked],
    ["dompurify", versions.dompurify]
  ];
  const updates = [];

  try {
    await Promise.all(checks.map(async ([name, current]) => {
      const response = await fetch(`https://registry.npmjs.org/${name}/latest`, {
        cache: "no-store"
      });
      if (!response.ok) {
        return;
      }

      const latest = await response.json();
      if (latest.version && latest.version !== current) {
        updates.push(`${name} ${latest.version}`);
      }
    }));
  } catch (error) {
    setUpdateStatus("Renderer update check skipped", "muted");
    return;
  }

  if (updates.length) {
    setUpdateStatus(`Renderer updates available: ${updates.join(", ")}`, "attention");
  } else {
    setUpdateStatus("Renderer libraries up to date", "ok");
  }
}

function autosave() {
  window.clearTimeout(saveTimer);
  saveTimer = window.setTimeout(() => {
    localStorage.setItem(storageKey, editor.value);
    localStorage.setItem(fileNameKey, currentFileName);
    setStatus(`${new Date().toLocaleTimeString("ko-KR", { hour: "2-digit", minute: "2-digit" })} 자동 저장됨`);
  }, 250);
}

function recordTestAction(action) {
  if (testActionMocks) {
    testActions.push({
      ...action,
      status: status.textContent
    });
  }
}

function downloadFile(content, filename, type) {
  if (testActionMocks) {
    setStatus(`${filename} 테스트 저장 호출됨`);
    recordTestAction({
      action: "save",
      filename,
      type,
      contentLength: content.length
    });
    return;
  }

  const nativeSave = window.webkit?.messageHandlers?.saveFile;
  if (nativeSave) {
    nativeSave.postMessage({ content, filename, type });
    setStatus(`${filename} 저장 위치 선택 중`);
    return;
  }

  const blob = new Blob([content], { type });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}

window.deskMdSaveCompleted = (filename) => {
  if (/\.m(?:arkdown|d)$/i.test(filename)) {
    currentFileName = filename;
    updateDocumentMeta();
  }
  setStatus(`${filename} 저장됨`);
};

window.deskMdSaveFailed = (message) => {
  setStatus(message || "저장 실패");
};

window.deskMdCopyCompleted = () => {
  setStatus("선택한 텍스트 복사됨");
};

function openFilePicker() {
  if (testActionMocks) {
    setStatus("열기 테스트 호출됨");
    recordTestAction({ action: "open" });
    return;
  }

  openFile.click();
}

function saveMarkdown() {
  const name = currentFileName.endsWith(".md") ? currentFileName : `${currentFileName}.md`;
  downloadFile(editor.value, name, "text/markdown;charset=utf-8");
}

function createNewDocument() {
  if (!testActionMocks && editor.value.trim() && !window.confirm("현재 문서를 새 문서로 바꿀까요? 자동 저장본도 바뀝니다.")) {
    return false;
  }

  currentFileName = "document.md";
  editor.value = starter;
  render();
  updateDocumentMeta();
  autosave();
  setStatus("새 문서");
  recordTestAction({ action: "newDocument" });
  return true;
}

window.deskMdTest = {
  enableActionMocks() {
    testActionMocks = true;
    testActions = [];
  },
  disableActionMocks() {
    testActionMocks = false;
  },
  setMarkdown(markdown, filename = "test.md") {
    currentFileName = filename;
    editor.value = markdown;
    render();
    updateDocumentMeta();
    autosave();
    setStatus(`${filename} 테스트 문서`);
  },
  getMarkdown() {
    return editor.value;
  },
  getPreviewText() {
    return preview.innerText;
  },
  getStatus() {
    return status.textContent;
  },
  getCount() {
    return count.textContent;
  },
  getDocumentName() {
    return documentName.textContent;
  },
  getAppVersion() {
    return appVersion.textContent;
  },
  getUpdateStatus() {
    return updateStatus.textContent;
  },
  getActions() {
    return testActions;
  },
  clickNewDocument() {
    newDoc.click();
    return status.textContent;
  },
  clickOpenFile() {
    openFileButton.click();
  },
  clickSaveMarkdown() {
    saveMd.click();
  },
  copyPreviewTextForTest() {
    const text = preview.innerText.trim();
    const nativeCopy = window.webkit?.messageHandlers?.copyText;
    if (text && nativeCopy) {
      nativeCopy.postMessage({ text });
      return true;
    }
    return false;
  }
};

editor.addEventListener("input", () => {
  render();
  autosave();
});

openFileButton.addEventListener("click", () => {
  openFilePicker();
});

openFile.addEventListener("change", async (event) => {
  const [file] = event.target.files;
  if (!file) {
    return;
  }

  currentFileName = file.name;
  editor.value = await file.text();
  render();
  updateDocumentMeta();
  autosave();
  setStatus(`${file.name} 열림`);
  openFile.value = "";
});

saveMd.addEventListener("click", () => {
  saveMarkdown();
});

newDoc.addEventListener("click", () => {
  createNewDocument();
});

window.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
    event.preventDefault();
    saveMd.click();
    return;
  }

  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "c") {
    const activeElement = document.activeElement;
    if (activeElement === editor) {
      return;
    }

    const selectedText = window.getSelection()?.toString();
    const nativeCopy = window.webkit?.messageHandlers?.copyText;
    if (selectedText && nativeCopy) {
      event.preventDefault();
      nativeCopy.postMessage({ text: selectedText });
    }
  }
});

editor.value = localStorage.getItem(storageKey) || localStorage.getItem(legacyStorageKey) || starter;
updateDocumentMeta();
render();
setStatus("오프라인 렌더링 준비됨");
checkLibraryUpdates();
