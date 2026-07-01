import SwiftUI

/// Agent 对话面板:消息列表(流式 + 推理 + 工具调用)+ 设置按钮 + 多行输入框 + 发送/停止。
/// 用户在输入框打字 → store.sendAgentMessage()(与 harness 同一路径)→ 流式驱动剪辑。
struct ChatPanelView: View {
    let store: DocumentStore
    @State private var collapsedThinks: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Tokens.Palette.divider)
            messageList
            Divider().overlay(Tokens.Palette.divider)
            inputArea
        }
        .frame(maxWidth: .infinity)
        .background(Tokens.Palette.chatPanel)
        .sheet(isPresented: Binding(get: { store.ui.showSettings }, set: { store.ui.showSettings = $0 })) {
            SettingsView(store: store)
        }
    }

    // MARK: - Header(标题 + 设置按钮)

    private var header: some View {
        HStack(spacing: 6) {
            providerPicker
            Spacer()
            if store.agentBusy { ProgressView().controlSize(.small).padding(.trailing, 4) }
            Button { store.ui.showSettings = true } label: {
                Image(systemName: "gearshape").foregroundStyle(Tokens.Palette.textMuted)
            }
            .buttonStyle(.plain)
            .help("设置(配置 AI provider)")
        }
        .padding(8)
        .background(Tokens.Palette.elevated)
    }

    /// chat 左上角:下拉菜单选择 provider,按钮上显示当前模型名。
    private var providerPicker: some View {
        Menu {
            if store.providers.isEmpty {
                Text("未配置 provider")
            } else {
                ForEach(store.providers) { p in
                    Button {
                        store.selectProvider(p.id)
                    } label: {
                        if store.ui.providerId == p.id {
                            Label("\(p.label) · \(p.model)", systemImage: "checkmark")
                        } else {
                            Text("\(p.label) · \(p.model)")
                        }
                    }
                }
            }
            Divider()
            Button("配置 Provider…") { store.ui.showSettings = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu").font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted)
                Text(currentModelLabel).font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textCool).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(Tokens.Palette.textMuted)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var currentModelLabel: String {
        store.currentProvider()?.model ?? "选择模型"
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if store.agentMessages.isEmpty { emptyHint }
                    ForEach(store.agentMessages) { msg in messageRow(msg).id(msg.id) }
                }
                .padding(8)
            }
            .onChange(of: store.agentMessages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: store.agentBusy) { _, _ in scrollToEnd(proxy) }
            .onReceive(Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()) { _ in
                if store.agentBusy { scrollToEnd(proxy) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = store.agentMessages.last else { return }
        // 流式滚动不加动画:agentMessages 现已节流到 ~18Hz,逐次动画反而挤主线程。
        proxy.scrollTo(last.id, anchor: .bottom)
    }

    private var emptyHint: some View {
        Text("告诉我你想怎么剪。例如:\n「把第一个素材加到时间线」\n「在 2 秒处切一刀」\n「把素材2叠加到上层并缩小一半」")
            .font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.textMuted).padding(.vertical, 8)
    }

    /// 可折叠的推理过程:用 ChunkedStreamingView 分块渲染(thinking 越来越长是卡顿根源)。
    private func thinkBlock(_ m: AgentMessage) -> some View {
        let collapsed = collapsedThinks.contains(m.id)
        return Button {
            if collapsed { collapsedThinks.remove(m.id) } else { collapsedThinks.insert(m.id) }
        } label: {
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8)).foregroundStyle(Tokens.Palette.textMuted).padding(.top, 2)
                if collapsed {
                    Text("💭 思考过程(点击展开)").font(.system(size: 10))
                        .foregroundStyle(Tokens.Palette.textMuted).lineLimit(1)
                } else {
                    // 分块渲染:thinking 越来越长,只更新最后一块,前面的冻结不重算。
                    ChunkedStreamingView(text: "💭 " + m.think, streaming: m.streaming)
                }
                Spacer(minLength: 0)
            }
            .padding(6).background(Tokens.Palette.chrome).cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func messageRow(_ m: AgentMessage) -> some View {
        switch m.role {
        case .user:
            HStack { Spacer()
                Text(m.text).font(Tokens.Typeface.label).foregroundStyle(Tokens.Palette.onAccent)
                    .textSelection(.enabled)
                    .padding(8).background(Tokens.Palette.clipBlue).cornerRadius(8)
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                if !m.think.isEmpty { thinkBlock(m) }
                if !m.text.isEmpty || m.streaming {
                    HStack {
                        // 分块渲染:streaming 时只更新最后一块,完成后全部冻结。
                        ChunkedStreamingView(text: m.text, streaming: m.streaming)
                        Spacer()
                    }
                }
            }
        case .tool:
            HStack {
                Text("⚙ \(m.toolName ?? "")\(toolArgsBrief(m)) · \(m.text)")
                    .font(.system(size: 10)).foregroundStyle(Tokens.Palette.textMuted).lineLimit(2)
                    .textSelection(.enabled)
                Spacer()
            }
        case .confirm:
            confirmCard(m)
        }
    }

    /// 确认卡片:黄色警告 + "允许"/"拒绝" 按钮,用户点后 Agent 继续。
    private func confirmCard(_ m: AgentMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("需要确认").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.Palette.textPrimary)
            }
            Text(m.text).font(Tokens.Typeface.label)
                .foregroundStyle(Tokens.Palette.textPrimary)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Button { store.respondAgentConfirm(approve: true) } label: {
                    Text("允许").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Color.green).cornerRadius(6)
                }.buttonStyle(.plain)
                Button { store.respondAgentConfirm(approve: false) } label: {
                    Text("拒绝").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Color.red).cornerRadius(6)
                }.buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.yellow.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.5), lineWidth: 1))
        .cornerRadius(8)
    }

    private func toolArgsBrief(_ m: AgentMessage) -> String {
        guard let a = m.toolArgs, !a.isEmpty else { return "" }
        return "(\(a.prefix(40)))"
    }

    // MARK: - 输入区(多行 + 发送/停止 + ⌘↵ 提示)

    private var inputArea: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                TextField("和 Agent 对话…", text: Binding(
                    get: { store.ui.agentInput }, set: { store.ui.agentInput = $0 }
                ), axis: .vertical)
                .textFieldStyle(.plain)
                .font(Tokens.Typeface.label)
                .foregroundStyle(Tokens.Palette.textPrimary)
                .lineLimit(2...6)
                .frame(minHeight: 40, alignment: .topLeading)
                .padding(8)
                .background(Tokens.Palette.elevated)
                .cornerRadius(8)
                .onSubmit(send)   // 回车;⌘↵ 由按钮快捷键

                sendOrStopButton
            }
            HStack {
                Spacer()
                Text("⌘ + ↵ 发送").font(.system(size: 9)).foregroundStyle(Tokens.Palette.textMuted)
            }
        }
        .padding(8)
    }

    private var sendOrStopButton: some View {
        Group {
            if store.agentBusy {
                Button(action: store.stopAgent) {
                    Image(systemName: "stop.fill").foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(Tokens.Palette.windowClose).cornerRadius(8)
                }
                .buttonStyle(.plain).help("停止")
            } else {
                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(canSend ? Tokens.Palette.onAccent : Tokens.Palette.textMuted)
                        .frame(width: 36, height: 36)
                        .background(canSend ? Tokens.Palette.clipBlue : Tokens.Palette.elevated).cornerRadius(8)
                }
                .buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command).disabled(!canSend)
            }
        }
    }

    private var canSend: Bool { !store.ui.agentInput.trimmingCharacters(in: .whitespaces).isEmpty && !store.agentBusy }
    private func send() { store.sendAgentMessage() }
}
