import Foundation

/// 用户可配置的 LLM provider(OpenAI 兼容)。可在设置里增删改,持久化到磁盘。
/// 参考 shotCrafter ProviderConfigModal:Base URL / API Key / 模型 / 是否支持视觉。
struct ProviderConfig: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var baseURL: String
    var apiKey: String
    var model: String
    var vision: Bool

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
    var host: String { URL(string: baseURL)?.host ?? baseURL }

    static func new(label: String, baseURL: String, apiKey: String, model: String, vision: Bool) -> ProviderConfig {
        ProviderConfig(id: UUID().uuidString, label: label, baseURL: baseURL, apiKey: apiKey, model: model, vision: vision)
    }
}

/// 一键预设:填 Base URL / 模型 /(视觉),用户只需粘贴 key。
struct ProviderPreset: Identifiable {
    var id: String { label }
    let label: String
    let baseURL: String
    let model: String
    let vision: Bool
    let envKey: String?   // 首次启动从此环境变量种子 key(向后兼容 STEP_API_KEY 等)

    static let all: [ProviderPreset] = [
        .init(label: "StepFun",     baseURL: "https://api.stepfun.com/v1",            model: "step-3.7-flash",    vision: true,  envKey: "STEP_API_KEY"),
        .init(label: "MiniMax",     baseURL: "https://api.minimaxi.com/v1",           model: "MiniMax-M3",        vision: true,  envKey: "MINIMAX_API_KEY"),
        .init(label: "DeepSeek",    baseURL: "https://api.deepseek.com/v1",           model: "deepseek-v4-flash", vision: false, envKey: "DEEPSEEK_API_KEY"),
        .init(label: "OpenAI",      baseURL: "https://api.openai.com/v1",             model: "gpt-4o",            vision: true,  envKey: "OPENAI_API_KEY"),
        .init(label: "Kimi",        baseURL: "https://api.moonshot.cn/v1",            model: "kimi-k2.6",         vision: true,  envKey: "MOONSHOT_API_KEY"),
        .init(label: "GLM",         baseURL: "https://open.bigmodel.cn/api/paas/v4/", model: "glm-5.1",           vision: false, envKey: "ZHIPU_API_KEY"),
        .init(label: "Xiaomi MiMo", baseURL: "https://api.xiaomimimo.com/v1",         model: "mimo-v2.5",         vision: true,  envKey: "XIAOMI_API_KEY"),
    ]
}

/// provider 配置持久化:~/Library/Application Support/FCPXLite/providers.json
enum ProviderPersistence {
    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FCPXLite", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("providers.json")
    }

    static func load() -> [ProviderConfig] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([ProviderConfig].self, from: data),
              !list.isEmpty else {
            return seedFromEnv()
        }
        return list
    }

    static func save(_ list: [ProviderConfig]) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(list) { try? data.write(to: fileURL) }
    }

    /// 首次启动:从环境变量种子已有 key 的 preset(向后兼容)。id 用 preset 名小写,默认选中可对上。
    private static func seedFromEnv() -> [ProviderConfig] {
        let env = ProcessInfo.processInfo.environment
        return ProviderPreset.all.compactMap { p in
            guard let ek = p.envKey, let key = env[ek],
                  !key.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return ProviderConfig(id: p.label.lowercased(), label: p.label,
                                  baseURL: p.baseURL, apiKey: key, model: p.model, vision: p.vision)
        }
    }
}
