import SwiftUI

struct PanelPlaceholder: View {
    let title: String
    var background: Color = Tokens.Palette.chrome
    var body: some View {
        ZStack {
            background
            Text(title).font(Tokens.Typeface.body).foregroundStyle(Tokens.Palette.textMuted)
        }
    }
}

struct ChatPanelView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("🤖 Agent").font(Tokens.Typeface.body)
                       .foregroundStyle(Tokens.Palette.textCool); Spacer() }
                .padding(8)
                .background(Tokens.Palette.elevated)
            PanelPlaceholder(title: "对话区(M2 接入)", background: Tokens.Palette.chatPanel)
            HStack { Text("和 Agent 对话…").font(Tokens.Typeface.label)
                       .foregroundStyle(Tokens.Palette.textMuted); Spacer() }
                .padding(8).background(Tokens.Palette.elevated).cornerRadius(5).padding(8)
        }
        .frame(width: Tokens.Metric.chatWidth)
        .background(Tokens.Palette.chatPanel)
    }
}
