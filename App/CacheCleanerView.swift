// CacheCleanerView.swift
// 缓存清理页（V2.9）：底层扫描/校验/清理用 WQ Files 的引擎（WQCache/WQCacheEngine），
// 界面是 SwiftUI，照确认过的预览画。
// 自己的 App 那行不走引擎（运行中的文件变了会被引擎的身份校验拦住），
// 四项（预览视频/封面图/目录数据/临时文件）用自家 API 量、自己清。
// 署名在页底：清理功能基于 WQ Files（kolbicz），GPL-3.0。

import SwiftUI
import UIKit

extension Notification.Name {
    /// 清理完成后通知目录页刷新。
    static let win97CacheCleaned = Notification.Name("win97.cacheCleaned")
}

// MARK: - App 图标

/// 从 .app 包里读图标文件（WQ 的 wq_app_icon 不搬，Swift 里直接读）。
/// 图标按需读、读完缓存，拿不到就显示色块 + 名字首字。
enum AppIconLoader {
    private static let cache = NSCache<NSString, UIImage>()

    static func icon(for bundleID: String?) -> UIImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = cache.object(forKey: bundleID as NSString) { return cached }
        guard let bundlePath = wq_bundle_path_for_id(bundleID) else { return nil }
        guard let plist = NSDictionary(contentsOfFile: bundlePath + "/Info.plist"),
              let icons = plist["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.first else { return nil }
        for suffix in ["@3x.png", "@2x.png", ".png"] {
            let path = bundlePath + "/" + name + suffix
            if let image = UIImage(contentsOfFile: path) {
                cache.setObject(image, forKey: bundleID as NSString)
                return image
            }
        }
        return nil
    }
}

// MARK: - 自己的 App 缓存四项

struct OwnCacheSubItem: Identifiable {
    let id: String   // "video" / "cover" / "catalog" / "tmp"
    let name: String
    let detail: String
    let color: Color
    let glyph: String
    var bytes: UInt64
    var selected: Bool
}

enum OwnCache {
    static func directorySize(_ url: URL) -> UInt64 {
        var total: UInt64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += UInt64(values.fileSize ?? 0)
        }
        return total
    }

    static func deleteContents(of url: URL) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil) else { return }
        for item in items {
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// 预览视频走 URLCache（App 代码里 CatalogModel:528 就是拿 URLCache 清视频）。
    static func videoBytes(catalogBytes: UInt64) -> UInt64 {
        let total = UInt64(max(0, URLCache.shared.currentDiskUsage))
        return total > catalogBytes ? total - catalogBytes : 0
    }

    /// 目录数据：用已知目录地址去 URLCache 里探 catalog.json 的大小。
    /// CatalogStore 是 @MainActor，catalogHosts/catalogPath 只能在主线程读，
    /// 所以这两个静态方法也标 @MainActor（调用处在 Task.detached 里要走 MainActor.run）。
    @MainActor static func catalogBytes() -> UInt64 {
        var total: UInt64 = 0
        for host in CatalogStore.catalogHosts {
            guard let url = URL(string: host + "/" + CatalogStore.catalogPath) else { continue }
            if let response = URLCache.shared.cachedResponse(for: URLRequest(url: url)) {
                total += UInt64(response.data.count)
            }
        }
        return total
    }

    @MainActor static func clearCatalogCache() {
        for host in CatalogStore.catalogHosts {
            guard let url = URL(string: host + "/" + CatalogStore.catalogPath) else { continue }
            URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
        }
    }
}

// MARK: - 大小文字

func wqSizeText(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

// MARK: - 模型

@MainActor
final class CacheCleanerModel: NSObject, ObservableObject, WQCacheEngineDelegate {
    let engine = WQCacheEngine()

    @Published var items: [WQCacheItem] = []
    @Published var status: String?
    @Published var scanning = false
    @Published var cleaning = false
    @Published var scanProgress: Float = 0
    @Published var scanBytes: UInt64 = 0
    @Published var lastScanned: Date?
    @Published var persistenceFailed = false

    @Published var query = ""
    @Published var ownItems: [OwnCacheSubItem] = []
    @Published var ownExpanded = false
    @Published var icons: [String: UIImage] = [:]

    /// 自己的 App 在引擎列表里的那一行（没扫出来就是 nil）。
    @Published var ownEngineItem: WQCacheItem?

    @Published var showConfirm = false
    @Published var showLimitedAlert = false
    @Published var resultBanner: String?

    /// 清理进行中（引擎清理 + 自己四项一起算一次）。
    private var cleanInFlight = false
    /// 这次有没有真的让引擎清东西（没让引擎清时，它的 lastFreedBytes 是上次的旧值，不能算）。
    private var engineCleanRan = false
    private var ownFreed: UInt64 = 0

    override init() {
        super.init()
        engine.delegate = self
        ownItems = [
            OwnCacheSubItem(id: "video", name: "预览视频", detail: "App 里缓存的壁纸预览视频", color: Color(hex: "#5AA9FF"), glyph: "视", bytes: 0, selected: true),
            OwnCacheSubItem(id: "cover", name: "封面图", detail: "目录封面缩略图（上限 50 MB）", color: Color(hex: "#00C2A8"), glyph: "封", bytes: 0, selected: true),
            OwnCacheSubItem(id: "catalog", name: "目录数据", detail: "目录表（catalog.json）", color: Color(hex: "#7A5CFF"), glyph: "目", bytes: 0, selected: true),
            OwnCacheSubItem(id: "tmp", name: "临时文件", detail: "App 临时目录里的文件", color: Color(hex: "#FF8A4C"), glyph: "临", bytes: 0, selected: true),
        ]
    }

    var ownBundleID: String { Bundle.main.bundleIdentifier ?? "" }

    /// 自己的 App 行（引擎那行，或引擎没扫出来时用四项拼的合成行）。
    var ownTotalBytes: UInt64 { ownItems.reduce(0) { $0 + $1.bytes } }
    var ownSelectedBytes: UInt64 { ownItems.filter(\.selected).reduce(0) { $0 + $1.bytes } }
    var ownAnySelected: Bool { ownItems.contains(where: \.selected) }

    /// 除自己外的引擎行。
    var otherItems: [WQCacheItem] { items.filter { $0.bundleID != ownBundleID } }

    /// 搜索过滤后的其他行。
    var visibleOtherItems: [WQCacheItem] {
        guard !query.isEmpty else { return otherItems }
        let q = query.lowercased()
        return otherItems.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || ($0.bundleID?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var ownRowVisible: Bool {
        query.isEmpty || "壁纸匣".localizedCaseInsensitiveContains(query.lowercased())
    }

    /// 全部行（自己 + 别人）的字节总数。
    var totalBytes: UInt64 {
        otherItems.reduce(0) { $0 + $1.bytes } + ownTotalBytes
    }

    /// 已选的字节总数（自己四项 + 别人勾上的行）。
    var selectedBytes: UInt64 {
        otherItems.filter(\.selected).reduce(0) { $0 + $1.bytes } + ownSelectedBytes
    }

    /// 已选的行数（自己算一行，别人按行算）。
    var selectedCount: Int {
        otherItems.filter(\.selected).count + (ownAnySelected ? 1 : 0)
    }

    var totalCount: Int { otherItems.count + 1 }

    var cleanDisabled: Bool { selectedBytes == 0 || scanning || cleaning }

    // MARK: 扫描

    func startIfNeeded() {
        engine.startScanIfNeeded()
        Task { await measureOwnItems() }
    }

    func refresh() {
        engine.refreshScan()
        Task { await measureOwnItems() }
    }

    /// 量自己四项（在后台跑，量完回主线程写）。
    func measureOwnItems() async {
        let measured = await Task.detached {
            let catalog = await MainActor.run { OwnCache.catalogBytes() }
            let video = OwnCache.videoBytes(catalogBytes: catalog)
            let cover = ThumbnailDiskCache.shared.totalBytes()
            let tmp = OwnCache.directorySize(URL(fileURLWithPath: NSTemporaryDirectory()))
            return (video: video, cover: cover, catalog: catalog, tmp: tmp)
        }.value
        for i in ownItems.indices {
            switch ownItems[i].id {
            case "video": ownItems[i].bytes = measured.video
            case "cover": ownItems[i].bytes = measured.cover
            case "catalog": ownItems[i].bytes = measured.catalog
            case "tmp": ownItems[i].bytes = measured.tmp
            default: break
            }
        }
    }

    // MARK: 引擎回调（主线程）

    func cacheEngineDidUpdate(_ engine: WQCacheEngine) {
        items = engine.items
        status = engine.status
        scanning = engine.scanning
        cleaning = engine.cleaning
        scanProgress = engine.scanProgress
        scanBytes = engine.scanBytes
        lastScanned = engine.lastScanned
        persistenceFailed = engine.persistenceFailed
        ownEngineItem = items.first { $0.bundleID == ownBundleID }
        // 自己那行的勾选跟四项走（四项有勾就当整行勾了，确认框和页脚才算得对）。
        ownEngineItem?.selected = ownAnySelected
        // 清理刚结束（result 出来了才算，引擎先发一次扫描开始的通知、result 还是空的）。
        if cleanInFlight, !engine.cleaning, let engineResult = engine.result {
            cleanInFlight = false
            finishClean(engineResult: engineResult)
        }
    }

    // MARK: 选择

    func setAllSelected(_ selected: Bool) {
        for item in visibleOtherItems where !item.limited {
            item.selected = selected
        }
        // 自己那行被搜索藏起来时不跟着动（只对看得见的行全选/全不选）。
        if ownRowVisible {
            for i in ownItems.indices { ownItems[i].selected = selected }
        }
        ownEngineItem?.selected = ownAnySelected
    }

    func toggleOwnItem(_ id: String) {
        guard let i = ownItems.firstIndex(where: { $0.id == id }) else { return }
        ownItems[i].selected.toggle()
        ownEngineItem?.selected = ownAnySelected
    }

    func toggleOwnRow() {
        let target = !ownAnySelected
        for i in ownItems.indices { ownItems[i].selected = target }
        ownEngineItem?.selected = target
    }

    func loadIcon(for bundleID: String?) {
        guard let bundleID, !bundleID.isEmpty, icons[bundleID] == nil else { return }
        Task.detached { [weak self] in
            guard let image = AppIconLoader.icon(for: bundleID) else { return }
            await MainActor.run { self?.icons[bundleID] = image }
        }
    }

    // MARK: 清理

    var confirmationMessage: String {
        engine.confirmationMessageForSelectedItems()
    }

    var footerText: String {
        engine.footerTextForSelectedItems()
    }

    /// 确认框点了“清理”：先清自己四项，再把引擎那边的勾上的行交给引擎清。
    func startClean() {
        showConfirm = false
        ownFreed = cleanOwnSelected()
        // 自己那行不进引擎的清理名单（引擎会因运行中文件变化校验失败）。
        ownEngineItem?.selected = false
        let engineHasSelection = otherItems.contains { $0.selected }
        if !engineHasSelection {
            // 只清了自己四项，引擎那边没活，直接收尾。
            finishClean(engineResult: nil)
            return
        }
        cleanInFlight = true
        engineCleanRan = true
        engine.cleanSelected()
    }

    /// 清自己四项（按量到的数算释放了多少；目录数据先清、预览视频再清，
    /// 因为预览视频是整桶清，会把目录数据那份也带走；四项全选时把
    /// Library/Caches 里其余杂文件也一并清掉）。
    private func cleanOwnSelected() -> UInt64 {
        let selected = Dictionary(uniqueKeysWithValues: ownItems.map { ($0.id, $0.selected) })
        let bytes = Dictionary(uniqueKeysWithValues: ownItems.map { ($0.id, $0.bytes) })
        let allSelected = ownItems.allSatisfy(\.selected)
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        // 其余杂文件：整个 Caches 目录减去四项里已算过的部分（量清之前算）。
        var miscBytes: UInt64 = 0
        if allSelected {
            let cachesSize = OwnCache.directorySize(cachesDir)
            let known = (bytes["video"] ?? 0) + (bytes["catalog"] ?? 0) + (bytes["cover"] ?? 0)
            miscBytes = cachesSize > known ? cachesSize - known : 0
        }
        var freed: UInt64 = 0
        if selected["catalog"] == true {
            freed += bytes["catalog"] ?? 0
            OwnCache.clearCatalogCache()
        }
        if selected["video"] == true {
            freed += bytes["video"] ?? 0
            URLCache.shared.removeAllCachedResponses()
        }
        if allSelected {
            freed += (bytes["cover"] ?? 0) + miscBytes
            // 封面图走 ThumbnailDiskCache 清（只清里面的文件，目录本身留着，
            // 删了目录缩略图缓存就写不进去了）；其余杂文件直接删。
            ThumbnailDiskCache.shared.clear()
            if let items = try? FileManager.default.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil) {
                for item in items where item.lastPathComponent != "cover-thumbs" {
                    try? FileManager.default.removeItem(at: item)
                }
            }
        } else if selected["cover"] == true {
            freed += bytes["cover"] ?? 0
            ThumbnailDiskCache.shared.clear()
        }
        if selected["tmp"] == true {
            freed += bytes["tmp"] ?? 0
            OwnCache.deleteContents(of: URL(fileURLWithPath: NSTemporaryDirectory()))
        }
        return freed
    }

    /// 收尾：拼结果横幅、刷新自己四项、通知目录页刷新。
    private func finishClean(engineResult: String?) {
        // 校验失败（引擎 result 里有“重新扫描”）直接显示引擎的原文。
        if let engineResult, engineResult.contains("重新扫描") {
            resultBanner = engineResult
        } else {
            let engineFreed = engineCleanRan ? engine.lastFreedBytes : 0
            let totalFreed = ownFreed + engineFreed
            var text = "已释放 \(wqSizeText(totalFreed))。"
            if engineCleanRan && engine.lastCleanIncomplete {
                text += "有些项目无法删除。"
            }
            text += "目录正在刷新…"
            resultBanner = text
        }
        ownFreed = 0
        engineCleanRan = false
        Task { await measureOwnItems() }
        NotificationCenter.default.post(name: .win97CacheCleaned, object: nil)
    }

    func cancelClean() {
        engine.cancelClean()
    }
}

// MARK: - 界面

struct CacheCleanerView: View {
    @StateObject private var model = CacheCleanerModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // 搜索框。
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索 App", text: $model.query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(10)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                // 汇总卡。
                summaryCard

                // 列表头：个数 + 全选/全不选。
                HStack {
                    Text("\(model.totalCount) 个 App 和扩展")
                        .font(.headline)
                    Spacer()
                    Button("全选") { model.setAllSelected(true) }
                    Text("·").foregroundStyle(.secondary)
                    Button("全不选") { model.setAllSelected(false) }
                }
                .font(.subheadline)
                .foregroundStyle(Color(hex: "#5AA9FF"))

                // 列表。
                VStack(spacing: 0) {
                    if model.ownRowVisible {
                        ownRow
                    }
                    ForEach(model.visibleOtherItems, id: \.self) { item in
                        Divider().background(Color.white.opacity(0.08)).padding(.leading, 14)
                        appRow(item)
                    }
                }
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1))

                // 页脚说明（WQ 原话，按当前勾选算）。
                if !model.footerText.isEmpty {
                    Text(model.footerText)
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                // 结果横幅。
                if let banner = model.resultBanner {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(banner).font(.subheadline)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }

                // 清理按钮。
                Button {
                    model.showConfirm = true
                } label: {
                    Text("清理选中（\(model.selectedCount) 项，\(wqSizeText(model.selectedBytes))）")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(model.cleanDisabled ? Color.gray.opacity(0.4) : Color.red,
                                    in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(model.cleanDisabled)

                if model.persistenceFailed {
                    Text("扫描结果未能保存，重新扫描即可恢复。")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                // 署名：清理功能基于 WQ Files，GPL-3.0。
                Text("缓存清理基于 WQ Files（kolbicz），遵循 GPL-3.0 开源协议。")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding()
        }
        .refreshable { model.refresh() }
        .background(AppBackgroundView())
        .navigationTitle("缓存清理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.startIfNeeded() }
        .alert("清理缓存？", isPresented: $model.showConfirm) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) { model.startClean() }
        } message: {
            Text(model.confirmationMessage)
        }
        .alert("无法清理", isPresented: $model.showLimitedAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("系统没有开放这个 App 的缓存，清不掉。")
        }
        .overlay {
            if model.cleaning {
                cleaningOverlay
            }
        }
    }

    // MARK: 汇总卡

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.scanning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(model.status ?? "正在扫描…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text(wqSizeText(model.scanBytes))
                    .font(.system(size: 34, weight: .bold))
                ProgressView(value: Double(model.scanProgress))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("可释放")
                        .font(.headline)
                    Text(wqSizeText(model.totalBytes))
                        .font(.system(size: 34, weight: .bold))
                }
                Text("已选择 \(wqSizeText(model.selectedBytes))，共 \(model.totalCount) 个项目")
                    .font(.subheadline).foregroundStyle(.secondary)
                if model.totalBytes > 0 {
                    ProgressView(value: Double(model.selectedBytes) / Double(model.totalBytes))
                }
                if let last = model.lastScanned {
                    Text("上次扫描：\(last, style: .relative)前")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: 自己的 App 行

    private var ownRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    model.ownExpanded.toggle()
                } label: {
                    HStack(spacing: 12) {
                        appIconTile(fallbackGlyph: "壁", color: Color(hex: "#34C759"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("壁纸匣（本 App）").font(.headline)
                            Text("缓存 \(wqSizeText(ownCacheBytes)) · 临时文件 \(wqSizeText(ownTempBytes))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(wqSizeText(model.ownTotalBytes))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Image(systemName: model.ownExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    model.toggleOwnRow()
                } label: {
                    selectionCircle(selected: model.ownAnySelected, partial: model.ownPartialSelected)
                }
                .buttonStyle(.plain)
            }
            .padding(12)

            if model.ownExpanded {
                ForEach(model.ownItems) { sub in
                    Divider().background(Color.white.opacity(0.08)).padding(.leading, 56)
                    Button {
                        model.toggleOwnItem(sub.id)
                    } label: {
                        HStack(spacing: 12) {
                            appIconTile(fallbackGlyph: sub.glyph, color: sub.color, small: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sub.name).font(.subheadline)
                                Text(sub.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(wqSizeText(sub.bytes))
                                .font(.subheadline).foregroundStyle(.secondary)
                            selectionCircle(selected: sub.selected, partial: false)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 自己的缓存/临时文件拆分（引擎那行有现成数就用它的，没有就按四项估）。
    private var ownCacheBytes: UInt64 {
        if let item = model.ownEngineItem { return item.cacheBytes }
        return model.ownItems.filter { $0.id != "tmp" }.reduce(0) { $0 + $1.bytes }
    }

    private var ownTempBytes: UInt64 {
        if let item = model.ownEngineItem { return item.tempBytes }
        return model.ownItems.first(where: { $0.id == "tmp" })?.bytes ?? 0
    }

    // MARK: 别人 App 的行

    private func appRow(_ item: WQCacheItem) -> some View {
        Button {
            if item.limited {
                model.showLimitedAlert = true
            } else {
                item.selected.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                if let image = model.icons[item.bundleID ?? ""] {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    appIconTile(fallbackGlyph: String(item.name.prefix(1)),
                                color: Color(hex: "#5A6478"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name).font(.headline)
                            .foregroundStyle(item.limited ? .secondary : .primary)
                        if item.limited {
                            Text("访问受限")
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.white.opacity(0.1), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                        if item.crashLogs {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Text("缓存 \(wqSizeText(item.cacheBytes)) · 临时文件 \(wqSizeText(item.tempBytes))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(wqSizeText(item.bytes))
                    .font(.subheadline).foregroundStyle(.secondary)
                selectionCircle(selected: item.selected, partial: false)
                    .opacity(item.limited ? 0.3 : 1)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { model.loadIcon(for: item.bundleID) }
    }

    // MARK: 小组件

    private func appIconTile(fallbackGlyph: String, color: Color, small: Bool = false) -> some View {
        let size: CGFloat = small ? 32 : 44
        return ZStack {
            RoundedRectangle(cornerRadius: small ? 8 : 10)
                .fill(color)
                .frame(width: size, height: size)
            Text(fallbackGlyph)
                .font(.system(size: small ? 15 : 18, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func selectionCircle(selected: Bool, partial: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(selected || partial ? Color(hex: "#5AA9FF") : .secondary.opacity(0.5), lineWidth: 1.5)
                .frame(width: 24, height: 24)
            if selected {
                Circle().fill(Color(hex: "#5AA9FF")).frame(width: 24, height: 24)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            } else if partial {
                Circle().fill(Color(hex: "#5AA9FF")).frame(width: 12, height: 12)
            }
        }
    }

    // MARK: 清理中浮层

    private var cleaningOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("正在清理")
                    .font(.headline)
                if let status = model.status {
                    Text(status)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("停止") {
                    model.cancelClean()
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(.white.opacity(0.12), in: Capsule())
            }
            .padding(24)
            .background(Color(hex: "#1C1E24"), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - 模型小 helper

extension CacheCleanerModel {
    /// 自己四项有没有只勾了一部分（画半选圈用）。
    var ownPartialSelected: Bool {
        let selected = ownItems.filter(\.selected).count
        return selected > 0 && selected < ownItems.count
    }
}
