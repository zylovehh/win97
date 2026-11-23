# 缓存清理 · 来源说明

缓存清理功能移植自 **WQ Files**（kolbicz/WQFiles，https://github.com/kolbicz/WQFiles），
遵循 **GPL-3.0** 开源协议（协议全文见 `LICENSE-GPL-3.0.txt`）。
App 里缓存清理页底部也有同一行署名，用户看得见。

## 原样拷过来的文件（一个字没改）

- `WQAccess.h` / `WQAccess.m`：沙箱外文件访问（worse_query 手法）、枚举、测量、清理。
- `WQLaunchServices.h` / `WQLaunchServices.m`：App 名字、图标信息、容器标识。
- `WQScanTask.h` / `WQScanTask.m`：可续跑的扫描任务（进度、续跑、落盘）。
- `WQScanJournal.h`：扫描落盘（只有头文件，全是 inline 函数）。
- `WQAccessSafety.h` / `WQCacheSafety.h`：路径安全检查（只有头文件，全是 inline 函数）。
- `WQCore.h` / `WQCore.m`：`WQPatchRangeValid` 等小工具（`WQAccess.m` 用到它）。
- `WQLocalization.h` / `WQLocalization.m`：文案查表（`WQLocalized`）。
- `zh-Hans.lproj/Localizable.strings`：WQ 的中文文案原表，清理页的中文都从这里来。
- `LICENSE-GPL-3.0.txt`：GPL-3.0 协议全文。

## 改过的部分（只改必须改的那层）

- `WQCacheEngine.h` / `WQCacheEngine.m`：新写的壳。
  扫描、清理、校验、量大小的逻辑原样照搬 WQ Files 的 `WQCache.m`
 （`WQCacheCleanerViewController` 里那套），只是把 UIKit 的表界面拆掉，
  换成给 SwiftUI 用的回调（delegate）；`WQCacheItem`、`WQCacheTargetRecord`
  和那几个静态函数都是原文照搬。
  另外从 `WQUI.m` 里只搬了四个不带界面的小函数（`wq_io`、`wq_scan_queue`、
  `wq_scan_read`、`wq_size_text`），原文照抄，文件头里注明了出处。

## 没搬的东西（这次不要）

- WQ 的整套 UIKit 界面（`WQCacheCleanerViewController` 的表、cell、搜索、
  右键菜单）和文件浏览器：界面由咱们的 SwiftUI 重写（`App/CacheCleanerView.swift`）。
- “允许删除”总闸：咱们不要这道闸。
- 从文件浏览器“添加到缓存清理”的自定义目标：这次不做，扫描代码里相关分支
  留着（没存过的目标是空的，不影响扫描）。
- 崩溃日志那行：在 iOS 27.0.1 上因权限问题读不到，WQ 那边也是直接不显示，
  咱们这版也没有，这不是 bug。
