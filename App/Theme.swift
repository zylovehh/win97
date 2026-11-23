// Theme.swift
// 主题系统（V2.9）：照 WQ Files 的两套内置主题搬过来。
// 颜色值照 WQ Files 安装包里的 midnight.wqtheme / sunset.wqtheme（JSON，
// 颜色串最后两位是透明度）；.wqtheme 文件本身没放进包里，值写死在这里。
// 只有默认 / 自定颜色 / Midnight / Sunset 四项，不做导入导出主题。
// 注意：App 全局强制深色（Win97App 里 .preferredColorScheme(.dark)），
// 所以实际走的都是 dark 那套；light 的值留着，万一哪天放开浅色直接能用。

import SwiftUI

// MARK: - 颜色值

/// 一套深色或浅色的颜色。
struct ThemeVariant {
    let backgroundTop: Color
    let backgroundBottom: Color
    /// 四团光晕（左上、右上、左下、右中）。
    let glows: [Color]
    let accent: Color
    /// 卡片底色（Midnight dark 有；Sunset dark 没有，用 accent 加透明度凑）。
    let card: Color?
    /// 纯色背景用的单色（只有 dark 有；light 用 backgroundTop）。
    let plain: Color?
}

/// 一个主题的完整定义。
struct ThemeDefinition {
    let id: String
    let name: String
    let dark: ThemeVariant
    let light: ThemeVariant
    /// 卡片轮换用的渐变（Midnight 8 个，Sunset 6 个，按文件里的顺序）。
    let tiles: [(Color, Color)]
}

extension Color {
    /// "#RRGGBB" 或 "#RRGGBBAA"（最后两位是透明度）。
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: h).scanHexInt64(&value)
        if h.count == 8 {
            let r = Double((value >> 24) & 0xFF) / 255
            let g = Double((value >> 16) & 0xFF) / 255
            let b = Double((value >> 8) & 0xFF) / 255
            let a = Double(value & 0xFF) / 255
            self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
        } else {
            let r = Double((value >> 16) & 0xFF) / 255
            let g = Double((value >> 8) & 0xFF) / 255
            let b = Double(value & 0xFF) / 255
            self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
        }
    }

    /// 转回 "#RRGGBB"（取色器写回 UserDefaults 用）。
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    /// 变亮一点（自定颜色的卡片渐变用）。
    func lightened(by amount: Double) -> Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(.sRGB,
                     red: min(1, Double(r) + amount),
                     green: min(1, Double(g) + amount),
                     blue: min(1, Double(b) + amount),
                     opacity: Double(a))
    }
}

/// 内置主题的数据（照 .wqtheme 文件）。
enum BuiltinThemes {
    static let midnight = ThemeDefinition(
        id: "midnight", name: "Midnight",
        dark: ThemeVariant(
            backgroundTop: Color(hex: "#05070F"), backgroundBottom: Color(hex: "#0B1226"),
            glows: [Color(hex: "#2F6BFF9E"), Color(hex: "#00C2FF66"), Color(hex: "#7A5CFF55"), Color(hex: "#00E0B03A")],
            accent: Color(hex: "#5AA9FF"), card: Color(hex: "#1A2A5C33"), plain: Color(hex: "#05070F")),
        light: ThemeVariant(
            backgroundTop: Color(hex: "#EEF3FF"), backgroundBottom: Color(hex: "#DCE6FF"),
            glows: [Color(hex: "#7FA8FF80"), Color(hex: "#7FE0FF60"), Color(hex: "#B9A8FF55"), Color(hex: "#7FF0D040")],
            accent: Color(hex: "#2F6BFF"), card: nil, plain: nil),
        tiles: [
            (Color(hex: "#6FB6FF"), Color(hex: "#2F6BFF")),
            (Color(hex: "#7FE0FF"), Color(hex: "#1FA5E0")),
            (Color(hex: "#A08CFF"), Color(hex: "#5B3FE0")),
            (Color(hex: "#8C9CFF"), Color(hex: "#3A4BD0")),
            (Color(hex: "#5FF0D0"), Color(hex: "#0FA88C")),
            (Color(hex: "#7FC4FF"), Color(hex: "#3570E8")),
            (Color(hex: "#9FDCFF"), Color(hex: "#3A8FD9")),
            (Color(hex: "#B9A8FF"), Color(hex: "#6E4DE8")),
        ])

    static let sunset = ThemeDefinition(
        id: "sunset", name: "Sunset",
        dark: ThemeVariant(
            backgroundTop: Color(hex: "#140806"), backgroundBottom: Color(hex: "#2A0F12"),
            glows: [Color(hex: "#FF6A3DA0"), Color(hex: "#FF2E7A70"), Color(hex: "#FFC24A55"), Color(hex: "#B34DFF3A")],
            accent: Color(hex: "#FF8A4C"), card: nil, plain: Color(hex: "#140806")),
        light: ThemeVariant(
            backgroundTop: Color(hex: "#FFF4EC"), backgroundBottom: Color(hex: "#FFE3D6"),
            glows: [Color(hex: "#FFAA7A80"), Color(hex: "#FF8AB560"), Color(hex: "#FFD27A55"), Color(hex: "#D9A6FF40")],
            accent: Color(hex: "#E8562A"), card: nil, plain: nil),
        tiles: [
            (Color(hex: "#FF9A6B"), Color(hex: "#E8562A")),
            (Color(hex: "#FFB38A"), Color(hex: "#F06A3A")),
            (Color(hex: "#FF8AB5"), Color(hex: "#D9367A")),
            (Color(hex: "#FF7A8A"), Color(hex: "#C93A55")),
            (Color(hex: "#FFC86B"), Color(hex: "#E0901F")),
            (Color(hex: "#D9B3A6"), Color(hex: "#9C6B5C")),
        ])
}

// MARK: - 主题管理

/// 主题选择存在 UserDefaults 里；单例，各页直接用，不走 environment（有的页
/// 是 sheet 里弹出来的，environment 传不到会闪退，单例最稳）。
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    enum ID: String, CaseIterable {
        case `default` = "default"
        case custom = "custom"
        case midnight = "midnight"
        case sunset = "sunset"

        var displayName: String {
            switch self {
            case .default: return "默认"
            case .custom: return "自定颜色"
            case .midnight: return "Midnight"
            case .sunset: return "Sunset"
            }
        }
    }

    @AppStorage("win97.theme.id") var themeIDRaw: String = ID.midnight.rawValue
    @AppStorage("win97.theme.customColor") var customColorHex: String = "#2F6BFF"
    @AppStorage("win97.theme.plainBackground") var plainBackground: Bool = false
    @AppStorage("win97.theme.colorfulCards") var colorfulCards: Bool = false
    /// 固定卡片颜色的 hex；空串 = 不固定，按主题色轮着来。
    @AppStorage("win97.theme.cardColor") var cardColorHex: String = ""

    var themeID: ID {
        get { ID(rawValue: themeIDRaw) ?? .midnight }
        set { themeIDRaw = newValue.rawValue }
    }

    var customColor: Color {
        get { Color(hex: customColorHex) }
        set { customColorHex = newValue.hexString }
    }

    var fixedCardColor: Color? {
        get { cardColorHex.isEmpty ? nil : Color(hex: cardColorHex) }
        set { cardColorHex = newValue?.hexString ?? "" }
    }

    /// 当前主题的定义（自定颜色是现算的：底用深蓝黑，光晕是自定颜色加透明度）。
    var currentDefinition: ThemeDefinition {
        switch themeID {
        case .default:
            // 默认不套主题：给一套 App 原来的深色，背景图那页自己处理。
            return ThemeDefinition(
                id: "default", name: "默认",
                dark: ThemeVariant(backgroundTop: Color(hex: "#171A21"), backgroundBottom: Color(hex: "#101218"),
                                   glows: [Color(hex: "#78829659"), Color(hex: "#5A647866"), Color(hex: "#46506440"), Color(hex: "#646E8233")],
                                   accent: Color(hex: "#0A84FF"), card: nil, plain: Color(hex: "#000000")),
                light: ThemeVariant(backgroundTop: .white, backgroundBottom: Color(hex: "#F2F2F7"),
                                    glows: [], accent: Color(hex: "#0A84FF"), card: nil, plain: .white),
                tiles: [])
        case .custom:
            let c = customColor
            return ThemeDefinition(
                id: "custom", name: "自定颜色",
                dark: ThemeVariant(backgroundTop: Color(hex: "#0B0F1C"), backgroundBottom: Color(hex: "#070A12"),
                                   glows: [c.opacity(0.62), c.opacity(0.40), c.opacity(0.33), c.opacity(0.23)],
                                   accent: c, card: nil, plain: Color(hex: "#070A12")),
                light: ThemeVariant(backgroundTop: Color(hex: "#F2F4F8"), backgroundBottom: Color(hex: "#E8ECF2"),
                                    glows: [c.opacity(0.50), c.opacity(0.38), c.opacity(0.33), c.opacity(0.25)],
                                    accent: c, card: nil, plain: .white),
                tiles: (0..<8).map { i in
                    (c.lightened(by: 0.30 - Double(i) * 0.03), c)
                })
        case .midnight:
            return BuiltinThemes.midnight
        case .sunset:
            return BuiltinThemes.sunset
        }
    }

    /// 当前深浅下的一套颜色（App 强制深色，实际走 dark；light 留着备用）。
    func colors(for scheme: ColorScheme) -> ThemeVariant {
        scheme == .dark ? currentDefinition.dark : currentDefinition.light
    }

    /// 卡片描边的渐变：固定了卡片颜色就用纯色，没固定就按主题 tiles 轮着来。
    /// id 用壁纸的 id，同一个壁纸每次算出来是同一个色（不会切页就变）。
    func cardGradient(forItemID id: String) -> LinearGradient {
        if let fixed = fixedCardColor {
            return LinearGradient(colors: [fixed, fixed], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        let tiles = currentDefinition.tiles
        guard !tiles.isEmpty else {
            let accent = currentDefinition.dark.accent
            return LinearGradient(colors: [accent, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        var hash = 0
        for scalar in id.unicodeScalars {
            hash = (hash &* 31) &+ Int(scalar.value)
        }
        // 用掩码去符号位，不用 abs（hash 恰好是 Int.min 时 abs 会 trap）。
        let pair = tiles[(hash & 0x7FFFFFFF) % tiles.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 卡片底色：主题自带 card 就用它（Sunset dark 没有，就用 accent 加透明度凑）。
    func cardBackground(for scheme: ColorScheme) -> Color {
        let variant = colors(for: scheme)
        if let card = variant.card { return card }
        return variant.accent.opacity(0.14)
    }
}

// MARK: - 主题背景

/// 主题渐变 + 四团光晕（照 WQ 主题页预览的位置摆）。
/// 默认主题返回透明（外层 AppBackgroundView 会垫原来的背景图）。
struct ThemeBackgroundView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if theme.themeID == .default {
            Color.clear
        } else {
            let variant = theme.colors(for: scheme)
            GeometryReader { geo in
                ZStack {
                    if theme.plainBackground {
                        (variant.plain ?? variant.backgroundTop)
                    } else {
                        LinearGradient(
                            colors: [variant.backgroundTop, variant.backgroundBottom],
                            startPoint: .top, endPoint: .bottom)
                        // 四团光晕：左上、右上、左下、右中。
                        Circle().fill(variant.glows[0]).frame(width: 300, height: 300).blur(radius: 70)
                            .position(x: -10, y: 10)
                        Circle().fill(variant.glows[1]).frame(width: 300, height: 300).blur(radius: 70)
                            .position(x: geo.size.width + 20, y: 40)
                        Circle().fill(variant.glows[2]).frame(width: 300, height: 300).blur(radius: 70)
                            .position(x: 0, y: geo.size.height + 20)
                        Circle().fill(variant.glows[3]).frame(width: 300, height: 300).blur(radius: 70)
                            .position(x: geo.size.width + 30, y: geo.size.height * 0.42)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - 主题设置页

/// 状态页“主题”卡点进来的二级页（照确认过的预览画的）。
struct ThemeSettingsView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { theme.colors(for: scheme).accent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 四项主题。
                VStack(spacing: 0) {
                    themeRow(id: .default, title: "默认", subtitle: "App 现在的样子，不套任何主题",
                             bar: LinearGradient(colors: [Color(hex: "#3A3F4A"), Color(hex: "#171A21")],
                                                 startPoint: .leading, endPoint: .trailing))
                    Divider().background(Color.white.opacity(0.08)).padding(.leading, 14)
                    customRow
                    Divider().background(Color.white.opacity(0.08)).padding(.leading, 14)
                    themeRow(id: .midnight, title: "Midnight", subtitle: "内置 · 深蓝",
                             bar: LinearGradient(colors: [Color(hex: "#2F6BFF"), Color(hex: "#00C2FF"), Color(hex: "#7A5CFF")],
                                                 startPoint: .leading, endPoint: .trailing))
                    Divider().background(Color.white.opacity(0.08)).padding(.leading, 14)
                    themeRow(id: .sunset, title: "Sunset", subtitle: "内置 · 暖橙",
                             bar: LinearGradient(colors: [Color(hex: "#FF6A3D"), Color(hex: "#FF2E7A"), Color(hex: "#FFC24A")],
                                                 startPoint: .leading, endPoint: .trailing))
                }
                .background(theme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1))

                Text("轻点主题即可使用，深色和浅色自动跟随系统。")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                // 三个开关。
                VStack(spacing: 0) {
                    Toggle(isOn: $theme.plainBackground) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("纯色背景").font(.headline)
                            Text("打开后背景用纯色，不用渐变和光晕").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    Divider().background(Color.white.opacity(0.08)).padding(.leading, 14)
                    Toggle(isOn: $theme.colorfulCards) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("彩色卡片").font(.headline)
                            Text("目录里的壁纸卡片带上主题色").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    Divider().background(Color.white.opacity(0.08)).padding(.leading, 14)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("卡片颜色").font(.headline)
                            Text("每张卡片使用其图标的颜色").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if theme.fixedCardColor != nil {
                            Button("恢复轮换") { theme.fixedCardColor = nil }
                                .font(.caption).foregroundStyle(accent)
                        }
                        ColorPicker("", selection: Binding(
                            get: { theme.fixedCardColor ?? theme.colors(for: scheme).accent },
                            set: { theme.fixedCardColor = $0 }
                        ), supportsOpacity: false)
                        .labelsHidden()
                    }
                    .padding(14)
                }
                .background(theme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1))

                Text("挑一个固定颜色后，全部卡片都用这个颜色；不挑就按主题色轮着来。")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                Text("主题只改 App 的样子，不改壁纸和安装。\n换主题立刻生效，不用重启 App。")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding()
        }
        .background(AppBackgroundView())
        .navigationTitle("主题")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 一行主题：名字、说明、右边色条、选中打勾。
    private func themeRow(id: ThemeManager.ID, title: String, subtitle: String, bar: LinearGradient) -> some View {
        Button {
            theme.themeID = id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                RoundedRectangle(cornerRadius: 8)
                    .fill(bar)
                    .frame(width: 56, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.25), lineWidth: 1))
                if theme.themeID == id {
                    Image(systemName: "checkmark")
                        .font(.headline).foregroundStyle(accent)
                } else {
                    // 占位，让没选中的行跟选中的行对齐。
                    Image(systemName: "checkmark")
                        .font(.headline).foregroundStyle(.clear)
                }
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(theme.themeID == id ? accent.opacity(0.14) : Color.clear)
    }

    /// 自定颜色那行：右边是个取色器，点了就切到自定颜色。
    private var customRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("自定颜色").font(.headline)
                Text("自己挑一个颜色当主题色").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ColorPicker("", selection: Binding(
                get: { theme.customColor },
                set: {
                    theme.customColor = $0
                    theme.themeID = .custom
                }
            ), supportsOpacity: false)
            .labelsHidden()
            if theme.themeID == .custom {
                Image(systemName: "checkmark")
                    .font(.headline).foregroundStyle(accent)
            } else {
                Image(systemName: "checkmark")
                    .font(.headline).foregroundStyle(.clear)
            }
        }
        .padding(14)
        .contentShape(Rectangle())
        .onTapGesture { theme.themeID = .custom }
        .background(theme.themeID == .custom ? accent.opacity(0.14) : Color.clear)
    }
}
