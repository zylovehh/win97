// WQFullScanUI.m
// 完整扫描的确认框 + 进度窗（V2.9.3）。逻辑照上游 WQ Files 0.9.19 的
// main.m（WQScanWindowController、wq_confirm_full_scan、
// wq_full_scan_progress）和 WQUI.m（wq_scan_pause_for_background）抄，
// 文案改成中文；上游 main.m / WQUI.m 里的几个小助手（找最上层 VC、
// 文件数/时长文案）这边没有，就在本文件里实现。WQAccess.m、WQScanTask.m
// 本体一个字没动。

#import "WQFullScanUI.h"
#import "WQAccess.h"
#import "WQScanTask.h"
#import <UIKit/UIKit.h>

// 找当前最上层 VC（上游 main.m 的 wq_top_view_controller，原样抄）。
static UIViewController *wq_top_view_controller(void)
{
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.isKeyWindow) continue;
            UIViewController *top = window.rootViewController;
            while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
            return top;
        }
    }
    return nil;
}

// 时长文案（上游 main.m 的 wq_duration_text，改成中文）。
static NSString *wq_duration_text(double seconds)
{
    if (seconds < 90) return @"约 1 分钟";
    if (seconds < 3600) return [NSString stringWithFormat:@"约 %.0f 分钟", ceil(seconds / 60)];
    return [NSString stringWithFormat:@"约 %.1f 小时", seconds / 3600];
}

// 文件数文案（上游 main.m 的 wq_count_text，改成中文）。
static NSString *wq_count_text(int64_t n)
{
    if (n >= 100000000) return [NSString stringWithFormat:@"%.0f 亿", n / 1e8];
    if (n >= 1000000) return [NSString stringWithFormat:@"%.0f 万", n / 1e4];
    return [NSNumberFormatter localizedStringFromNumber:@(n) numberStyle:NSNumberFormatterDecimalStyle];
}

// 切后台时暂停扫描（上游 WQUI.m 的 wq_scan_pause_for_background，原样抄）。
static void wq_scan_pause_for_background(void)
{
    wq_scan_set_paused(YES);
    [WQScanTask setPaused:YES];
}

// 扫描进度窗（上游 main.m 的 WQScanWindowController，原样抄，文案改中文）。
@interface WQScanWindowController : UIViewController
- (void)updateDone:(int64_t)done total:(int64_t)total;
@end

@implementation WQScanWindowController {
    UIProgressView *_bar;
    UILabel *_status;
    CFAbsoluteTime _started;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _started = CFAbsoluteTimeGetCurrent();
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:40 weight:UIImageSymbolWeightRegular];
    icon.tintColor = UIColor.tintColor;
    UILabel *title = [UILabel new];
    title.text = @"正在扫描全部文件";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    title.adjustsFontForContentSizeCategory = YES;
    UILabel *text = [UILabel new];
    text.numberOfLines = 0;
    text.textAlignment = NSTextAlignmentCenter;
    text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    text.textColor = UIColor.secondaryLabelColor;
    text.text = @"系统不让直接列出这些文件夹，所以要把手机上的文件逐个查一遍。只第一次慢：以后只查新文件，几秒就完。\n\n扫描时别关 App，切换到别的 App 或锁屏会暂停扫描。";
    _bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _status = [UILabel new];
    _status.font = [UIFont monospacedDigitSystemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize
                                                    weight:UIFontWeightRegular];
    _status.textAlignment = NSTextAlignmentCenter;
    _status.text = @"开始扫描…";
    UIButton *hide = [UIButton buttonWithConfiguration:UIButtonConfiguration.borderedButtonConfiguration primaryAction:
        [UIAction actionWithTitle:@"隐藏" image:nil identifier:nil handler:^(UIAction *__unused a) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
    UIButtonConfiguration *stopConfig = UIButtonConfiguration.borderedButtonConfiguration;
    stopConfig.baseForegroundColor = UIColor.systemRedColor;
    UIButton *stop = [UIButton buttonWithConfiguration:stopConfig primaryAction:
        [UIAction actionWithTitle:@"停止扫描" image:nil identifier:nil handler:^(UIAction *__unused a) {
            wq_full_scan_stop();
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[hide, stop]];
    buttons.spacing = 12;
    buttons.distribution = UIStackViewDistributionFillEqually;
    UILabel *note = [UILabel new];
    note.numberOfLines = 0;
    note.textAlignment = NSTextAlignmentCenter;
    note.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    note.textColor = UIColor.tertiaryLabelColor;
    note.text = @"隐藏后扫描继续跑，扫完列表自己填上。";
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, title, text, _bar, _status, buttons, note]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-24],
        [_bar.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [buttons.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [text.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [note.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];
}

- (void)updateDone:(int64_t)done total:(int64_t)total
{
    if (total <= 0) return;
    float fraction = (float)((double)done / (double)total);
    [_bar setProgress:fraction animated:NO];
    double elapsed = CFAbsoluteTimeGetCurrent() - _started;
    NSString *left = @"";
    if (elapsed > 5 && done > 0 && done < total) {
        double remaining = elapsed * (double)(total - done) / (double)done;
        left = [NSString stringWithFormat:@" · 还剩 %@", wq_duration_text(remaining)];
    }
    _status.text = [NSString stringWithFormat:@"%.0f%%%@", fraction * 100, left];
}

@end

static WQScanWindowController *gScanWindow;
static UIBackgroundTaskIdentifier gScanBackgroundTask;   // 0 is UIBackgroundTaskInvalid

// 在扫描线程被调：切到主线程问用户，等点了再回。照上游 main.m 的
// wq_confirm_full_scan 抄，文案改中文。
static BOOL wq_confirm_full_scan(NSString *what, int64_t ids, double seconds)
{
    dispatch_semaphore_t answered = dispatch_semaphore_create(0);
    __block BOOL start = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = wq_top_view_controller();
        if (!top) { dispatch_semaphore_signal(answered); return; }   // 不在前台：不经问就扫
        // what 是 WQ 传来的名字（"the app folders" / "Internal Daemons" /
        // 文件夹名，WQLocalized 翻过也可能是中文），是英文就翻成中文再显示。
        NSString *whatCN = what;
        if ([what isEqualToString:@"the app folders"]) whatCN = @"应用文件夹";
        else if ([what isEqualToString:@"Internal Daemons"]) whatCN = @"内部守护进程";
        NSString *message = [NSString stringWithFormat:@"要列出 %@，得把手机上的文件逐个查一遍：%@ 个文件，%@。\n\n只第一次要这么久，以后只查新文件，几秒就完。\n\n扫描时别关 App。", whatCN, wq_count_text(ids), wq_duration_text(seconds)];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"完整扫描？" message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"以后再说" style:UIAlertActionStyleCancel handler:^(UIAlertAction *__unused a) {
            dispatch_semaphore_signal(answered);
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"开始扫描" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__unused a) {
            start = YES;
            // 切走时多争取一点后台时间（系统大约给 30 秒）。
            if (gScanBackgroundTask == UIBackgroundTaskInvalid) {
                gScanBackgroundTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"WQ full scan" expirationHandler:^{
                    wq_scan_pause_for_background();   // 后台时间用完了
                    [UIApplication.sharedApplication endBackgroundTask:gScanBackgroundTask];
                    gScanBackgroundTask = UIBackgroundTaskInvalid;
                }];
            }
            WQScanWindowController *window = [WQScanWindowController new];
            window.modalPresentationStyle = UIModalPresentationPageSheet;
            window.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                                                          UISheetPresentationControllerDetent.largeDetent];
            window.sheetPresentationController.prefersGrabberVisible = YES;
            gScanWindow = window;
            dispatch_semaphore_signal(answered);
            // 等弹框收起来再 present（弹框还没收时 present 会失败）。
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIViewController *host = wq_top_view_controller();
                if (gScanWindow == window && host && host != window) [host presentViewController:window animated:YES completion:nil];
            });
        }]];
        [top presentViewController:alert animated:YES completion:nil];
    });
    dispatch_semaphore_wait(answered, DISPATCH_TIME_FOREVER);
    return start;
}

// 扫描进度回调（上游 main.m 的 wq_full_scan_progress，原样抄）。
static void wq_full_scan_progress(int64_t done, int64_t total, BOOL finished)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!finished) { [gScanWindow updateDone:done total:total]; return; }
        WQScanWindowController *window = gScanWindow;
        gScanWindow = nil;
        if (window.presentingViewController && !window.isBeingDismissed) [window dismissViewControllerAnimated:YES completion:nil];
        if (gScanBackgroundTask != UIBackgroundTaskInvalid) {
            // 在后台扫完：其他扫描现在也暂停。
            if (UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) wq_scan_pause_for_background();
            [UIApplication.sharedApplication endBackgroundTask:gScanBackgroundTask];
            gScanBackgroundTask = UIBackgroundTaskInvalid;
        }
    });
}

void wq_full_scan_ui_install(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        wq_set_full_scan_ui(wq_confirm_full_scan, wq_full_scan_progress);
    });
}
