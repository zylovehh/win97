// Win97-Bridging-Header.h
// Swift 调 WQ Files 缓存清理引擎（ObjC）的桥（V2.9）。
// WQCacheEngine.h：扫描/校验/清理引擎 + WQCacheItem。
// WQLaunchServices.h：wq_bundle_path_for_id（按 bundleID 找 .app 包路径，读图标用）。
#import "WQCache/WQCacheEngine.h"
#import "WQCache/WQLaunchServices.h"

// wq_log_text：WQ 扫描日志全文（实现在 WQCache/WQAccess.m，声明在
// WQCache/WQAccess.h）。只声明这一个函数，不整头引 WQAccess.h，免得它里面
// 大量 C 声明进 Swift。V2.9.2 清理页“扫描日志”区用。
NSString *wq_log_text(void);
