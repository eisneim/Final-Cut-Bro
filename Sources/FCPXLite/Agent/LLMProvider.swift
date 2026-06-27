import Foundation

/// LLM provider 预设(OpenAI 兼容)。默认 stepfun。API key 从对应环境变量读。
/// 参考 shotCrafter/src/shared/config.ts 的 provider 列表。
struct LLMProvider: Identifiable, Equatable {
    let id: String
    let label: String
    let baseURL: String
    let model: String
    let envKey: String

    static let presets: [LLMProvider] = [
        LLMProvider(id: "stepfun",  label: "StepFun",  baseURL: "https://api.stepfun.com/v1",  model: "step-3.7-flash",     envKey: "STEP_API_KEY"),
        LLMProvider(id: "minimax",  label: "MiniMax",  baseURL: "https://api.minimaxi.com/v1", model: "MiniMax-M3",         envKey: "MINIMAX_API_KEY"),
        LLMProvider(id: "deepseek", label: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-v4-flash",  envKey: "DEEPSEEK_API_KEY"),
    ]
    static let defaultId = "stepfun"

    static func preset(_ id: String) -> LLMProvider { presets.first { $0.id == id } ?? presets[0] }

    /// 从环境变量取该 provider 的 API key。
    var apiKey: String? {
        let e = ProcessInfo.processInfo.environment
        if let k = e[envKey], !k.trimmingCharacters(in: .whitespaces).isEmpty { return k }
        return nil
    }
}
