//
//  WQCacheEngine.h
//  Win97 · 壁纸匣
//
//  缓存清理的引擎：从 WQ Files（kolbicz/WQFiles，GPL-3.0-or-later）的
//  WQCache.m 里把 WQCacheCleanerViewController 的扫描、清理、校验逻辑
//  原样搬过来，只是把 UIKit 的表界面拆掉，换成给 SwiftUI 用的回调。
//  WQCacheItem、WQCacheTargetRecord 和那几个静态函数都是原文照搬；
//  界面由 App/CacheCleanerView.swift 用 SwiftUI 重写。
//  出处和协议见 WQCache/README.md；App 里缓存清理页底部也有署名。
//

#import <Foundation/Foundation.h>
#import <sys/stat.h>

NS_ASSUME_NONNULL_BEGIN

@interface WQCacheTargetRecord : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *relativePath;
@property (nonatomic) BOOL existed;
@property (nonatomic) BOOL identityKnown;
@property (nonatomic) dev_t device;
@property (nonatomic) ino_t inode;
@property (nonatomic) mode_t mode;
@end

@interface WQCacheItem : NSObject
@property (nonatomic, copy) NSString *name;        // app name or "Crash Logs"
@property (nonatomic, copy, nullable) NSString *bundleID;    // for the icon; nil for logs
@property (nonatomic, copy) NSArray<NSString *> *targets;  // dirs to purge
@property (nonatomic) unsigned long long cacheBytes;
@property (nonatomic) unsigned long long tempBytes;
@property (nonatomic) BOOL cacheKnown;
@property (nonatomic) BOOL tempKnown;
@property (nonatomic) BOOL limited;
@property (nonatomic) BOOL crashLogs;
@property (nonatomic, copy, nullable) NSString *containerPath;
@property (nonatomic) BOOL containerIdentityKnown;
@property (nonatomic) dev_t containerDevice;
@property (nonatomic) ino_t containerInode;
@property (nonatomic) mode_t containerMode;
@property (nonatomic, copy) NSArray<WQCacheTargetRecord *> *targetRecords;
@property (nonatomic) BOOL selected;
@property (nonatomic, readonly) unsigned long long bytes;
// A folder/file added to the Cache Cleaner from the file browser: its path
// in the container. (No UI adds these in Win97; kept so the scan stays verbatim.)
@property (nonatomic, copy, nullable) NSString *customRelative;
@property (nonatomic) BOOL customIsFile;
@property (nonatomic) BOOL customAutoSelect;   // selected like caches
@end

@class WQCacheEngine;

@protocol WQCacheEngineDelegate <NSObject>
- (void)cacheEngineDidUpdate:(WQCacheEngine *)engine;
@end

/// 扫描 / 清理的引擎（主线程调用；回调都在主线程上）。
/// 扫描是可续跑的（WQScanTask "clean"，落盘在 Application Support/ScanTasks）。
@interface WQCacheEngine : NSObject

@property (nonatomic, weak, nullable) id<WQCacheEngineDelegate> delegate;

/// 当前列表（扫描完才有；扫描中是上一次的结果）。
@property (nonatomic, readonly) NSArray<WQCacheItem *> *items;
/// 扫描 / 清理的进度文案（nil 表示空闲）；清理完的结果在 result 里。
@property (nonatomic, readonly, nullable) NSString *status;
/// 上一次清理的结果（"已释放 …" 或 "已停止…" 等）；开始扫描时清掉。
@property (nonatomic, readonly, nullable) NSString *result;
/// 扫描的备注（比如哪几处没扫全）；没有是 nil。
@property (nonatomic, readonly, nullable) NSString *note;
@property (nonatomic, readonly) BOOL scanning;
@property (nonatomic, readonly) BOOL cleaning;
/// 扫描进度 0…1；清理时是选中比例以外的进度条不用它。
@property (nonatomic, readonly) float scanProgress;
/// 扫描进行中找到的字节数（第一次扫描时总数往上数）。
@property (nonatomic, readonly) unsigned long long scanBytes;
/// 上次扫完的时间；没有扫过是 nil。
@property (nonatomic, readonly, nullable) NSDate *lastScanned;
@property (nonatomic, readonly) BOOL persistenceFailed;
/// 上一次清理实际释放的字节数（校验没过、一样没清就是 0）。
@property (nonatomic, readonly) unsigned long long lastFreedBytes;
/// 上一次清理有没有项目没清掉（包括校验没过直接取消的）。
@property (nonatomic, readonly) BOOL lastCleanIncomplete;

/// 首次扫描（新扫一遍；清理进行中时调用会排到清理后）。
- (void)startScan;
/// 下拉刷新：先忘掉枚举缓存和名字缓存，再重新扫。
- (void)refreshScan;
/// 进页时调用：没结果 / 上次被打断 / 结果超过 10 分钟才扫，否则不动。
- (void)startScanIfNeeded;
/// 扫描暂停 / 继续。
- (void)pauseOrResumeScan;
/// 清掉所有勾选的行（调用前 SwiftUI 先弹确认框）。
- (void)cleanSelected;
/// 清理进行中时叫停（停在当前这一项之后）。
- (void)cancelClean;

/// 确认框的文案（WQ 原话，中文从 zh-Hans.lproj 表里来）。
- (NSString *)confirmationMessageForSelectedItems;
/// 列表底部的说明文案（WQ 原话）。
- (NSString *)footerTextForSelectedItems;

@end

NS_ASSUME_NONNULL_END
