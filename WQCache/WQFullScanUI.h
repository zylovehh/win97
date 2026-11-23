// WQFullScanUI.h
// 完整扫描的确认框 + 进度窗（V2.9.3）。
// WQ 的完整扫描（inode 全盘扫描）只有在 UI 钩子注册后才会启动：
// WQAccess.m 的 wq_full_scan_begin 里 gFullScanConfirm 为空就直接返回 nil
// （V2.9.2 的扫描日志里那句 "full scan of App 文件夹 not started" 就是
// 这么来的——咱们 App 从来没调过 wq_set_full_scan_ui）。
// 上游 WQ Files 在 main.m 里注册 wq_confirm_full_scan /
// wq_full_scan_progress；咱们 App 是 SwiftUI，没有 main.m，就用这个文件
// 提供同一套逻辑（确认弹框 + 进度窗 + 后台任务），在清理页出现时调
// wq_full_scan_ui_install() 注册一次。
// 注意：这是咱们自己写的 UI 胶水代码，不是 WQ 原代码；WQAccess.m、
// WQScanTask.m 本体一个字没动。

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 注册完整扫描的确认回调和进度回调（只注册一次，多次调无害）。
void wq_full_scan_ui_install(void);

NS_ASSUME_NONNULL_END
