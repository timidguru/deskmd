#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler>
@property(strong) NSWindow *window;
@property(strong) WKWebView *webView;
@property(strong) NSURL *currentDocumentURL;
@property(strong) NSURL *lastDocumentDirectoryURL;
@property(assign) BOOL runsUXSmokeTest;
@property(assign) BOOL runsTopbarVisualTest;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  [self setupMainMenu];
  self.runsUXSmokeTest = [NSProcessInfo.processInfo.arguments containsObject:@"--ux-smoke-test"];
  self.runsTopbarVisualTest = [NSProcessInfo.processInfo.arguments containsObject:@"--topbar-visual-test"];

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

  NSRect frame = NSMakeRect(0, 0, 1180, 820);
  self.window = [[NSWindow alloc]
      initWithContentRect:frame
                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                  backing:NSBackingStoreBuffered
                    defer:NO];
  self.window.title = @"DeskMD";
  self.window.minSize = NSMakeSize(760, 560);
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
  NSMutableArray<UTType *> *allowedTypes = [NSMutableArray arrayWithObject:UTTypePlainText];
  UTType *markdownType = [UTType typeWithFilenameExtension:@"md"];
  UTType *markdownLongType = [UTType typeWithFilenameExtension:@"markdown"];
  if (markdownType) {
    [allowedTypes addObject:markdownType];
  }
  if (markdownLongType) {
    [allowedTypes addObject:markdownLongType];
  }
  panel.allowedContentTypes = allowedTypes;

  [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
    if (result == NSModalResponseOK) {
      NSURL *selectedURL = panel.URLs.firstObject;
      if (selectedURL) {
        self.currentDocumentURL = selectedURL;
        self.lastDocumentDirectoryURL = selectedURL.URLByDeletingLastPathComponent;
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

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
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
       "if (!window.deskMdTest.copyPreviewTextForTest()) { return fail('copy'); }"
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
       "window.deskMdTest.clickOpenFile();"
       "const actions = window.deskMdTest.getActions();"
       "if (!actions.some((a) => a.action === 'newDocument')) { return fail('new-document-action'); }"
       "if (!actions.some((a) => a.action === 'save' && a.mode === 'save' && a.filename === 'button-test.md' && a.type.includes('markdown'))) { return fail('md-save-action:' + JSON.stringify(actions)); }"
       "if (!actions.some((a) => a.action === 'save' && a.mode === 'saveAs' && a.filename === 'button-test.md' && a.type.includes('markdown'))) { return fail('save-as-action:' + JSON.stringify(actions)); }"
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

  [self.window setContentSize:NSMakeSize(width, height)];

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    NSString *script = [NSString stringWithFormat:
      @"(() => {"
       "const label = %@;"
       "const maxTopbarHeight = %ld;"
       "const fail = (message) => 'failed:' + label + ':' + message;"
       "window.deskMdTest.setMarkdown('# Topbar Visual\\n\\nBody', 'a-very-long-document-name-that-should-ellipsize.md');"
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
       "return 'passed:' + label + ':' + JSON.stringify({ viewport: snapshot.viewport, topbar: snapshot.topbar, actions: snapshot.actions });"
      "})()",
      [self jsonStringLiteral:label], (long)maxTopbarHeight];

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
