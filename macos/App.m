#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler>
@property(strong) NSWindow *window;
@property(strong) WKWebView *webView;
@property(strong) NSURL *currentDocumentURL;
@property(strong) NSURL *lastDocumentDirectoryURL;
@property(strong) NSMenu *openRecentMenu;
@property(assign) BOOL runsUXSmokeTest;
@property(assign) BOOL runsTopbarVisualTest;
@property(assign) BOOL runsRecentDocumentsTest;
@property(assign) BOOL usesRecentDocumentsTestStore;
@property(assign) BOOL forcesDarkAppearance;
@property(copy) NSString *recentDocumentsTestPhase;
@end

@implementation AppDelegate

static NSString *const DeskMDRecentDocumentsKey = @"DeskMDRecentDocuments";
static NSString *const DeskMDRecentDocumentsTestKey = @"DeskMDRecentDocumentsTest";
static NSString *const DeskMDRecentDocumentsTestMetadataKey = @"DeskMDRecentDocumentsTestMetadata";
static const NSUInteger DeskMDMaximumRecentDocuments = 5;

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  self.runsUXSmokeTest = [NSProcessInfo.processInfo.arguments containsObject:@"--ux-smoke-test"];
  self.runsTopbarVisualTest = [NSProcessInfo.processInfo.arguments containsObject:@"--topbar-visual-test"];
  self.recentDocumentsTestPhase = [self recentDocumentsTestPhaseFromArguments:NSProcessInfo.processInfo.arguments];
  self.runsRecentDocumentsTest = self.recentDocumentsTestPhase.length > 0;
  self.usesRecentDocumentsTestStore = self.runsRecentDocumentsTest;
  self.forcesDarkAppearance = [NSProcessInfo.processInfo.arguments containsObject:@"--force-dark-appearance"];
  [self setupMainMenu];

  NSAppearance *forcedAppearance = nil;
  if (self.forcesDarkAppearance) {
    forcedAppearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSApp.appearance = forcedAppearance;
  }

  WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
  configuration.defaultWebpagePreferences.allowsContentJavaScript = YES;
  WKUserContentController *contentController = [[WKUserContentController alloc] init];
  [contentController addScriptMessageHandler:self name:@"saveFile"];
  [contentController addScriptMessageHandler:self name:@"copyText"];
  [contentController addScriptMessageHandler:self name:@"documentState"];
  configuration.userContentController = contentController;

  self.webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
  self.webView.navigationDelegate = self;
  self.webView.UIDelegate = self;
  if (forcedAppearance) {
    self.webView.appearance = forcedAppearance;
  }

  NSRect frame = NSMakeRect(0, 0, 1180, 820);
  self.window = [[NSWindow alloc]
      initWithContentRect:frame
                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                  backing:NSBackingStoreBuffered
                    defer:NO];
  self.window.title = @"DeskMD";
  self.window.minSize = NSMakeSize(760, 560);
  if (forcedAppearance) {
    self.window.appearance = forcedAppearance;
  }
  self.window.contentView = self.webView;
  [self.window center];
  [self.window makeKeyAndOrderFront:nil];
  [self.window orderFrontRegardless];
  [NSApp activateIgnoringOtherApps:YES];

  [self loadEditor];
}

- (void)setupMainMenu {
  NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];

  NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"DeskMD"];
  NSString *quitTitle = [@"Quit " stringByAppendingString:NSProcessInfo.processInfo.processName];
  [appMenu addItemWithTitle:quitTitle action:@selector(terminate:) keyEquivalent:@"q"];
  appMenuItem.submenu = appMenu;
  [mainMenu addItem:appMenuItem];

  NSMenuItem *fileMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
  [fileMenu addItemWithTitle:@"New" action:@selector(newDocumentFromMenu:) keyEquivalent:@"n"].target = self;
  [fileMenu addItemWithTitle:@"Open..." action:@selector(openDocumentFromMenu:) keyEquivalent:@"o"].target = self;

  self.openRecentMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
  NSMenuItem *openRecentItem = [[NSMenuItem alloc] initWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
  openRecentItem.submenu = self.openRecentMenu;
  [fileMenu addItem:openRecentItem];
  [fileMenu addItem:[NSMenuItem separatorItem]];
  [fileMenu addItemWithTitle:@"Save" action:@selector(saveDocumentFromMenu:) keyEquivalent:@"s"].target = self;
  [fileMenu addItemWithTitle:@"Save As..." action:@selector(saveDocumentAsFromMenu:) keyEquivalent:@"S"].target = self;
  fileMenuItem.submenu = fileMenu;
  [mainMenu addItem:fileMenuItem];
  [self updateOpenRecentMenu];

  NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
  NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
  [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
  [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
  [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
  [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
  editMenuItem.submenu = editMenu;
  [mainMenu addItem:editMenuItem];

  NSApp.mainMenu = mainMenu;
}

- (void)newDocumentFromMenu:(id)sender {
  [self.webView evaluateJavaScript:@"window.deskMdCreateNewDocument && window.deskMdCreateNewDocument();" completionHandler:nil];
}

- (void)openDocumentFromMenu:(id)sender {
  NSOpenPanel *panel = [self markdownOpenPanel];
  [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
    if (result == NSModalResponseOK && panel.URL) {
      [self openDocumentAtURL:panel.URL removeIfMissing:NO];
    }
  }];
}

- (void)saveDocumentFromMenu:(id)sender {
  [self.webView evaluateJavaScript:@"document.querySelector('#saveMd')?.click();" completionHandler:nil];
}

- (void)saveDocumentAsFromMenu:(id)sender {
  [self.webView evaluateJavaScript:@"document.querySelector('#saveAs')?.click();" completionHandler:nil];
}

- (NSOpenPanel *)markdownOpenPanel {
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = YES;
  panel.canChooseDirectories = NO;
  panel.allowsMultipleSelection = NO;
  panel.allowedContentTypes = [self allowedOpenDocumentTypes];
  if (self.lastDocumentDirectoryURL) {
    panel.directoryURL = self.lastDocumentDirectoryURL;
  }
  return panel;
}

- (NSArray<UTType *> *)allowedOpenDocumentTypes {
  NSMutableArray<UTType *> *allowedTypes = [NSMutableArray arrayWithObject:UTTypePlainText];
  UTType *markdownType = [UTType typeWithFilenameExtension:@"md"];
  UTType *markdownLongType = [UTType typeWithFilenameExtension:@"markdown"];
  if (markdownType) {
    [allowedTypes addObject:markdownType];
  }
  if (markdownLongType) {
    [allowedTypes addObject:markdownLongType];
  }
  return allowedTypes;
}

- (void)openRecentDocument:(NSMenuItem *)sender {
  NSString *path = [sender.representedObject isKindOfClass:NSString.class] ? sender.representedObject : nil;
  if (!path.length) {
    return;
  }

  [self openDocumentAtURL:[NSURL fileURLWithPath:path] removeIfMissing:YES];
}

- (void)clearRecentDocuments:(id)sender {
  [NSUserDefaults.standardUserDefaults removeObjectForKey:[self recentDocumentsKey]];
  [self updateOpenRecentMenu];
}

- (void)openDocumentAtURL:(NSURL *)url removeIfMissing:(BOOL)removeIfMissing {
  NSError *error = nil;
  NSString *content = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
  if (!content) {
    if (removeIfMissing) {
      [self removeRecentDocumentURL:url];
    }
    NSString *message = error.localizedDescription ?: @"문서를 열 수 없습니다.";
    [self showNonFatalError:[NSString stringWithFormat:@"%@\n%@", url.lastPathComponent ?: @"문서", message]];
    return;
  }

  self.currentDocumentURL = url;
  self.lastDocumentDirectoryURL = url.URLByDeletingLastPathComponent;
  [self addRecentDocumentURL:url];

  NSString *script = [NSString stringWithFormat:@"window.deskMdOpenDocument(%@, %@);",
      [self jsonStringLiteral:url.lastPathComponent ?: @"document.md"],
      [self jsonStringLiteral:content]];
  [self.webView evaluateJavaScript:script completionHandler:nil];
}

- (NSArray<NSString *> *)recentDocumentPaths {
  NSArray *storedPaths = [NSUserDefaults.standardUserDefaults arrayForKey:[self recentDocumentsKey]];
  if (![storedPaths isKindOfClass:NSArray.class]) {
    return @[];
  }

  NSMutableArray<NSString *> *paths = [NSMutableArray array];
  for (id item in storedPaths) {
    if ([item isKindOfClass:NSString.class] && [item length] > 0) {
      [paths addObject:item];
    }
  }
  return paths;
}

- (void)addRecentDocumentURL:(NSURL *)url {
  if (!url.isFileURL || !url.path.length) {
    return;
  }

  NSString *path = url.path.stringByStandardizingPath;
  NSMutableArray<NSString *> *paths = [[self recentDocumentPaths] mutableCopy];
  [paths removeObject:path];
  [paths insertObject:path atIndex:0];
  if (paths.count > DeskMDMaximumRecentDocuments) {
    [paths removeObjectsInRange:NSMakeRange(DeskMDMaximumRecentDocuments, paths.count - DeskMDMaximumRecentDocuments)];
  }

  [NSUserDefaults.standardUserDefaults setObject:paths forKey:[self recentDocumentsKey]];
  [self updateOpenRecentMenu];
}

- (void)removeRecentDocumentURL:(NSURL *)url {
  if (!url.path.length) {
    return;
  }

  NSMutableArray<NSString *> *paths = [[self recentDocumentPaths] mutableCopy];
  [paths removeObject:url.path.stringByStandardizingPath];
  [NSUserDefaults.standardUserDefaults setObject:paths forKey:[self recentDocumentsKey]];
  [self updateOpenRecentMenu];
}

- (NSString *)recentDocumentsKey {
  return self.usesRecentDocumentsTestStore ? DeskMDRecentDocumentsTestKey : DeskMDRecentDocumentsKey;
}

- (void)updateOpenRecentMenu {
  if (!self.openRecentMenu) {
    return;
  }

  [self.openRecentMenu removeAllItems];
  NSArray<NSString *> *paths = [self recentDocumentPaths];
  if (!paths.count) {
    NSMenuItem *emptyItem = [[NSMenuItem alloc] initWithTitle:@"No Recent Documents" action:nil keyEquivalent:@""];
    emptyItem.enabled = NO;
    [self.openRecentMenu addItem:emptyItem];
    return;
  }

  for (NSString *path in paths) {
    NSURL *url = [NSURL fileURLWithPath:path];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:url.lastPathComponent action:@selector(openRecentDocument:) keyEquivalent:@""];
    item.target = self;
    item.representedObject = path;
    item.toolTip = path;
    [self.openRecentMenu addItem:item];
  }

  [self.openRecentMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *clearItem = [[NSMenuItem alloc] initWithTitle:@"Clear Menu" action:@selector(clearRecentDocuments:) keyEquivalent:@""];
  clearItem.target = self;
  [self.openRecentMenu addItem:clearItem];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
  return YES;
}

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  NSURL *url = navigationAction.request.URL;
  NSString *scheme = url.scheme.lowercaseString;
  BOOL isExternalLink = navigationAction.navigationType == WKNavigationTypeLinkActivated &&
      ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]);

  if (isExternalLink) {
    [[NSWorkspace sharedWorkspace] openURL:url];
    decisionHandler(WKNavigationActionPolicyCancel);
    return;
  }

  decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
  if ([message.name isEqualToString:@"copyText"]) {
    [self copyTextFromMessage:message];
    return;
  }

  if ([message.name isEqualToString:@"documentState"]) {
    [self updateDocumentStateFromMessage:message];
    return;
  }

  if (![message.name isEqualToString:@"saveFile"] || ![message.body isKindOfClass:NSDictionary.class]) {
    return;
  }

  NSDictionary *payload = (NSDictionary *)message.body;
  NSString *content = [payload[@"content"] isKindOfClass:NSString.class] ? payload[@"content"] : @"";
  NSString *filename = [payload[@"filename"] isKindOfClass:NSString.class] ? payload[@"filename"] : @"document.md";
  NSString *mode = [payload[@"mode"] isKindOfClass:NSString.class] ? payload[@"mode"] : @"save";

  [self saveContent:content suggestedFilename:filename mode:mode];
}

- (void)updateDocumentStateFromMessage:(WKScriptMessage *)message {
  if (![message.body isKindOfClass:NSDictionary.class]) {
    return;
  }

  NSDictionary *payload = (NSDictionary *)message.body;
  NSString *action = [payload[@"action"] isKindOfClass:NSString.class] ? payload[@"action"] : @"";
  if ([action isEqualToString:@"newDocument"]) {
    self.currentDocumentURL = nil;
  }
}

- (void)copyTextFromMessage:(WKScriptMessage *)message {
  NSString *text = nil;

  if ([message.body isKindOfClass:NSString.class]) {
    text = (NSString *)message.body;
  } else if ([message.body isKindOfClass:NSDictionary.class]) {
    NSDictionary *payload = (NSDictionary *)message.body;
    text = [payload[@"text"] isKindOfClass:NSString.class] ? payload[@"text"] : nil;
  }

  if (text.length == 0) {
    return;
  }

  NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
  [pasteboard clearContents];
  [pasteboard setString:text forType:NSPasteboardTypeString];
  [self notifyCopyCompleted];
}

- (void)webView:(WKWebView *)webView
    runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters
              initiatedByFrame:(WKFrameInfo *)frame
             completionHandler:(void (^)(NSArray<NSURL *> * _Nullable URLs))completionHandler {
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = YES;
  panel.canChooseDirectories = NO;
  panel.allowsMultipleSelection = parameters.allowsMultipleSelection;
  panel.allowedContentTypes = [self allowedOpenDocumentTypes];
  if (self.lastDocumentDirectoryURL) {
    panel.directoryURL = self.lastDocumentDirectoryURL;
  }

  [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
    if (result == NSModalResponseOK) {
      NSURL *selectedURL = panel.URLs.firstObject;
      if (selectedURL) {
        self.currentDocumentURL = selectedURL;
        self.lastDocumentDirectoryURL = selectedURL.URLByDeletingLastPathComponent;
        [self addRecentDocumentURL:selectedURL];
      }
      completionHandler(panel.URLs);
      return;
    }

    completionHandler(nil);
  }];
}

- (void)webView:(WKWebView *)webView
    runJavaScriptConfirmPanelWithMessage:(NSString *)message
                        initiatedByFrame:(WKFrameInfo *)frame
                       completionHandler:(void (^)(BOOL result))completionHandler {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = message.length ? message : @"계속할까요?";
  alert.informativeText = @"현재 작업을 계속할지 선택하세요.";
  alert.alertStyle = NSAlertStyleWarning;
  [alert addButtonWithTitle:@"계속"];
  [alert addButtonWithTitle:@"취소"];

  [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
    completionHandler(returnCode == NSAlertFirstButtonReturn);
  }];
}

- (void)saveContent:(NSString *)content suggestedFilename:(NSString *)filename mode:(NSString *)mode {
  if (![mode isEqualToString:@"saveAs"] && self.currentDocumentURL) {
    [self writeContent:content toURL:self.currentDocumentURL fallbackFilename:filename];
    return;
  }

  NSSavePanel *panel = [NSSavePanel savePanel];
  panel.nameFieldStringValue = filename;
  panel.canCreateDirectories = YES;
  panel.allowedContentTypes = [self allowedTypesForFilename:filename];
  if (self.lastDocumentDirectoryURL) {
    panel.directoryURL = self.lastDocumentDirectoryURL;
  }

  [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
    if (result != NSModalResponseOK || !panel.URL) {
      [self notifySaveFailed:@"저장 취소됨"];
      return;
    }

    [self writeContent:content toURL:panel.URL fallbackFilename:filename];
  }];
}

- (void)writeContent:(NSString *)content toURL:(NSURL *)url fallbackFilename:(NSString *)filename {
  NSError *error = nil;
  BOOL didWrite = [content writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error];
  if (!didWrite) {
    NSString *message = error.localizedDescription ?: @"저장 실패";
    [self notifySaveFailed:message];
    return;
  }

  self.currentDocumentURL = url;
  self.lastDocumentDirectoryURL = url.URLByDeletingLastPathComponent;
  [self addRecentDocumentURL:url];
  [self notifySaveCompleted:url.lastPathComponent ?: filename];
}

- (NSArray<UTType *> *)allowedTypesForFilename:(NSString *)filename {
  NSString *extension = filename.pathExtension.lowercaseString;
  UTType *type = nil;

  if ([extension isEqualToString:@"md"] || [extension isEqualToString:@"markdown"]) {
    type = [UTType typeWithFilenameExtension:extension];
  } else if ([extension isEqualToString:@"txt"]) {
    type = UTTypePlainText;
  }

  return type ? @[type] : @[UTTypePlainText];
}

- (void)notifySaveCompleted:(NSString *)filename {
  NSString *script = [NSString stringWithFormat:@"window.deskMdSaveCompleted(%@);", [self jsonStringLiteral:filename]];
  [self.webView evaluateJavaScript:script completionHandler:nil];
}

- (void)notifySaveFailed:(NSString *)message {
  NSString *script = [NSString stringWithFormat:@"window.deskMdSaveFailed(%@);", [self jsonStringLiteral:message]];
  [self.webView evaluateJavaScript:script completionHandler:nil];
}

- (void)notifyCopyCompleted {
  [self.webView evaluateJavaScript:@"window.deskMdCopyCompleted && window.deskMdCopyCompleted();" completionHandler:nil];
}

- (NSString *)jsonStringLiteral:(NSString *)value {
  NSData *data = [NSJSONSerialization dataWithJSONObject:@[value ?: @""] options:0 error:nil];
  NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (json.length < 2) {
    return @"\"\"";
  }

  return [json substringWithRange:NSMakeRange(1, json.length - 2)];
}

- (void)loadEditor {
  NSURL *url = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html" subdirectory:@"Editor"];
  if (!url) {
    [self showError:@"index.html을 찾을 수 없습니다."];
    return;
  }

  [self.webView loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
}

- (NSString *)recentDocumentsTestPhaseFromArguments:(NSArray<NSString *> *)arguments {
  for (NSString *argument in arguments) {
    if ([argument hasPrefix:@"--recent-documents-test-phase="]) {
      return [argument componentsSeparatedByString:@"="].lastObject ?: @"";
    }
  }

  if ([arguments containsObject:@"--recent-documents-test"]) {
    return @"single";
  }

  return @"";
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  if (self.runsRecentDocumentsTest) {
    self.runsRecentDocumentsTest = NO;
    [self runRecentDocumentsTest];
    return;
  }

  if (self.runsTopbarVisualTest) {
    self.runsTopbarVisualTest = NO;
    [self runTopbarVisualTestAtIndex:0 results:[NSMutableArray array]];
    return;
  }

  if (!self.runsUXSmokeTest) {
    return;
  }

  self.runsUXSmokeTest = NO;
  NSString *script =
      @"(() => {"
       "const fail = (message) => 'failed:' + message;"
       "window.deskMdTest.enableActionMocks();"
       "window.deskMdTest.setMarkdown('# UX Smoke\\n\\n- copy\\n- preview', 'ux-smoke.md');"
       "if (window.deskMdTest.getAppVersion() !== 'v1.0.1') { return fail('app-version:' + window.deskMdTest.getAppVersion()); }"
       "if (window.deskMdTest.getDocumentName() !== 'ux-smoke.md') { return fail('document-name:' + window.deskMdTest.getDocumentName()); }"
       "let preview = window.deskMdTest.getPreviewText();"
       "if (!preview.includes('UX Smoke') || !preview.includes('copy')) { return fail('preview:' + preview); }"
       "window.deskMdTest.setMarkdown('Paragraph before\\n\\n```\\n  code line\\nnext line\\n```', 'copy-smoke.md');"
       "const selectedPreviewText = window.deskMdTest.selectAllPreviewText();"
       "if (!selectedPreviewText.includes('\\n') || !selectedPreviewText.includes('  code line')) { return fail('copy-selection-shape:' + JSON.stringify(selectedPreviewText)); }"
       "const copyResult = window.deskMdTest.triggerPreviewCopyShortcut();"
       "if (!copyResult.defaultPrevented) { return fail('copy-shortcut-not-handled'); }"
       "if (copyResult.selectedText !== selectedPreviewText) { return fail('copy-selection-mismatch:' + JSON.stringify(copyResult)); }"
       "window.deskMdTest.disableActionMocks();"
       "window.confirm = () => true;"
       "window.deskMdTest.setMarkdown('# Needs Confirm\\n\\nBody', 'confirm-test.md');"
       "window.deskMdTest.clickNewDocument();"
       "if (window.deskMdTest.getDocumentName() !== 'document.md') { return fail('new-document-name:' + window.deskMdTest.getDocumentName()); }"
       "if (!window.deskMdTest.getPreviewText().includes('새 문서')) { return fail('new-document-confirm-path'); }"
       "window.deskMdTest.enableActionMocks();"
       "window.deskMdTest.clickNewDocument();"
       "if (!window.deskMdTest.getPreviewText().includes('새 문서')) { return fail('new-document'); }"
       "window.deskMdTest.setMarkdown('# Save Button\\n\\nBody', 'button-test.md');"
       "window.deskMdTest.clickSaveMarkdown();"
       "window.deskMdTest.clickSaveAs();"
       "window.deskMdTest.setMarkdown('# Markdown Long\\n\\nBody', 'long-form.markdown');"
       "window.deskMdTest.clickSaveMarkdown();"
       "window.deskMdTest.clickSaveAs();"
       "window.deskMdTest.setMarkdown('# Text File\\n\\nBody', 'notes.txt');"
       "window.deskMdTest.clickSaveMarkdown();"
       "window.deskMdTest.clickSaveAs();"
       "window.deskMdTest.setMarkdown('# No Extension\\n\\nBody', 'untitled');"
       "window.deskMdTest.clickSaveMarkdown();"
       "window.deskMdTest.clickSaveAs();"
       "const saveComplete = window.deskMdTest.completeSave('renamed-notes.txt');"
       "if (saveComplete.documentName !== 'renamed-notes.txt' || saveComplete.storedFileName !== 'renamed-notes.txt') { return fail('save-complete-filename:' + JSON.stringify(saveComplete)); }"
       "window.deskMdTest.clickOpenFile();"
       "const actions = window.deskMdTest.getActions();"
       "if (!actions.some((a) => a.action === 'newDocument')) { return fail('new-document-action'); }"
       "if (!actions.some((a) => a.action === 'save' && a.mode === 'save' && a.filename === 'button-test.md' && a.type.includes('markdown'))) { return fail('md-save-action:' + JSON.stringify(actions)); }"
       "if (!actions.some((a) => a.action === 'save' && a.mode === 'saveAs' && a.filename === 'button-test.md' && a.type.includes('markdown'))) { return fail('save-as-action:' + JSON.stringify(actions)); }"
       "if (!actions.some((a) => a.action === 'save' && a.mode === 'save' && a.filename === 'long-form.markdown')) { return fail('markdown-save-action:' + JSON.stringify(actions)); }"
       "if (!actions.some((a) => a.action === 'save' && a.mode === 'saveAs' && a.filename === 'long-form.markdown')) { return fail('markdown-save-as-action:' + JSON.stringify(actions)); }"
       "if (!actions.some((a) => a.action === 'save' && a.mode === 'save' && a.filename === 'notes.txt')) { return fail('txt-save-action:' + JSON.stringify(actions)); }"
       "if (!actions.some((a) => a.action === 'save' && a.mode === 'saveAs' && a.filename === 'notes.txt')) { return fail('txt-save-as-action:' + JSON.stringify(actions)); }"
       "if (!actions.some((a) => a.action === 'save' && a.mode === 'save' && a.filename === 'untitled.md')) { return fail('extensionless-save-action:' + JSON.stringify(actions)); }"
       "if (!actions.some((a) => a.action === 'save' && a.mode === 'saveAs' && a.filename === 'untitled.md')) { return fail('extensionless-save-as-action:' + JSON.stringify(actions)); }"
       "if (actions.some((a) => a.filename === 'long-form.markdown.md' || a.filename === 'notes.txt.md')) { return fail('duplicated-extension:' + JSON.stringify(actions)); }"
       "if (actions.some((a) => a.filename === 'button-test.html')) { return fail('html-save-action-removed:' + JSON.stringify(actions)); }"
       "if (!actions.some((a) => a.action === 'open')) { return fail('open-action:' + JSON.stringify(actions)); }"
       "return 'passed:' + JSON.stringify(actions);"
      "})()";

  [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
    if (error) {
      fprintf(stderr, "UX smoke test failed: %s\n", error.localizedDescription.UTF8String);
      [NSApp terminate:nil];
      return;
    }

    printf("UX smoke test result: %s\n", [result description].UTF8String);
    fflush(stdout);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [NSApp terminate:nil];
    });
  }];
}

- (void)runRecentDocumentsTest {
  if ([self.recentDocumentsTestPhase isEqualToString:@"seed"]) {
    [self seedRecentDocumentsTest];
    return;
  }

  if ([self.recentDocumentsTestPhase isEqualToString:@"verify"]) {
    [self verifyRecentDocumentsRestoreTest];
    return;
  }

  NSString *(^fail)(NSString *) = ^NSString *(NSString *message) {
    return [@"failed:" stringByAppendingString:message];
  };

  [NSUserDefaults.standardUserDefaults removeObjectForKey:[self recentDocumentsKey]];
  [self updateOpenRecentMenu];

  NSFileManager *fileManager = NSFileManager.defaultManager;
  NSURL *tempDirectory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] isDirectory:YES];
  NSError *error = nil;
  if (![fileManager createDirectoryAtURL:tempDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
    [self finishRecentDocumentsTest:fail(error.localizedDescription ?: @"temp-directory") tempDirectory:tempDirectory];
    return;
  }

  NSMutableArray<NSURL *> *urls = [NSMutableArray array];
  for (NSUInteger index = 0; index < 6; index++) {
    NSURL *url = [tempDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"recent-%lu.md", (unsigned long)index]];
    NSString *content = [NSString stringWithFormat:@"# Recent %lu\n\nBody", (unsigned long)index];
    if (![content writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
      [self finishRecentDocumentsTest:fail(error.localizedDescription ?: @"write-file") tempDirectory:tempDirectory];
      return;
    }
    [urls addObject:url];
    [self openDocumentAtURL:url removeIfMissing:NO];
  }

  NSArray<NSString *> *paths = [self recentDocumentPaths];
  if (paths.count != DeskMDMaximumRecentDocuments) {
    [self finishRecentDocumentsTest:fail([NSString stringWithFormat:@"count:%lu", (unsigned long)paths.count]) tempDirectory:tempDirectory];
    return;
  }

  if (![paths.firstObject isEqualToString:urls[5].path.stringByStandardizingPath]) {
    [self finishRecentDocumentsTest:fail(@"latest-order") tempDirectory:tempDirectory];
    return;
  }

  if ([paths containsObject:urls[0].path.stringByStandardizingPath]) {
    [self finishRecentDocumentsTest:fail(@"maximum-trim") tempDirectory:tempDirectory];
    return;
  }

  [self addRecentDocumentURL:urls[3]];
  paths = [self recentDocumentPaths];
  if (paths.count != DeskMDMaximumRecentDocuments || ![paths.firstObject isEqualToString:urls[3].path.stringByStandardizingPath]) {
    [self finishRecentDocumentsTest:fail(@"dedupe-order") tempDirectory:tempDirectory];
    return;
  }

  NSUInteger expectedMenuItems = DeskMDMaximumRecentDocuments + 2;
  if (self.openRecentMenu.numberOfItems != expectedMenuItems) {
    [self finishRecentDocumentsTest:fail([NSString stringWithFormat:@"menu-items:%ld", (long)self.openRecentMenu.numberOfItems]) tempDirectory:tempDirectory];
    return;
  }

  NSURL *missingURL = [tempDirectory URLByAppendingPathComponent:@"missing.md"];
  [self addRecentDocumentURL:missingURL];
  [self openDocumentAtURL:missingURL removeIfMissing:YES];
  if ([[self recentDocumentPaths] containsObject:missingURL.path.stringByStandardizingPath]) {
    [self finishRecentDocumentsTest:fail(@"missing-not-removed") tempDirectory:tempDirectory];
    return;
  }

  [self clearRecentDocuments:nil];
  if ([self recentDocumentPaths].count != 0 || self.openRecentMenu.numberOfItems != 1) {
    [self finishRecentDocumentsTest:fail(@"clear-menu") tempDirectory:tempDirectory];
    return;
  }

  [self finishRecentDocumentsTest:@"passed" tempDirectory:tempDirectory];
}

- (void)seedRecentDocumentsTest {
  NSString *(^fail)(NSString *) = ^NSString *(NSString *message) {
    return [@"failed:" stringByAppendingString:message];
  };

  [NSUserDefaults.standardUserDefaults removeObjectForKey:[self recentDocumentsKey]];
  [NSUserDefaults.standardUserDefaults removeObjectForKey:DeskMDRecentDocumentsTestMetadataKey];
  [self updateOpenRecentMenu];

  NSFileManager *fileManager = NSFileManager.defaultManager;
  NSURL *tempDirectory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] isDirectory:YES];
  NSError *error = nil;
  if (![fileManager createDirectoryAtURL:tempDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
    [self finishRecentDocumentsTest:fail(error.localizedDescription ?: @"temp-directory") tempDirectory:tempDirectory];
    return;
  }

  NSMutableArray<NSURL *> *urls = [NSMutableArray array];
  for (NSUInteger index = 0; index < 6; index++) {
    NSURL *url = [tempDirectory URLByAppendingPathComponent:[NSString stringWithFormat:@"recent-%lu.md", (unsigned long)index]];
    NSString *content = [NSString stringWithFormat:@"# Recent %lu\n\nBody", (unsigned long)index];
    if (![content writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
      [self finishRecentDocumentsTest:fail(error.localizedDescription ?: @"write-file") tempDirectory:tempDirectory];
      return;
    }
    [urls addObject:url];
    [self openDocumentAtURL:url removeIfMissing:NO];
  }

  NSArray<NSString *> *paths = [self recentDocumentPaths];
  if (paths.count != DeskMDMaximumRecentDocuments) {
    [self finishRecentDocumentsTest:fail([NSString stringWithFormat:@"count:%lu", (unsigned long)paths.count]) tempDirectory:tempDirectory];
    return;
  }

  if (![paths.firstObject isEqualToString:urls[5].path.stringByStandardizingPath]) {
    [self finishRecentDocumentsTest:fail(@"latest-order") tempDirectory:tempDirectory];
    return;
  }

  if ([paths containsObject:urls[0].path.stringByStandardizingPath]) {
    [self finishRecentDocumentsTest:fail(@"maximum-trim") tempDirectory:tempDirectory];
    return;
  }

  [self addRecentDocumentURL:urls[3]];
  paths = [self recentDocumentPaths];
  if (paths.count != DeskMDMaximumRecentDocuments || ![paths.firstObject isEqualToString:urls[3].path.stringByStandardizingPath]) {
    [self finishRecentDocumentsTest:fail(@"dedupe-order") tempDirectory:tempDirectory];
    return;
  }

  NSUInteger expectedMenuItems = DeskMDMaximumRecentDocuments + 2;
  if (self.openRecentMenu.numberOfItems != expectedMenuItems) {
    [self finishRecentDocumentsTest:fail([NSString stringWithFormat:@"menu-items:%ld", (long)self.openRecentMenu.numberOfItems]) tempDirectory:tempDirectory];
    return;
  }

  NSURL *missingURL = [tempDirectory URLByAppendingPathComponent:@"missing.md"];
  [self addRecentDocumentURL:missingURL];
  [self openDocumentAtURL:missingURL removeIfMissing:YES];
  paths = [self recentDocumentPaths];
  if ([paths containsObject:missingURL.path.stringByStandardizingPath]) {
    [self finishRecentDocumentsTest:fail(@"missing-not-removed") tempDirectory:tempDirectory];
    return;
  }

  NSDictionary *metadata = @{
    @"tempDirectory": tempDirectory.path ?: @"",
    @"expectedPaths": paths
  };
  [NSUserDefaults.standardUserDefaults setObject:metadata forKey:DeskMDRecentDocumentsTestMetadataKey];
  [NSUserDefaults.standardUserDefaults synchronize];

  printf("Recent documents test seed result: passed:%s\n", tempDirectory.path.UTF8String);
  fflush(stdout);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [NSApp terminate:nil];
  });
}

- (void)verifyRecentDocumentsRestoreTest {
  NSString *(^fail)(NSString *) = ^NSString *(NSString *message) {
    return [@"failed:" stringByAppendingString:message];
  };

  NSDictionary *metadata = [NSUserDefaults.standardUserDefaults dictionaryForKey:DeskMDRecentDocumentsTestMetadataKey];
  NSArray<NSString *> *expectedPaths = [metadata[@"expectedPaths"] isKindOfClass:NSArray.class] ? metadata[@"expectedPaths"] : nil;
  NSString *tempDirectoryPath = [metadata[@"tempDirectory"] isKindOfClass:NSString.class] ? metadata[@"tempDirectory"] : nil;
  NSURL *tempDirectory = tempDirectoryPath.length ? [NSURL fileURLWithPath:tempDirectoryPath isDirectory:YES] : nil;

  if (!expectedPaths.count || !tempDirectory) {
    [self finishRecentDocumentsTest:fail(@"missing-metadata") tempDirectory:tempDirectory];
    return;
  }

  NSArray<NSString *> *paths = [self recentDocumentPaths];
  if (![paths isEqualToArray:expectedPaths]) {
    [self finishRecentDocumentsTest:fail([NSString stringWithFormat:@"restore-paths:%@", paths]) tempDirectory:tempDirectory];
    return;
  }

  NSUInteger expectedMenuItems = expectedPaths.count + 2;
  if (self.openRecentMenu.numberOfItems != expectedMenuItems) {
    [self finishRecentDocumentsTest:fail([NSString stringWithFormat:@"restore-menu-items:%ld", (long)self.openRecentMenu.numberOfItems]) tempDirectory:tempDirectory];
    return;
  }

  NSMenuItem *firstItem = self.openRecentMenu.itemArray.firstObject;
  NSString *expectedTitle = [NSURL fileURLWithPath:expectedPaths.firstObject].lastPathComponent;
  if (![firstItem.title isEqualToString:expectedTitle]) {
    [self finishRecentDocumentsTest:fail([NSString stringWithFormat:@"restore-menu-title:%@", firstItem.title ?: @""]) tempDirectory:tempDirectory];
    return;
  }

  [self clearRecentDocuments:nil];
  if ([self recentDocumentPaths].count != 0 || self.openRecentMenu.numberOfItems != 1) {
    [self finishRecentDocumentsTest:fail(@"clear-menu") tempDirectory:tempDirectory];
    return;
  }

  [self finishRecentDocumentsTest:@"passed" tempDirectory:tempDirectory];
}

- (void)finishRecentDocumentsTest:(NSString *)result tempDirectory:(NSURL *)tempDirectory {
  [NSUserDefaults.standardUserDefaults removeObjectForKey:[self recentDocumentsKey]];
  [NSUserDefaults.standardUserDefaults removeObjectForKey:DeskMDRecentDocumentsTestMetadataKey];
  [self updateOpenRecentMenu];
  if (tempDirectory) {
    [NSFileManager.defaultManager removeItemAtURL:tempDirectory error:nil];
  }

  printf("Recent documents test result: %s\n", result.UTF8String);
  fflush(stdout);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [NSApp terminate:nil];
  });
}

- (void)runTopbarVisualTestAtIndex:(NSUInteger)index results:(NSMutableArray<NSString *> *)results {
  NSArray<NSDictionary *> *cases = @[
    @{@"label": @"desktop", @"width": @1180, @"height": @820, @"maxTopbarHeight": @130},
    @{@"label": @"narrow", @"width": @760, @"height": @560, @"maxTopbarHeight": @190}
  ];

  if (index >= cases.count) {
    printf("Topbar layout test result: passed:%s\n", [results componentsJoinedByString:@","].UTF8String);
    fflush(stdout);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [NSApp terminate:nil];
    });
    return;
  }

  NSDictionary *testCase = cases[index];
  NSString *label = testCase[@"label"];
  CGFloat width = [testCase[@"width"] doubleValue];
  CGFloat height = [testCase[@"height"] doubleValue];
  NSInteger maxTopbarHeight = [testCase[@"maxTopbarHeight"] integerValue];
  NSString *expectedAppearance = self.forcesDarkAppearance ? @"dark" : @"system";

  [self.window setContentSize:NSMakeSize(width, height)];

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    NSString *script = [NSString stringWithFormat:
      @"(() => {"
       "const label = %@;"
       "const maxTopbarHeight = %ld;"
       "const expectedAppearance = %@;"
       "const fail = (message) => 'failed:' + label + ':' + message;"
       "window.deskMdTest.setMarkdown('# Topbar Visual\\n\\nBody', 'a-very-long-document-name-that-should-ellipsize.md');"
       "window.deskMdTest.setUpdateStatusForTest('Renderer updates available: marked 99.0.0', 'attention');"
       "const snapshot = window.deskMdTest.getTopbarLayoutSnapshot();"
       "const visible = (name, rect) => {"
         "if (!rect) { return fail(name + '-missing'); }"
         "if (rect.display === 'none' || rect.visibility === 'hidden') { return fail(name + '-hidden'); }"
         "if (rect.width < 24 || rect.height < 24) { return fail(name + '-too-small:' + JSON.stringify(rect)); }"
         "if (rect.left < -0.5 || rect.top < -0.5 || rect.right > snapshot.viewport.width + 0.5 || rect.bottom > snapshot.viewport.height + 0.5) {"
           "return fail(name + '-offscreen:' + JSON.stringify({ viewport: snapshot.viewport, rect }));"
         "}"
         "return null;"
       "};"
       "for (const [name, rect] of [['topbar', snapshot.topbar], ['documentStrip', snapshot.documentStrip], ['actions', snapshot.actions]]) {"
         "const error = visible(name, rect);"
         "if (error) { return error; }"
       "}"
       "if (!snapshot.workspace || snapshot.workspace.top < -0.5 || snapshot.workspace.left < -0.5 || snapshot.workspace.right > snapshot.viewport.width + 0.5 || snapshot.workspace.height < 120) {"
         "return fail('workspace-bounds:' + JSON.stringify({ viewport: snapshot.viewport, workspace: snapshot.workspace }));"
       "}"
       "if (snapshot.topbar.height > maxTopbarHeight) { return fail('topbar-too-tall:' + snapshot.topbar.height); }"
       "if (snapshot.workspace.top < snapshot.topbar.bottom - 1) { return fail('workspace-overlaps-topbar:' + JSON.stringify({ topbar: snapshot.topbar, workspace: snapshot.workspace })); }"
       "const expectedButtons = ['newDoc', 'openFileButton', 'saveMd', 'saveAs'];"
       "for (const id of expectedButtons) {"
         "const button = snapshot.buttons.find((item) => item.id === id);"
         "if (!button) { return fail('button-missing:' + id); }"
         "const error = visible('button-' + id, button.rect);"
         "if (error) { return error; }"
       "}"
       "if (expectedAppearance === 'dark') {"
         "if (!window.matchMedia('(prefers-color-scheme: dark)').matches) { return fail('dark-media-query-not-matched'); }"
         "const rootStyle = window.getComputedStyle(document.documentElement);"
         "const expectedTokens = { '--app-bg': '#181713', '--panel': '#26241f', '--editor-bg': '#201e1a', '--accent-ink': '#11100e' };"
         "for (const [name, value] of Object.entries(expectedTokens)) {"
           "const actual = rootStyle.getPropertyValue(name).trim().toLowerCase();"
           "if (actual !== value) { return fail('dark-token-mismatch:' + name + ':' + actual); }"
         "}"
         "const rgb = (value) => value.slice(value.indexOf('(') + 1, value.indexOf(')')).split(',').slice(0, 3).map((part) => Number.parseFloat(part));"
         "const luminance = ([r, g, b]) => {"
           "const convert = (channel) => {"
             "const normalized = channel / 255;"
             "return normalized <= 0.03928 ? normalized / 12.92 : Math.pow((normalized + 0.055) / 1.055, 2.4);"
           "};"
           "return 0.2126 * convert(r) + 0.7152 * convert(g) + 0.0722 * convert(b);"
         "};"
         "const contrast = (foreground, background) => {"
           "const first = luminance(rgb(foreground));"
           "const second = luminance(rgb(background));"
           "const light = Math.max(first, second);"
           "const dark = Math.min(first, second);"
           "return (light + 0.05) / (dark + 0.05);"
         "};"
         "const effectiveBackground = (value, fallback) => {"
           "if (!value || value === 'transparent' || value === 'rgba(0, 0, 0, 0)') { return fallback; }"
           "return value;"
         "};"
         "const contrastPairs = ["
           "['body', window.getComputedStyle(document.body).color, window.getComputedStyle(document.body).backgroundColor],"
           "['editor', window.getComputedStyle(document.querySelector('#editor')).color, window.getComputedStyle(document.querySelector('#editor')).backgroundColor],"
           "['primary-action', window.getComputedStyle(document.querySelector('.primary-action')).color, window.getComputedStyle(document.querySelector('.primary-action')).backgroundColor],"
           "['version-badge', snapshot.textStyles.appVersion.color, effectiveBackground(snapshot.textStyles.appVersion.backgroundColor, snapshot.textStyles.topbar.backgroundColor)],"
           "['update-status', snapshot.textStyles.updateStatus.color, effectiveBackground(snapshot.textStyles.updateStatus.backgroundColor, snapshot.textStyles.topbar.backgroundColor)],"
           "['document-status', snapshot.textStyles.documentStatus.color, effectiveBackground(snapshot.textStyles.documentStatus.backgroundColor, snapshot.textStyles.topbar.backgroundColor)]"
         "];"
         "for (const [name, foreground, background] of contrastPairs) {"
           "if (contrast(foreground, background) < 4.5) { return fail('dark-contrast-low:' + name + ':' + foreground + ':' + background); }"
         "}"
         "if (snapshot.textStyles.updateStatus.display === 'none') { return fail('update-status-hidden'); }"
       "}"
       "return 'passed:' + label + ':' + JSON.stringify({ viewport: snapshot.viewport, topbar: snapshot.topbar, actions: snapshot.actions, appearance: expectedAppearance });"
      "})()",
      [self jsonStringLiteral:label], (long)maxTopbarHeight, [self jsonStringLiteral:expectedAppearance]];

    [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
      if (error) {
        fprintf(stderr, "Topbar layout test failed: %s\n", error.localizedDescription.UTF8String);
        [NSApp terminate:nil];
        return;
      }

      NSString *resultText = [result description];
      if (![resultText hasPrefix:@"passed:"]) {
        fprintf(stderr, "Topbar layout test failed: %s\n", resultText.UTF8String);
        [NSApp terminate:nil];
        return;
      }

      [results addObject:resultText];
      [self runTopbarVisualTestAtIndex:index + 1 results:results];
    }];
  });
}

- (void)showError:(NSString *)message {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"DeskMD를 열 수 없습니다.";
  alert.informativeText = message;
  alert.alertStyle = NSAlertStyleCritical;
  [alert runModal];
  [NSApp terminate:nil];
}

- (void)showNonFatalError:(NSString *)message {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"DeskMD";
  alert.informativeText = message;
  alert.alertStyle = NSAlertStyleWarning;
  [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

@end

static AppDelegate *appDelegate;

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    appDelegate = [[AppDelegate alloc] init];
    app.delegate = appDelegate;
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    [app activateIgnoringOtherApps:YES];
    [app run];
  }

  return 0;
}
