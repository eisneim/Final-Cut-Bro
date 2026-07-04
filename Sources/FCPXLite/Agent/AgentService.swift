import Foundation

/// Agent 流式对话循环:用户消息 → LLM(流式,带工具+时间线状态)→ 实时显示文本/推理/工具调用 →
/// 执行工具(改剪辑)→ 结果喂回 → 循环到最终回复。可中止(stop)。
/// 消息流实时写入 store.agentMessages 供 Chat UI 渲染。
@MainActor
final class AgentService {
    let store: DocumentStore
    let registry: AgentToolRegistry
    let backend: StreamingLLMBackend
    let maxToolRounds: Int

    init(store: DocumentStore, backend: StreamingLLMBackend, maxToolRounds: Int = 16) {
        self.store = store
        self.registry = AgentToolRegistry(store: store)
        self.backend = backend
        self.maxToolRounds = maxToolRounds
    }

    private static let systemPrompt = """
    你是 Final Cut Bro(一个简化版 Final Cut Pro,"AI 帮你剪的兄弟")的剪辑助手。用户用中文描述剪辑意图,你用提供的工具操作时间线。
    你通过 5 个工具操作剪辑:
    - query_timeline:先调它看当前素材库/时间线(片段用 0 基 index,时间用秒)。
    - timeline_edit:改结构(insert/append/connect/delete/move/blade/trim/set_gap/position_move/blade_at/batch_blade/build_subtitle_cut)。
    - clip_adjust:改画面/音频(scale/position/crop/opacity/volume)、特效(add_effect/remove_effect/set_effect_param,kind=color/blur/fade)、停用启用片段(toggle_enabled)。
    - navigate:导航/选择/撤销/导入(playhead/zoom/tool/select/select_asset/undo/redo/import)、导出(export_fcpxml 工程 / export_movie 渲染成片)。
    - file_ops:本地文件操作(read_file 读文件/write_file 写文件(需确认)/edit_file 编辑文件(需确认)/list_directory 列目录)。
    - shell:跑 shell 命令 run_command(ffprobe/ffmpeg 探测处理音视频、python 数据分析等;素材绝对路径见 query_timeline;高危命令需确认)。
    每个编辑工具都传 type=动作名 + 该动作的参数。操作前先 query_timeline 确认最新 index。
    若要求"做完整条片子",记得最后用 export_movie 导出成片。完成后用一句话总结你做了什么。
    """

    /// 处理一条用户消息(流式)。返回时整轮结束或被取消。
    func send(userText: String) async {
        store.agentMessages.append(AgentMessage(role: .user, text: userText))
        store.agentBusy = true
        store.agentConfirmResult = nil   // 清掉上一轮(可能被取消)遗留的结果,避免被本轮误取
        store.agentAsyncResult = nil
        defer { store.agentBusy = false }

        var wire: [LLMWireMessage] = [
            LLMWireMessage(role: "system", content: Self.systemPrompt + "\n\n当前状态:\n" + registry.timelineSummary()),
        ]
        for m in store.agentMessages where m.role != .tool {
            wire.append(LLMWireMessage(role: m.role == .user ? "user" : "assistant", content: m.text))
        }

        for _ in 0..<maxToolRounds {
            if Task.isCancelled { markStopped(); return }

            // 本轮的实时 assistant 气泡
            let asstId = UUID()
            store.agentMessages.append(AgentMessage(id: asstId, role: .assistant, text: "", streaming: true))
            var asstText = ""; var asstThink = ""
            var roundCalls: [LLMToolCall] = []
            var toolMsgIds: [String: UUID] = [:]   // toolCall.id → 对应的 tool 气泡

            // 流式文本【按时间节流 flush】(~18Hz):避免每个 token 都改 agentMessages,
            // 否则 ChatPanelView 逐 token 重建列表挤爆主线程、饿死时间轴拖拽/重画。
            var pendingFlush = false
            var lastFlushNanos = DispatchTime.now().uptimeNanoseconds
            let flushIntervalNanos: UInt64 = 55_000_000   // ~18Hz
            func flushStreamText() {
                guard pendingFlush else { return }
                PerfProbe.shared.count("chat.flush")
                updateMsg(asstId) { $0.text = asstText; $0.think = asstThink }
                pendingFlush = false
                lastFlushNanos = DispatchTime.now().uptimeNanoseconds
            }

            do {
                for try await ev in backend.stream(messages: wire, tools: registry.toolsJSON()) {
                    if Task.isCancelled { markStopped(); return }
                    PerfProbe.shared.measure("AgentService.tokenApply") {
                    switch ev {
                    case .textDelta(let d):
                        asstText += d; pendingFlush = true          // 累加,节流时才写入
                    case .thinkDelta(let d):
                        asstThink += d; pendingFlush = true
                    case .toolCallBegin(let id, let name):
                        flushStreamText()                            // 工具气泡前先把已累积文本落地(保证顺序)
                        let tid = UUID(); toolMsgIds[id] = tid
                        store.agentMessages.append(AgentMessage(id: tid, role: .tool, text: "调用中…", toolName: name, toolArgs: "", streaming: true))
                    case .toolCallArg(let id, let chunk):
                        if let tid = toolMsgIds[id] { updateMsg(tid) { $0.toolArgs = ($0.toolArgs ?? "") + chunk } }
                    case .toolCallEnd(let id, let name, let args):
                        roundCalls.append(LLMToolCall(id: id, name: name, args: args))
                        _ = id
                    case .error(let m):
                        updateMsg(asstId) { $0.text = (asstText.isEmpty ? "" : asstText + "\n") + "出错:" + m; $0.streaming = false }
                    case .done: break
                    }
                    }
                    if case .error = ev { return }
                    // 节流:距上次 flush 超过间隔才写入(终止事件由循环后的 trailing flush 兜底)
                    if pendingFlush, DispatchTime.now().uptimeNanoseconds - lastFlushNanos > flushIntervalNanos {
                        flushStreamText()
                    }
                }
            } catch {
                updateMsg(asstId) { $0.text = "出错:\(error.localizedDescription)"; $0.streaming = false }
                return
            }

            flushStreamText()   // trailing flush:保证最后一批文字不丢
            updateMsg(asstId) { $0.streaming = false }

            if roundCalls.isEmpty { return }   // 最终回复,结束

            // assistant 发起工具调用 → 执行 → 结果喂回
            wire.append(LLMWireMessage(role: "assistant", content: asstText, toolCalls: roundCalls))
            for tc in roundCalls {
                var result = registry.execute(name: tc.name, args: tc.args)   // ← 真正改剪辑
                if result == "__PENDING_CONFIRM__" {
                    // 危险操作:等用户在 confirm 卡片点允许/拒绝。
                    if let tid = toolMsgIds[tc.id] { updateMsg(tid) { $0.text = "等待用户确认…"; $0.streaming = false } }
                    while store.agentConfirm != nil {
                        if Task.isCancelled { markStopped(); return }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                    result = store.agentConfirmResult?.result ?? "用户未响应"
                    store.agentConfirmResult = nil
                } else if result == "__PENDING_ASYNC__" {
                    // 后台命令(run_command,如 ffmpeg/python):在后台线程跑,主线程不冻结,轮询结果。
                    let cmd = (tc.args["command"] as? String) ?? ""
                    let hint = cmd.isEmpty ? "执行中…" : "执行中: \(cmd.prefix(80))"
                    if let tid = toolMsgIds[tc.id] { updateMsg(tid) { $0.text = hint; $0.streaming = false } }
                    while store.agentAsyncResult == nil {
                        if Task.isCancelled { markStopped(); return }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                    result = store.agentAsyncResult?.result ?? "(无结果)"
                    store.agentAsyncResult = nil
                }
                // 统一落地:更新 tool 气泡 + 喂回 LLM
                if let tid = toolMsgIds[tc.id] {
                    updateMsg(tid) { $0.text = result; $0.streaming = false }
                } else {
                    store.agentMessages.append(AgentMessage(role: .tool, text: result, toolName: tc.name))
                }
                wire.append(LLMWireMessage(role: "tool", content: result, toolCallId: tc.id, name: tc.name))
            }
        }
        store.agentMessages.append(AgentMessage(role: .assistant, text: "(已达到最大工具步数,停止)"))
    }

    private func updateMsg(_ id: UUID, _ f: (inout AgentMessage) -> Void) {
        if let i = store.agentMessages.firstIndex(where: { $0.id == id }) { f(&store.agentMessages[i]) }
    }
    private func markStopped() {
        for i in store.agentMessages.indices where store.agentMessages[i].streaming {
            store.agentMessages[i].streaming = false
        }
        store.agentMessages.append(AgentMessage(role: .assistant, text: "(已停止)"))
    }
}
