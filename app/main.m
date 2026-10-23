// 美筑智管 iOS 壳 —— 把单文件网页包成原生 App（WKWebView）
// 目标：iPhone 15 Pro / iOS 17.0 / TrollStore 安装
// v2.1：新增 JS 桥（导出文件直接写入「文件」App），修复 blob 下载在 WKWebView 不落地的问题
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate, WKNavigationDelegate, WKDownloadDelegate, WKScriptMessageHandler>
@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) WKWebView *webView;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    cfg.allowsInlineMediaPlayback = YES;
    if (@available(iOS 14.0, *)) {
        cfg.defaultWebpagePreferences.allowsContentJavaScript = YES;
    }
    // JS 桥：网页可通过 window.webkit.messageHandlers.meizhu 调用原生保存
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:self name:@"meizhu"];
    cfg.userContentController = ucc;
    // 让 localStorage 持久可用（file:// 下需要非临时数据存储）
    if (@available(iOS 17.0, *)) {
        cfg.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    }

    self.webView = [[WKWebView alloc] initWithFrame:self.window.bounds configuration:cfg];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.navigationDelegate = self;
    self.webView.opaque = NO;
    self.webView.backgroundColor = [UIColor colorWithRed:15/255.0 green:22/255.0 blue:38/255.0 alpha:1.0];
    self.webView.scrollView.backgroundColor = self.webView.backgroundColor;

    UIViewController *vc = [UIViewController new];
    vc.view = self.webView;
    vc.view.backgroundColor = self.webView.backgroundColor;

    NSString *path = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"];
    NSURL *dir = [NSURL fileURLWithPath:[path stringByDeletingLastPathComponent] isDirectory:YES];
    [self.webView loadFileURL:[NSURL fileURLWithPath:path] allowingReadAccessToURL:dir];

    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {}

#pragma mark - JS 桥：接收网页发来的文件（导出 Excel/CSV → 写入「文件」App）

- (NSString *)jsQuote:(NSString *)s {
    NSString *e = [s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    e = [e stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    e = [e stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    e = [e stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    return [NSString stringWithFormat:@"'%@'", e];
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"meizhu"]) return;
    NSDictionary *body = message.body;
    if (![body isKindOfClass:[NSDictionary class]]) return;
    NSString *action = [body[@"action"] isKindOfClass:[NSString class]] ? body[@"action"] : @"";
    if (![action isEqualToString:@"saveFile"]) return;

    NSString *name = [body[@"name"] isKindOfClass:[NSString class]] ? body[@"name"] : @"导出文件.xlsx";
    if (name.length == 0) name = @"导出文件.xlsx";
    name = [name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    name = [name stringByReplacingOccurrencesOfString:@":" withString:@"_"];

    NSString *b64 = [body[@"data"] isKindOfClass:[NSString class]] ? body[@"data"] : @"";
    NSData *data = [[NSData alloc] initWithBase64EncodedString:b64 options:NSDataBase64DecodingIgnoreUnknownCharacters];

    NSURL *docs = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *dest = [docs URLByAppendingPathComponent:name];
    [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
    BOOL ok = (data.length > 0) && [data writeToURL:dest atomically:YES];

    NSString *js = [NSString stringWithFormat:@"window.__onNativeSave && window.__onNativeSave(%@, %@);", ok ? @"true" : @"false", [self jsQuote:name]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView evaluateJavaScript:js completionHandler:nil];
    });
}

#pragma mark - 下载（兼容 http(s) 下载；blob 下载由上面的 JS 桥处理）

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (navigationAction.shouldPerformDownload) {
        decisionHandler(WKNavigationActionPolicyDownload);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (!navigationResponse.canShowMIMEType) {
        decisionHandler(WKNavigationResponsePolicyDownload);
        return;
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response suggestedFilename:(NSString *)suggestedFilename completionHandler:(void (^)(NSURL * _Nullable))completionHandler API_AVAILABLE(ios(14.5)) {
    NSURL *docs = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *dest = [docs URLByAppendingPathComponent:suggestedFilename];
    [[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
    completionHandler(dest);
}

- (void)downloadDidFinish:(WKDownload *)download API_AVAILABLE(ios(14.5)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"导出完成"
            message:@"文件已保存到「文件」App → 我的 iPhone → 美筑智管"
            preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
        [self.window.rootViewController presentViewController:ac animated:YES completion:nil];
    });
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}