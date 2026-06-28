import SwiftUI

/// 设置弹窗 = Provider 配置(增删改)。参考 shotCrafter ProviderConfigModal:
/// 一键预设填充 Base URL/模型 → 用户粘贴 API Key → 添加;列表可编辑/删除。持久化到磁盘。
struct SettingsView: View {
    let store: DocumentStore

    // 表单草稿(模态内瞬时编辑态,本地 @State)
    @State private var label = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var vision = false
    @State private var editingId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Tokens.Palette.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    hint
                    presets
                    form
                    Divider().overlay(Tokens.Palette.divider)
                    list
                }
                .padding(14)
            }
        }
        .frame(width: 460, height: 560)
        .background(Tokens.Palette.chrome)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("配置大模型 Provider").font(Tokens.Typeface.title).foregroundStyle(Tokens.Palette.textPrimary)
            Spacer()
            Button { store.ui.showSettings = false } label: {
                Image(systemName: "xmark").foregroundStyle(Tokens.Palette.textMuted)
            }.buttonStyle(.plain)
        }
        .padding(14)
    }

    private var hint: some View {
        Text("填写一个 OpenAI 兼容的模型服务(Base URL / API Key / 模型名)。勾选「支持视觉」后该模型可接收参考图。")
            .font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
    }

    // MARK: - 一键预设

    private var presets: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("快速填充").font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(ProviderPreset.all) { p in
                    Button {
                        label = p.label; baseURL = p.baseURL; model = p.model; vision = p.vision
                    } label: {
                        Text(p.label).font(.system(size: 11)).foregroundStyle(Tokens.Palette.textPrimary)
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(Tokens.Palette.elevated).cornerRadius(5)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 表单

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("名称(选填)", text: $label, placeholder: "如 我的 MiniMax")
            field("Base URL", text: $baseURL, placeholder: "https://api.xxx.com/v1")
            secureField("API Key" + (editingId != nil ? "(留空则不变)" : ""), text: $apiKey,
                        placeholder: editingId != nil ? "••••(留空则不变)" : "sk-...")
            field("模型名称", text: $model, placeholder: "如 MiniMax-M3")
            Toggle(isOn: $vision) {
                Text("支持视觉 / 图片输入(多模态)").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textPrimary)
            }
            .toggleStyle(.checkbox)
            HStack {
                Button(action: save) {
                    Text(editingId != nil ? "保存修改" : "添加")
                        .font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.onAccent)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(canSave ? Tokens.Palette.clipBlue : Tokens.Palette.elevated).cornerRadius(6)
                }.buttonStyle(.plain).disabled(!canSave)
                if editingId != nil {
                    Button("取消编辑", action: resetForm).buttonStyle(.plain)
                        .font(.system(size: 11)).foregroundStyle(Tokens.Palette.textMuted)
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
            TextField(placeholder, text: text).textFieldStyle(.plain)
                .font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textPrimary)
                .padding(7).background(Tokens.Palette.elevated).cornerRadius(5)
        }
    }

    private func secureField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
            SecureField(placeholder, text: text).textFieldStyle(.plain)
                .font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textPrimary)
                .padding(7).background(Tokens.Palette.elevated).cornerRadius(5)
        }
    }

    // MARK: - 已配置列表

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("已配置(\(store.providers.count))").font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
            if store.providers.isEmpty {
                Text("还没有配置任何 provider").font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(store.providers) { p in providerRow(p) }
            }
        }
    }

    private func providerRow(_ p: ProviderConfig) -> some View {
        let isCurrent = store.ui.providerId == p.id
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(p.label).font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textPrimary)
                    if p.vision { Text("🖼").font(.system(size: 10)) }
                    if isCurrent { Text("· 使用中").font(.system(size: 9)).foregroundStyle(Tokens.Palette.selectYellow) }
                }
                Text("\(p.model) · \(p.host) · \(p.hasKey ? "🔑 ••••" : "⚠ 无 key")")
                    .font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
            }
            Spacer()
            Button { startEdit(p) } label: { Image(systemName: "pencil").foregroundStyle(Tokens.Palette.textMuted) }
                .buttonStyle(.plain).help("编辑")
            Button { store.deleteProvider(p.id) } label: { Image(systemName: "trash").foregroundStyle(Tokens.Palette.windowClose) }
                .buttonStyle(.plain).help("删除")
        }
        .padding(8)
        .background(editingId == p.id ? Tokens.Palette.elevated : Tokens.Palette.chatPanel)
        .cornerRadius(6)
    }

    // MARK: - 动作

    private var canSave: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !model.trimmingCharacters(in: .whitespaces).isEmpty &&
        (editingId != nil || !apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func save() {
        let name = label.trimmingCharacters(in: .whitespaces).isEmpty ? model : label
        if let id = editingId, var existing = store.providers.first(where: { $0.id == id }) {
            existing.label = name; existing.baseURL = baseURL; existing.model = model; existing.vision = vision
            if !apiKey.trimmingCharacters(in: .whitespaces).isEmpty { existing.apiKey = apiKey }
            store.updateProvider(existing)
        } else {
            store.addProvider(.new(label: name, baseURL: baseURL, apiKey: apiKey, model: model, vision: vision))
        }
        resetForm()
    }

    private func startEdit(_ p: ProviderConfig) {
        editingId = p.id; label = p.label; baseURL = p.baseURL; model = p.model; vision = p.vision; apiKey = ""
    }

    private func resetForm() {
        label = ""; baseURL = ""; apiKey = ""; model = ""; vision = false; editingId = nil
    }
}
