import Foundation
import Observation

/// 支持的界面语言。加一门语言 = 加一个 case + 在 Strings.table 各条目补该语言译文。
enum Language: String, Codable, CaseIterable, Identifiable {
    case zh, en
    var id: String { rawValue }
    /// 下拉菜单里的原生名。
    var nativeName: String {
        switch self { case .zh: return "中文"; case .en: return "English" }
    }
    /// toggle 上的短码。
    var shortCode: String {
        switch self { case .zh: return "中"; case .en: return "EN" }
    }
}

/// 运行时可切换的本地化(不重启)。全局单例;SwiftUI 在 body 里调用 `t(...)` 会读到 `language`
/// 从而被 @Observable 追踪 → 切换语言即刷新界面。AppKit(菜单栏)用 .fcbLanguageChanged 通知手动重建。
@Observable final class Localization {
    static let shared = Localization()

    var language: Language {
        didSet {
            guard oldValue != language else { return }
            LocalizationPersistence.save(language: language, enabled: enabledLanguages)
            NotificationCenter.default.post(name: .fcbLanguageChanged, object: nil)
        }
    }
    /// 出现在切换器里的语言集合(≤2 → 顶栏用 toggle;>2 → 下拉菜单)。至少含当前语言。
    var enabledLanguages: [Language] {
        didSet { LocalizationPersistence.save(language: language, enabled: enabledLanguages) }
    }

    private init() {
        let saved = LocalizationPersistence.load()
        self.language = saved.language
        self.enabledLanguages = saved.enabled.isEmpty ? [.zh, .en] : saved.enabled
    }

    /// 取译文。中文=原文直通(中文源串即 key);其他语言查表,缺失回退中文原文。
    func t(_ zh: String) -> String { Self.translate(zh, to: language) }

    /// 纯查表(无副作用,可单测):中文直通;其他语言查表,缺失回退中文原文。
    static func translate(_ zh: String, to lang: Language) -> String {
        lang == .zh ? zh : (Strings.table[zh]?[lang] ?? zh)
    }

    /// 顶栏 toggle:切到 enabledLanguages 里的下一个。
    func toggle() {
        guard let i = enabledLanguages.firstIndex(of: language), enabledLanguages.count >= 2 else {
            if let other = enabledLanguages.first(where: { $0 != language }) { language = other }
            return
        }
        language = enabledLanguages[(i + 1) % enabledLanguages.count]
    }

    /// 在切换器里启用/停用某语言(当前语言不可移除)。
    func setEnabled(_ lang: Language, _ on: Bool) {
        if on {
            if !enabledLanguages.contains(lang) { enabledLanguages.append(lang) }
        } else if lang != language {
            enabledLanguages.removeAll { $0 == lang }
        }
    }
}

extension Notification.Name {
    static let fcbLanguageChanged = Notification.Name("FCBLanguageChanged")
}

/// 全局便捷:t("中文原文") → 当前语言译文。在 SwiftUI body 内调用会随语言切换自动刷新。
func t(_ zh: String) -> String { Localization.shared.t(zh) }

/// 语言偏好持久化:~/Library/Application Support/FCPXLite/language.json
enum LocalizationPersistence {
    private struct Saved: Codable { var language: Language; var enabled: [Language] }

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FCPXLite", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("language.json")
    }

    /// 无文件(首次启动)→ 默认中文,启用中/英。
    static func load() -> (language: Language, enabled: [Language]) {
        guard let d = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(Saved.self, from: d) else {
            return (.zh, [.zh, .en])
        }
        return (s.language, s.enabled)
    }

    static func save(language: Language, enabled: [Language]) {
        if let d = try? JSONEncoder().encode(Saved(language: language, enabled: enabled)) {
            try? d.write(to: url)
        }
    }
}
