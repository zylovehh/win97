// CatalogModel.swift
// 目录数据：一条壁纸的元数据、目录拉取、已下载管理。
// 目录表 catalog.json 放在仓库根目录，App 打开时按分发线路顺序拉取
// （多镜像，照 Camlo 的做法：国内优先走代理镜像，国外优先走原站和 jsDelivr，
// 一条挂了自动试下一条）；全部失败就显示空状态，不崩。
// 壁纸包、预览视频、缩略图放仓库 wallpapers/ 目录。
// 管理端推完目录/传完壁纸后，自动清一下 CDN 缓存，用户端马上能看到新内容。

import Foundation

/// 目录里的一张壁纸：标题、标签、缩略图、预览视频、壁纸包地址，
/// 再加管理员置顶（pinned）和下载数（downloads）。
/// 排序规则（见 fetch）：置顶先排，置顶里按目录表顺序；不置顶的按下载数从多到少；
/// 下载数相同按目录表顺序。新上传的壁纸管理员置顶后就排最上边。
/// 下载数目前是目录表里的数字，由管理员改；App 里点下载不会自动加总，
/// 因为没有服务器记账，以后接了服务器再改成自动计数。
struct CatalogItem: Identifiable, Decodable, Equatable {
    let id: String
    let title: String
    let tags: [String]
    let thumbnailURL: String
    let previewURL: String
    let packageURL: String
    let pinned: Bool
    let downloads: Int
    /// 壁纸给哪个设备：iphone 或 ipad，老目录表没有这字段时默认 iphone。
    let device: String
    /// 包的描述符 UUID（包里的东西，不是名字）：分享/自动导入时按它去重，
    /// 同名可能是不同包、不同名可能是同一个包，只比名字会认错。
    /// 老目录表没有这字段时为 nil，比不上就跳过，不拦着用。
    let uuid: String?

    enum CodingKeys: String, CodingKey {
        case id, title, tags, pinned, downloads, device, uuid
        case thumbnailURL = "thumbnail"
        case previewURL = "preview"
        case packageURL = "package"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        tags = try c.decode([String].self, forKey: .tags)
        thumbnailURL = try c.decode(String.self, forKey: .thumbnailURL)
        previewURL = try c.decode(String.self, forKey: .previewURL)
        packageURL = try c.decode(String.self, forKey: .packageURL)
        // 老目录表没有这两个字段时默认不置顶、下载数 0，不让旧表解码失败。
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        downloads = try c.decodeIfPresent(Int.self, forKey: .downloads) ?? 0
        device = try c.decodeIfPresent(String.self, forKey: .device) ?? "iphone"
        uuid = try c.decodeIfPresent(String.self, forKey: .uuid)
    }

    /// 管理员改目录时直接拼一张新卡（改置顶、增加都用这个，不走解码）。
    init(id: String, title: String, tags: [String], thumbnailURL: String, previewURL: String, packageURL: String, pinned: Bool, downloads: Int, device: String = "iphone", uuid: String? = nil) {
        self.id = id
        self.title = title
        self.tags = tags
        self.thumbnailURL = thumbnailURL
        self.previewURL = previewURL
        self.packageURL = packageURL
        self.pinned = pinned
        self.downloads = downloads
        self.device = device
        self.uuid = uuid
    }
}

/// catalog.json 的顶层结构。
struct CatalogDocument: Decodable {
    let items: [CatalogItem]
}

/// 目录拉取/下载失败原因（带中文说明，免得 404 也报“格式不对”）。
enum CatalogError: LocalizedError {
    case notFound
    case fileNotFound
    var errorDescription: String? {
        switch self {
        case .notFound: return "目录表没找到（请检查目录地址）"
        case .fileNotFound: return "壁纸文件没找到（可能还没上传）"
        }
    }
}

/// 已下载的一张壁纸：元数据 + 本地文件名（存在沙盒里，供“我的”页列出）。
struct DownloadedItem: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let tags: [String]
    let fileName: String
    let downloadedAt: Date
}

/// 多镜像线路（照 Camlo 的做法搬过来：CloudGalleryManager.buildRepoURLs）。
/// GitHub 上的一个文件，按地区排 7 条线路，一条挂了自动试下一条：
/// 国内（中国）优先走代理镜像——GitHub 原站在国内经常慢甚至打不开；
/// 国外优先走原站和 jsDelivr——本机实测原站和 Fastly 最快（0.8 秒）。
enum MirrorRoutes {
    /// 是否优先走国内镜像：地区是中国，或时区是上海/重庆。
    /// 语言故意不算——海外华人手机多半也是简体中文，但在马来西亚这类地方
    /// GitHub 原站很快，按语言算会把他们错划成国内、反而变慢。
    static var prefersCNMirror: Bool {
        let region = Locale.current.region?.identifier.uppercased() ?? ""
        if region == "CN" { return true }
        let tz = TimeZone.current.identifier
        return tz == "Asia/Shanghai" || tz == "Asia/Chongqing"
    }

    /// 一个仓库文件的全部镜像地址（按地区排好序，去重）。
    /// slug 是 "用户/仓库"，branch 是分支，path 是仓库里的相对路径。
    static func repoFileURLs(slug: String, branch: String, path: String) -> [URL] {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let raw = "https://raw.githubusercontent.com/\(slug)/\(branch)/\(cleanPath)"
        let ghFast = "https://ghfast.top/\(raw)"
        let ghProxy = "https://gh-proxy.com/\(raw)"
        let ghProxyNet = "https://ghproxy.net/\(raw)"
        let jsdMirror = "https://cdn.jsdmirror.com/gh/\(slug)@\(branch)/\(cleanPath)"
        let jsDelivr = "https://fastly.jsdelivr.net/gh/\(slug)@\(branch)/\(cleanPath)"
        let gcore = "https://gcore.jsdelivr.net/gh/\(slug)@\(branch)/\(cleanPath)"
        let ordered: [String]
        if prefersCNMirror {
            ordered = [ghFast, ghProxy, ghProxyNet, jsdMirror, jsDelivr, gcore, raw]
        } else {
            ordered = [raw, jsDelivr, gcore, ghFast, ghProxy, ghProxyNet, jsdMirror]
        }
        var seen = Set<String>()
        return ordered.compactMap { str in
            guard seen.insert(str).inserted else { return nil }
            return URL(string: str)
        }
    }

    /// 一个仓库的根地址（不带具体文件），按地区排好序，供目录表这类按根拼地址的调用方用。
    static func repoBaseURLs(slug: String, branch: String) -> [String] {
        let raw = "https://raw.githubusercontent.com/\(slug)/\(branch)"
        let ghFast = "https://ghfast.top/\(raw)"
        let ghProxy = "https://gh-proxy.com/\(raw)"
        let ghProxyNet = "https://ghproxy.net/\(raw)"
        let jsdMirror = "https://cdn.jsdmirror.com/gh/\(slug)@\(branch)"
        let jsDelivr = "https://fastly.jsdelivr.net/gh/\(slug)@\(branch)"
        let gcore = "https://gcore.jsdelivr.net/gh/\(slug)@\(branch)"
        if prefersCNMirror {
            return [ghFast, ghProxy, ghProxyNet, jsdMirror, jsDelivr, gcore, raw]
        } else {
            return [raw, jsDelivr, gcore, ghFast, ghProxy, ghProxyNet, jsdMirror]
        }
    }

    /// 一个现成的下载地址（jsDelivr / raw / 镜像代理形式都认），拆出仓库、分支、路径，
    /// 返回按地区排好的全部镜像地址；拆不出来就原样返回这一条（不拦着下）。
    static func mirrorURLs(for address: String) -> [URL] {
        guard let (slug, branch, path) = parseRepoFile(address) else {
            return URL(string: address).map { [$0] } ?? []
        }
        return repoFileURLs(slug: slug, branch: branch, path: path)
    }

    /// 从一个地址里拆出（仓库 slug、分支、路径）：
    /// jsDelivr 系（fastly/cdn/gcore）：https://<host>/gh/<用户>/<仓库>@<分支>/<路径>
    /// jsdmirror：https://cdn.jsdmirror.com/gh/<用户>/<仓库>@<分支>/<路径>
    /// raw 直链：https://raw.githubusercontent.com/<用户>/<仓库>/<分支>/<路径>
    /// 代理镜像（ghfast/gh-proxy/ghproxy.net）：去掉前缀后按 raw 直链再拆。
    /// 拆不出来返回 nil。
    static func parseRepoFile(_ address: String) -> (slug: String, branch: String, path: String)? {
        // 代理前缀先剥掉，里面就是一条 raw 直链。
        for prefix in ["https://ghfast.top/", "https://gh-proxy.com/", "https://ghproxy.net/"] {
            if address.hasPrefix(prefix) {
                return parseRepoFile(String(address.dropFirst(prefix.count)))
            }
        }
        // jsDelivr 系 / jsdmirror：.../gh/<slug>@<branch>/<path>
        for host in ["https://fastly.jsdelivr.net/gh/", "https://cdn.jsdelivr.net/gh/",
                     "https://gcore.jsdelivr.net/gh/", "https://cdn.jsdmirror.com/gh/"] {
            guard address.hasPrefix(host) else { continue }
            let rest = String(address.dropFirst(host.count))
            guard let at = rest.firstIndex(of: "@"),
                  let slash = rest[rest.index(after: at)...].firstIndex(of: "/") else { return nil }
            let slug = String(rest[..<at])
            let branch = String(rest[rest.index(after: at)..<slash])
            let path = String(rest[rest.index(after: slash)...])
            guard slug.contains("/"), !branch.isEmpty, !path.isEmpty else { return nil }
            return (slug, branch, path)
        }
        // raw 直链：.../<用户>/<仓库>/<分支>/<路径>
        let rawHost = "https://raw.githubusercontent.com/"
        guard address.hasPrefix(rawHost) else { return nil }
        let rest = String(address.dropFirst(rawHost.count))
        let parts = rest.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 4 else { return nil }
        let slug = "\(parts[0])/\(parts[1])"
        let branch = String(parts[2])
        let path = parts[3...].joined(separator: "/")
        guard !path.isEmpty else { return nil }
        return (slug, branch, path)
    }
}

/// 目录仓库：拉目录表、下载壁纸包、管理已下载列表。
/// 已下载记录存在 UserDefaults，文件存在沙盒 Documents/downloaded-wallpapers/。
@MainActor
final class CatalogStore: ObservableObject {
    /// 目录表拉取顺序（多镜像，按地区排，见 MirrorRoutes）：
    /// 国内优先走代理镜像（GitHub 原站在国内经常慢），国外优先走原站和 jsDelivr。
    /// 改仓库名或分支要同步改这里。
    static var catalogHosts: [String] {
        MirrorRoutes.repoBaseURLs(slug: "zylovehh/win97-catalog", branch: "main")
    }

    /// 目录表地址（主线路；实际拉取在 fetch 里按 catalogHosts 顺序尝试）。
    static let catalogURLString = catalogHosts[0] + "/" + catalogPath

    /// 目录仓库（公开目录仓库，管理员改置顶、增删时推到这里）。
    static let catalogRepo = "zylovehh/win97-catalog"
    static let catalogPath = "catalog.json"
    static let wallpapersDir = "wallpapers"
    /// 新壁纸写进目录表的地址前缀（大文件走 Fastly 加速；下载实际按目录表里的地址走）。
    static let wallpapersRawBase = "https://fastly.jsdelivr.net/gh/zylovehh/win97-catalog@main/wallpapers/"

    @Published private(set) var items: [CatalogItem] = []
    @Published private(set) var downloaded: [DownloadedItem] = []
    @Published private(set) var downloadingIDs: Set<String> = []
    @Published var errorMessage = ""
    @Published private(set) var loading = false
    /// 目录表里要求的最低 App 版本（没有就不拦；发新版时跟着版本号一起提）。
    private(set) var minAppVersion: Double?

    /// 从目录表原始数据里宽松地读最低版本号（数字或字符串都认）。
    /// 读不到、读错了都不拦（当没有这个字段），绝不能因为这个字段坏了整表。
    static func readMinAppVersion(from data: Data) -> Double? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["minAppVersion"] else { return nil }
        if let n = raw as? Double { return n }
        if let n = raw as? Int { return Double(n) }
        if let s = raw as? String { return Double(s) }
        return nil
    }

    private let downloadedDefaultsKey = "win97-downloaded"

    init() {
        loadDownloaded()
    }

    /// 已下载文件存放目录（沙盒 Documents/downloaded-wallpapers/）。
    var downloadedDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("downloaded-wallpapers")
    }

    /// 某张壁纸是否已下载（记录在且文件还在）。
    func isDownloaded(_ item: CatalogItem) -> Bool {
        guard downloaded.contains(where: { $0.id == item.id }) else { return false }
        return FileManager.default.fileExists(atPath: localURL(for: item).path)
    }

    /// 已下载条目对应的本地文件地址。
    func localURL(for item: CatalogItem) -> URL {
        downloadedDirectory.appendingPathComponent(safeFileName(for: item.id))
    }

    /// 已下载条目对应的本地文件地址（按记录）。
    func localURL(for record: DownloadedItem) -> URL {
        downloadedDirectory.appendingPathComponent(record.fileName)
    }

    /// 拉目录表：按线路顺序尝试（仓库直链 → Fastly → Gcore），
    /// 第一条通的生效；全失败就留空 + 报错文案，绝不崩。
    func fetch() async {
        loading = true
        defer { loading = false }
        var lastError: Error?
        for host in Self.catalogHosts {
            guard var components = URLComponents(string: host + "/" + Self.catalogPath) else { continue }
            // 时间戳参数：让运营商/CDN 中间缓存无法命中旧目录（部分线路缓存宽限长达 7 天）。
            components.queryItems = [URLQueryItem(name: "ts", value: String(Int(Date().timeIntervalSince1970)))]
            guard let url = components.url else { continue }
            do {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw CatalogError.notFound
                }
                let doc = try JSONDecoder().decode(CatalogDocument.self, from: data)
                // 目录只给最新版：表里写了最低版本，低于它的 App 不显示目录。
                let min = Self.readMinAppVersion(from: data)
                minAppVersion = min
                if let min, UpdateChecker.versionCode(UpdateChecker.localVersionNumber()) < UpdateChecker.versionCode(min) {
                    items = []
                    errorMessage = "目录只给最新版：请先把 App 更新到 V\(UpdateChecker.versionString(min)) 再看目录。"
                    return
                }
                items = Self.sortedItems(doc.items)
                errorMessage = ""
                return
            } catch {
                lastError = error
            }
        }
        items = []
        errorMessage = "目录没拉到：\(lastError?.localizedDescription ?? "所有线路都不可用")"
    }

    /// 下载一张壁纸：存到沙盒并记入已下载，成功返回包数据（供安装页直接用）。
    /// 下载中、失败都不抛崩溃，失败只写 errorMessage。
    /// 目录表里有的包只写了相对路径（wallpapers/xxx.tendies），没写完整地址，
    /// 直接拿去下会失败（没域名），这里先拼成 Fastly 加速的完整地址再下。
    /// 注意 wallpapersRawBase 末尾已经是 wallpapers/，相对路径开头的 wallpapers/ 要去掉再拼，
    /// 不然会拼出两层 wallpapers。
    /// 多镜像兜底（见 MirrorRoutes）：不管目录表里写的是 Fastly 还是 raw，
    /// 都拆出仓库、分支、路径，按地区排 7 条线路逐条试——超 20M 的包 jsDelivr 直接 403、
    /// 缓存过期会 404、有的手机网络还根本到不了某条线路（断网、超时、连不上，连状态码都没有），
    /// 这几种都自动换下一条，不换源就永远下不来。
    func download(_ item: CatalogItem) async -> Data? {
        let packageAddress: String
        if item.packageURL.hasPrefix("http") {
            packageAddress = item.packageURL
        } else {
            let path = item.packageURL.hasPrefix("wallpapers/")
                ? String(item.packageURL.dropFirst("wallpapers/".count))
                : item.packageURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            packageAddress = Self.wallpapersRawBase + path
        }
        guard !downloadingIDs.contains(item.id) else { return nil }
        downloadingIDs.insert(item.id)
        defer { downloadingIDs.remove(item.id) }
        // 多镜像：按地区排好的线路逐条试，一条通了就行。
        for url in MirrorRoutes.mirrorURLs(for: packageAddress) {
            if let data = await Self.fetchData(from: url) {
                return saveDownload(data, for: item)
            }
        }
        errorMessage = "下载失败：所有线路都拉不到，请检查网络后重试"
        return nil
    }

    /// 拉一次：200 且拿到数据才返回，否则 nil（断网、超时、403/404 都算拉不到）。
    /// 单条线路 15 秒超时，超时就换下一条，别一条卡住整趟下载。
    /// 破本地缓存：同一个地址的文件可能被替换过（比如重编的同名 IPA/包），
    /// 不破缓存会拿到旧文件。
    private static func fetchData(from url: URL) async -> Data? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// jsDelivr 地址换成 GitHub 直链：
    /// https://fastly.jsdelivr.net/gh/<用户>/<仓库>@<分支>/<路径>
    /// → https://raw.githubusercontent.com/<用户>/<仓库>/<分支>/<路径>。
    /// 不是 jsDelivr 的地址返回 nil（不用换源）。
    static func rawGitHubURL(from address: String) -> URL? {
        for host in ["https://fastly.jsdelivr.net/gh/", "https://cdn.jsdelivr.net/gh/"] {
            guard address.hasPrefix(host) else { continue }
            let rest = String(address.dropFirst(host.count))
            guard let at = rest.firstIndex(of: "@") else { return nil }
            let repoPart = String(rest[..<at])
            let afterAt = String(rest[rest.index(after: at)...])
            guard let slash = afterAt.firstIndex(of: "/") else { return nil }
            let branch = String(afterAt[..<slash])
            let path = String(afterAt[afterAt.index(after: slash)...])
            return URL(string: "https://raw.githubusercontent.com/\(repoPart)/\(branch)/\(path)")
        }
        return nil
    }

    /// 下载成功后的落盘 + 记账（主源和换源共用）。
    private func saveDownload(_ data: Data, for item: CatalogItem) -> Data? {
        do {
            try FileManager.default.createDirectory(
                at: downloadedDirectory, withIntermediateDirectories: true)
            try data.write(to: localURL(for: item), options: .atomic)
            let record = DownloadedItem(
                id: item.id, title: item.title, tags: item.tags,
                fileName: safeFileName(for: item.id), downloadedAt: Date())
            downloaded.removeAll { $0.id == item.id }
            downloaded.insert(record, at: 0)
            saveDownloaded()
            errorMessage = ""
            return data
        } catch {
            errorMessage = "下载失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 删除一张已下载：文件和记录一起删。
    func delete(_ record: DownloadedItem) {
        try? FileManager.default.removeItem(at: localURL(for: record))
        downloaded.removeAll { $0.id == record.id }
        saveDownloaded()
    }

    /// 读已下载记录，并把文件已不在的记录清掉。
    private func loadDownloaded() {
        guard let data = UserDefaults.standard.data(forKey: downloadedDefaultsKey),
              let records = try? JSONDecoder().decode([DownloadedItem].self, from: data)
        else { return }
        downloaded = records.filter {
            FileManager.default.fileExists(atPath: localURL(for: $0).path)
        }
        if downloaded.count != records.count { saveDownloaded() }
    }

    private func saveDownloaded() {
        if let data = try? JSONEncoder().encode(downloaded) {
            UserDefaults.standard.set(data, forKey: downloadedDefaultsKey)
        }
    }

    /// 排序：置顶在前（置顶内保持目录表顺序），其余按下载数从多到少，
    /// 下载数相同保持目录表顺序（序号 tiebreak 保证稳定）。
    static func sortedItems(_ input: [CatalogItem]) -> [CatalogItem] {
        input.enumerated().sorted { a, b in
            if a.element.pinned != b.element.pinned {
                return a.element.pinned
            }
            if a.element.downloads != b.element.downloads {
                return a.element.downloads > b.element.downloads
            }
            return a.offset < b.offset
        }.map { $0.element }
    }

    // MARK: - 管理员改目录（推到 GitHub 仓库）

    /// 目录推送失败原因（带中文说明）。
    enum PushError: LocalizedError {
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .http(let code):
                let hint: String
                switch code {
                case 401: hint = "钥匙失效了，去管理员页重新保存一把"
                case 403: hint = "这把钥匙没有写权限，检查授权范围"
                case 409, 422: hint = "仓库刚变了，再点一次就行"
                case 404: hint = "仓库里没找到要写的文件"
                default: hint = "网络或服务暂时不给力"
                }
                return "推到仓库失败：\(hint)（状态码 \(code)）"
            }
        }
    }

    /// 把一整份目录表推到仓库（改置顶、增删都走这里），成功后刷新本机目录顺序。
    /// 推之前先拉仓库最新表合并一次：别人同时加的条目不丢，自己删的条目不回来；
    /// 这样仓库刚变了也不会报 409，基本一次就推上去，不用等几秒再点一次。
    func pushCatalog(_ newItems: [CatalogItem], token: String) async throws {
        let (merged, knownSHA, serverMin) = await mergedCatalog(newItems, token: token)
        let dicts: [[String: Any]] = merged.map { item in
            var dict: [String: Any] =
                ["id": item.id, "title": item.title, "tags": item.tags,
                 "thumbnail": item.thumbnailURL, "preview": item.previewURL,
                 "package": item.packageURL, "pinned": item.pinned, "downloads": item.downloads,
                 "device": item.device]
            // 有描述符 UUID 才写进表：老条目没这字段就留空，不硬塞。
            if let uuid = item.uuid { dict["uuid"] = uuid }
            return dict
        }
        // 最低版本跟着一起推（没有就不写，绝不因为这个字段丢了整表）。
        var top: [String: Any] = ["items": dicts]
        if let min = serverMin ?? minAppVersion { top["minAppVersion"] = min }
        let data = try JSONSerialization.data(
            withJSONObject: top, options: [.withoutEscapingSlashes])
        try await githubPut(
            path: Self.catalogPath, contentBase64: data.base64EncodedString(),
            message: "Update catalog via app", token: token, knownSHA: knownSHA)
        items = Self.sortedItems(merged)
        minAppVersion = serverMin ?? minAppVersion
        errorMessage = ""
        // 清 CDN 缓存改后台悄悄清，不等它：推表成功就立刻放开按钮，
        // 缓存清不清只影响别人晚几秒看到新目录，不影响这次操作。
        Task { await purgeCDNCache(paths: [Self.catalogPath]) }
    }

    /// 推前合并：以本地 newItems 为准（用户这次的操作），再把仓库里有、
    /// 本地这次没有、且本地原来也没有的条目（别人同时加的）补进来，插到置顶后面。
    /// 本地原来有、这次没了的，是用户刚删的，不补回来。
    /// 拉不到最新表就直接用本地的，不挡推送。
    /// 顺带把拉表时拿到的版本标识（sha）一起带回来，推表时直接用，省一次单独查询。
    private func mergedCatalog(_ newItems: [CatalogItem], token: String) async -> ([CatalogItem], String?, Double?) {
        guard let (serverItems, sha, serverMin) = try? await githubCatalogItems(token: token) else { return (newItems, nil, minAppVersion) }
        let baseIDs = Set(items.map { $0.id })
        let newIDs = Set(newItems.map { $0.id })
        let extras = serverItems.filter { !newIDs.contains($0.id) && !baseIDs.contains($0.id) }
        guard !extras.isEmpty else { return (newItems, sha, serverMin) }
        var merged = newItems
        let insertAt = merged.firstIndex(where: { !$0.pinned }) ?? merged.endIndex
        merged.insert(contentsOf: extras, at: insertAt)
        return (merged, sha, serverMin)
    }

    /// 从 GitHub 接口拉当前目录表（带钥匙走 API 不走 CDN，拿到的就是最新版）。
    /// 404 当空表，不算错；其他错直接抛，让调用方决定。
    /// 顺带返回文件的版本标识（sha），推表时直接用，省一次单独查询。
    private func githubCatalogItems(token: String) async throws -> ([CatalogItem], String?, Double?) {
        var request = URLRequest(url: githubContentsURL(path: Self.catalogPath))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Win97", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return ([], nil, nil) }
        guard status == 200 else { throw PushError.http(status) }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let b64 = dict["content"] as? String,
              let raw = Data(base64Encoded: b64.replacingOccurrences(of: "\n", with: "")),
              let doc = try? JSONDecoder().decode(CatalogDocument.self, from: raw)
        else { throw PushError.http(status) }
        return (doc.items, dict["sha"] as? String, Self.readMinAppVersion(from: raw))
    }

    /// 预览视频文件名：每次换视频都生成唯一新名（id + 秒级时间戳），
    /// 文件名要好认，不用 UUID。同名覆盖会被 CDN 和手机缓存认成同一个文件，
    /// 新视频传上去目录里还一直显示旧的；新名直接绕开缓存。
    static func previewVideoName(for id: String) -> String {
        "\(id)-preview-\(Int(Date().timeIntervalSince1970)).mp4"
    }

    /// 清掉某个 URL 的本地缓存（换视频后用）：新文件名已经绕开缓存，
    /// 这里再清掉旧 URL 的那份，卡片立刻显示新视频，不用等缓存过期。
    static func clearLocalCache(for urlString: String) {
        guard let url = URL(string: urlString) else { return }
        URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
        // 封面播不起来时会走 raw 直链当备用：那条也清掉。
        if let rawURL = rawGitHubURL(from: urlString) {
            URLCache.shared.removeCachedResponse(for: URLRequest(url: rawURL))
        }
    }

    /// 上传一个壁纸文件到仓库 wallpapers/ 目录（已有同名就覆盖，重试不报错）。
    /// progress：上传进度回调（0~1，可能从非主线程调用），nil 表示不关心进度。
    func uploadWallpaperFile(name: String, data: Data, token: String,
                             progress: ((Double) -> Void)? = nil) async throws {
        try await githubPut(
            path: "\(Self.wallpapersDir)/\(name)", contentBase64: data.base64EncodedString(),
            message: "Upload \(name) via app", token: token, progress: progress)
        // 清掉该文件的 CDN 缓存（目录本身的缓存由随后的 pushCatalog 统一清），后台悄悄清，不等它。
        Task { await purgeCDNCache(paths: ["\(Self.wallpapersDir)/\(name)"]) }
    }

    /// 删掉某张壁纸的旧预览视频（换视频后清理）：只删 `<id>-preview*.mp4`，
    /// .tendies 包和其他文件一律不动。删错了可从 git 历史恢复。
    /// 调用时机：新视频已传上去、目录表已指向新名之后；删除是 best effort，
    /// 删不掉不报错（新视频已生效，旧文件只占一点仓库空间）。
    func deleteOldPreviewVideos(id: String, keepName: String, token: String) async {
        guard let entries = try? await githubListDirectory(path: Self.wallpapersDir, token: token) else { return }
        var deletedPaths: [String] = []
        for entry in entries
        where entry.name.hasPrefix("\(id)-preview") && entry.name.hasSuffix(".mp4") && entry.name != keepName {
            let path = "\(Self.wallpapersDir)/\(entry.name)"
            do {
                try await githubDelete(path: path, sha: entry.sha,
                                       message: "Delete old preview \(entry.name) via app", token: token)
                deletedPaths.append(path)
            } catch {
                continue
            }
        }
        if !deletedPaths.isEmpty {
            await purgeCDNCache(paths: deletedPaths)
        }
    }

    /// 让 CDN 缓存失效（best effort）：逐条请求 purge 接口，失败静默忽略，
    /// 不影响推目录主流程。下次用户拉取时 CDN 会回源拿最新内容。
    private func purgeCDNCache(paths: [String]) async {
        for path in paths {
            guard let url = URL(string:
                "https://purge.jsdelivr.net/gh/\(Self.catalogRepo)@main/\(path)")
            else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// GitHub contents 接口地址。
    private func githubContentsURL(path: String) -> URL {
        URL(string: "https://api.github.com/repos/\(Self.catalogRepo)/contents/\(path)")!
    }

    /// 读仓库里某个文件的当前版本标识（sha），文件不存在返回 nil（不是错）。
    private func githubSHA(path: String, token: String) async throws -> String? {
        var request = URLRequest(url: githubContentsURL(path: path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Win97", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard status == 200 else { throw PushError.http(status) }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = dict["sha"] as? String
        else { throw PushError.http(status) }
        return sha
    }

    /// 删仓库里某个文件（DELETE contents 接口）：要带文件的 sha。
    private func githubDelete(path: String, sha: String, message: String, token: String) async throws {
        var request = URLRequest(url: githubContentsURL(path: path))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Win97", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["message": message, "sha": sha])
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw PushError.http(status) }
    }

    /// 列仓库里某个目录下的文件（名字 + sha），目录不存在返回空。
    private func githubListDirectory(path: String, token: String) async throws -> [(name: String, sha: String)] {
        var request = URLRequest(url: githubContentsURL(path: path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Win97", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return [] }
        guard status == 200 else { throw PushError.http(status) }
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw PushError.http(status)
        }
        return arr.compactMap { dict in
            guard let name = dict["name"] as? String, let sha = dict["sha"] as? String else { return nil }
            return (name, sha)
        }
    }

    /// 写（新建或覆盖）仓库里某个文件：内容先转 base64；已有文件要带上它的 sha 才能覆盖。
    /// 连续操作（删除/置顶连着点）时接口偶尔报 409 版本冲突，自动等一拍重取再推，最多重试两次。
    /// knownSHA：调用方拉表时顺带拿到的版本标识，第一次直接用，省一次单独查询；重试时重新拉最新的。
    private func githubPut(path: String, contentBase64: String, message: String, token: String,
                           progress: ((Double) -> Void)? = nil, knownSHA: String? = nil) async throws {
        let baseBody: [String: Any] = ["message": message, "content": contentBase64]
        var lastStatus = 0
        for attempt in 0..<3 {
            var body = baseBody
            let sha: String?
            if attempt == 0, let known = knownSHA {
                sha = known
            } else {
                sha = try await githubSHA(path: path, token: token)
            }
            if let sha {
                body["sha"] = sha
            }
            let bodyData = try JSONSerialization.data(withJSONObject: body)
            var request = URLRequest(url: githubContentsURL(path: path))
            request.httpMethod = "PUT"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Win97", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
            let (data, response): (Data, URLResponse)
            if let progress {
                // 带进度的上传：每次发出数据块都会回传一次已传比例。
                let delegate = UploadProgressDelegate(handler: progress)
                let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
                (data, response) = try await session.data(for: request)
                session.finishTasksAndInvalidate()
            } else {
                (data, response) = try await URLSession.shared.data(for: request)
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            lastStatus = status
            if status == 200 || status == 201 { return }
            // 版本冲突就等一小拍重试；其他错直接抛。
            guard (status == 409 || status == 422), attempt < 2 else { break }
            try await Task.sleep(nanoseconds: 900_000_000)
        }
        throw PushError.http(lastStatus)
    }

    /// 按包的描述符 UUID 找目录条目：同名可能是不同包、不同名可能是同一个包，
    /// 只比名字会认错。条目没记 uuid 时比不上，返回 nil。
    func item(withUUID uuid: String) -> CatalogItem? {
        items.first { $0.uuid == uuid }
    }

    /// id 转安全串：只留字母数字、下划线、横线，其余换成下划线（增加壁纸时用文件名当 id）。
    static func safeID(from name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        return cleaned.isEmpty ? "wallpaper" : cleaned
    }

    /// id 转安全文件名：只留字母数字、下划线、横线，其余换成下划线。
    private func safeFileName(for id: String) -> String {
        Self.safeID(from: id) + ".tendies"
    }
}

/// 上传进度回调的辅助类：URLSession 每发出一块数据就触发一次，把已传比例交给外面。
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let handler: (Double) -> Void

    init(handler: @escaping (Double) -> Void) {
        self.handler = handler
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        handler(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}

