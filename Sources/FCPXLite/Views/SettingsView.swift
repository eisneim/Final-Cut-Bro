import SwiftUI

/// 设置弹窗:选择 LLM provider(预设 stepfun/minimax/deepseek)。API key 从环境变量读,显示是否已配置。
struct SettingsView: View {
    let store: DocumentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("设置").font(Tokens.Typeface.title).foregroundStyle(Tokens.Palette.textPrimary)
                Spacer()
                Button { store.ui.showSettings = false } label: {
                    Image(systemName: "xmark").foregroundStyle(Tokens.Palette.textMuted)
                }.buttonStyle(.plain)
            }
            .padding(14)
            Divider().overlay(Tokens.Palette.divider)

            VStack(alignment: .leading, spacing: 12) {
                Text("AI Provider").font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textPrimary)
                ForEach(LLMProvider.presets) { p in
                    providerRow(p)
                }
            }
            .padding(14)
            Spacer()
        }
        .frame(width: 420, height: 360)
        .background(Tokens.Palette.chrome)
    }

    private func providerRow(_ p: LLMProvider) -> some View {
        let selected = store.ui.providerId == p.id
        let hasKey = p.apiKey != nil
        return Button {
            store.ui.providerId = p.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Tokens.Palette.selectYellow : Tokens.Palette.textMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.label).font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textPrimary)
                    Text("\(p.model) · \(p.baseURL)").font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
                }
                Spacer()
                Text(hasKey ? "✓ key 已配" : "✗ 未配 \(p.envKey)")
                    .font(.system(size: 10))
                    .foregroundStyle(hasKey ? Tokens.Palette.windowZoom : Tokens.Palette.windowClose)
            }
            .padding(10)
            .background(selected ? Tokens.Palette.elevated : Tokens.Palette.chatPanel)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
