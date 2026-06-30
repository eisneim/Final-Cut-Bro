#if DEBUG
import Foundation
import Network
import AppKit
import AVFoundation

/// DEBUG-only 本地控制服务器(原生版 __dpd):让外部驱动(agent)通过 HTTP
/// 读状态 / 改状态 / 截图,从而自动化端到端测试 UI 渲染。Release 构建不含此文件。
///
///   GET  /state            → 当前 {document, ui} 的 JSON
///   POST /cmd  {op:...}     → 执行一个高层操作,返回新状态
///   GET  /screenshot       → 把窗口 contentView 渲染成 PNG 返回
///
/// /cmd ops: importFile{path} / insertAsset{index,at} / setPlayhead{seconds} /
///           setZoom{px} / setTool{tool} / togglePlay / blade{seconds} /
///           selectSpineClip{index} / relocateSpineClip{index,lane,seconds} /
///           deleteSelected / toggleSnapping
final class DebugControlServer {
    private let store: DocumentStore
    private weak var window: NSWindow?
    private var listener: NWListener?
    let port: UInt16

    init(store: DocumentStore, window: NSWindow?, port: UInt16 = 8765) {
        self.store = store
        self.window = window
        self.port = port
    }

    func start() {
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            listener?.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .global())
                self?.receive(conn, buffer: Data())
            }
            listener?.start(queue: .global())
            NSLog("[DebugControlServer] http://127.0.0.1:\(port)  (/state /cmd /screenshot)")
        } catch {
            NSLog("[DebugControlServer] start failed: \(error)")
        }
    }

    // MARK: - HTTP 接收/解析(单请求单连接)

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }

            if let req = Self.parse(buf) {
                self.route(conn, req)
                return
            }
            if isComplete || error != nil { conn.cancel(); return }
            self.receive(conn, buffer: buf)
        }
    }

    private struct Request { let method: String; let path: String; let body: Data }

    private static func parse(_ buf: Data) -> Request? {
        guard let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buf.subdata(in: buf.startIndex..<headerEnd.lowerBound)
        guard let header = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = header.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let method = parts[0], path = parts[1]

        var contentLength = 0
        for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
            contentLength = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let bodyStart = headerEnd.upperBound
        let available = buf.distance(from: bodyStart, to: buf.endIndex)
        if available < contentLength { return nil }   // body 未到齐
        let body = buf.subdata(in: bodyStart..<buf.index(bodyStart, offsetBy: contentLength))
        return Request(method: method, path: path, body: body)
    }

    // MARK: - 路由(store/UI 访问都切到主线程)

    private func route(_ conn: NWConnection, _ req: Request) {
        let pathOnly = req.path.components(separatedBy: "?").first ?? req.path
        switch (req.method, pathOnly) {
        case ("GET", "/state"):
            DispatchQueue.main.sync { sendJSON(conn, snapshotJSON()) }
        case ("POST", "/cmd"):
            DispatchQueue.main.sync {
                execute(body: req.body)
                sendJSON(conn, snapshotJSON())
            }
        case ("GET", "/screenshot"):
            DispatchQueue.main.sync {
                if let png = screenshotPNG() { sendPNG(conn, png) }
                else { sendText(conn, status: "500 No Image", "no window") }
            }
        case ("GET", "/layout"):
            DispatchQueue.main.sync {
                if let tc = findTimelineContentView() {
                    let data = (try? JSONSerialization.data(withJSONObject: tc.debugGeometryJSON(),
                                                            options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
                    sendJSON(conn, data)
                } else { sendText(conn, status: "500", "no timeline view") }
            }
        case ("GET", "/scale"):
            DispatchQueue.main.sync {
                var info: [String: Any] = [:]
                if let w = window {
                    info["windowBackingScaleFactor"] = w.backingScaleFactor
                    info["windowFrame"] = ["w": w.frame.width, "h": w.frame.height]
                    let px = w.convertToBacking(w.frame)
                    info["windowFrameInBackingPixels"] = ["w": px.width, "h": px.height]
                }
                if let scr = window?.screen ?? NSScreen.main {
                    info["screenFramePoints"] = ["w": scr.frame.width, "h": scr.frame.height]
                    info["screenBackingScaleFactor"] = scr.backingScaleFactor
                    let backing = scr.convertRectToBacking(scr.frame)
                    info["screenFrameBackingPixels"] = ["w": backing.width, "h": backing.height]
                }
                let mode = CGDisplayCopyDisplayMode(CGMainDisplayID())
                if let m = mode {
                    info["displayMode_pointsWidth"] = m.width        // 逻辑点
                    info["displayMode_pixelWidth"] = m.pixelWidth    // 原生像素
                    info["displayMode_ratio_pixelOverPoint"] = m.width > 0 ? Double(m.pixelWidth) / Double(m.width) : 0
                }
                let data = (try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
                sendJSON(conn, data)
            }
        case ("GET", "/preview"):
            DispatchQueue.main.sync {
                let item = CompositionBuilder.build(document: store.document)
                let durationSec = item.map { CMTimeGetSeconds($0.asset.duration) } ?? 0
                let info: [String: Any] = [
                    "hasItem": item != nil,
                    "durationSeconds": durationSec.isFinite ? durationSec : 0,
                    "spineClips": store.document.sequence.spine.filter { if case .clip = $0 { return true }; return false }.count
                ]
                let data = (try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys])) ?? Data("{}".utf8)
                sendJSON(conn, data)
            }
        case ("GET", "/agent"):
            DispatchQueue.main.sync {
                let msgs = store.agentMessages.map { m -> [String: Any] in
                    ["role": m.role.rawValue, "text": m.text, "tool": m.toolName ?? ""]
                }
                let info: [String: Any] = ["busy": store.agentBusy, "messages": msgs]
                let data = (try? JSONSerialization.data(withJSONObject: info)) ?? Data("{}".utf8)
                sendJSON(conn, data)
            }
        case ("GET", "/previewFrame"):
            DispatchQueue.main.sync {
                guard let item = CompositionBuilder.build(document: store.document) else {
                    sendText(conn, status: "500", "no item"); return
                }
                let gen = AVAssetImageGenerator(asset: item.asset)
                gen.appliesPreferredTrackTransform = true
                if let vc = item.videoComposition { gen.videoComposition = vc }
                gen.requestedTimeToleranceBefore = .zero
                gen.requestedTimeToleranceAfter = .zero
                let t = CMTime(seconds: max(0, store.ui.playhead.seconds), preferredTimescale: 600)
                if let cg = try? gen.copyCGImage(at: t, actualTime: nil) {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    if let png = rep.representation(using: .png, properties: [:]) { sendPNG(conn, png); return }
                }
                sendText(conn, status: "500", "no frame")
            }
        case ("GET", "/waveformPeaks"):
            DispatchQueue.main.sync {
                // 每个有音频的资源:波形是否就绪 + 非零桶占比 + 跨整段的 20 点预览(验证不是只填开头)
                var out: [[String: Any]] = []
                for asset in store.document.assetLibrary where asset.hasAudio {
                    if let peaks = TimelineMediaCache.shared.waveform(for: asset) {
                        let nz = peaks.filter { $0 > 0.001 }.count
                        let mx = peaks.max() ?? 0
                        var preview: [Double] = []
                        let pts = 20
                        for i in 0..<pts { preview.append(Double(peaks[min(peaks.count - 1, i * peaks.count / pts)])) }
                        out.append(["name": asset.url.lastPathComponent, "ready": true,
                                    "count": peaks.count, "nonZero": nz, "max": Double(mx),
                                    "preview": preview])
                    } else {
                        out.append(["name": asset.url.lastPathComponent, "ready": false])
                    }
                }
                let data = (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data("[]".utf8)
                sendJSON(conn, data)
            }
        default:
            sendText(conn, status: "404 Not Found", "unknown route \(pathOnly)")
        }
    }

    // MARK: - 命令执行(主线程)

    private struct Cmd: Decodable {
        let op: String
        var path: String?
        var seconds: Double?
        var px: Double?
        var index: Int?
        var at: Int?
        var lane: Int?
        var tool: String?
        var panel: String?
        var width: Double?
        var fromX: Double?; var fromY: Double?; var toX: Double?; var toY: Double?
    }

    private func execute(body: Data) {
        guard let cmd = try? JSONDecoder().decode(Cmd.self, from: body) else {
            NSLog("[DebugControlServer] bad cmd json"); return
        }
        switch cmd.op {
        case "importFile":
            if let p = cmd.path {
                do { store.dispatch(.importAsset(try MediaImporter.importAsset(from: URL(fileURLWithPath: p)))) }
                catch { NSLog("[cmd importFile] \(error)") }
            }
        case "insertAsset":
            let i = cmd.index ?? 0
            if store.document.assetLibrary.indices.contains(i) {
                let a = store.document.assetLibrary[i]
                let clip = Clip(assetID: a.id, sourceIn: .zero, duration: a.duration)
                store.dispatch(.insertClip(clip, at: cmd.at ?? store.document.sequence.spine.count))
            }
        case "setPlayhead": store.dispatch(.setPlayhead(.seconds(cmd.seconds ?? 0)))
        case "setZoom":     store.dispatch(.setZoom(cmd.px ?? 60))
        case "setTool":     if let t = cmd.tool, let tool = EditTool(rawValue: t) { store.dispatch(.setTool(tool)) }
        case "togglePlay":  store.dispatch(.togglePlay)
        case "toggleSnapping": store.dispatch(.toggleSnapping)
        case "undo": store.undo()
        case "redo": store.redo()
        case "createProject":
            // 自测:建项目(width/height/seconds=fps)。
            let w = Int(cmd.width ?? 1920), h = Int(cmd.seconds ?? 1080)
            store.dispatch(.createProject(Project(name: cmd.path ?? "测试项目",
                formatWidth: w, formatHeight: h, frameRate: 25)))
        case "agentSend":
            // 端到端:走【真实输入框路径】—— 注入输入框文字 + 调和 UI 按钮同一个 send。
            store.ui.agentInput = cmd.path ?? ""
            store.sendAgentMessage()
        case "agentStop":
            store.stopAgent()
        case "resetSelectedTransform":
            store.updateSelectedAdjust { $0.transform = Transform() }
        case "setInspector": store.dispatch(.setInspector((cmd.width ?? 1) > 0))
        case "setShowEffects": store.dispatch(.setShowEffects((cmd.width ?? 1) > 0))
        case "setAssetStripZoom": store.dispatch(.setAssetStripZoom(cmd.width ?? 6))
        case "setSkim":
            // index<0 或缺省 → 清除;否则对素材库第 index 个素材 skim 到 seconds。
            let i = cmd.index ?? -1
            if i >= 0, store.document.assetLibrary.indices.contains(i) {
                store.setSkim(store.document.assetLibrary[i].id, seconds: cmd.seconds ?? 0)
            } else { store.setSkim(nil, seconds: 0) }
        case "setSpineAdjust":
            // 自测inspector→预览: 给spine clip[index]设opacity(width字段)/scale(seconds字段)
            if let id = spineClipID(at: cmd.index ?? 0) {
                var adj = Adjustments()
                if let o = cmd.width { adj.opacity = o }
                if let sc = cmd.seconds { adj.transform.scale = CGSize(width: sc, height: sc) }
                store.dispatch(.setAdjust(id, adj))
            }
        case "scaleFirstConnected":
            // DEBUG 自测用:把第一个连接片段缩放,验证层级(缩小后能看见下层)
            let sc = CGFloat(cmd.width ?? 0.5)
            var seq = store.document.sequence
            for (i, el) in seq.spine.enumerated() {
                if case .clip(var host) = el, !host.connected.isEmpty {
                    host.connected[0].adjust.transform.scale = CGSize(width: sc, height: sc)
                    seq.spine[i] = .clip(host)
                    store.document.sequence = seq
                    break
                }
            }
        case "mouseDrag":
            // 合成鼠标拖拽(画布坐标 px):down(from)→drag(to)→up(to),驱动真实工具交互
            if let tc = findTimelineContentView() {
                synthDrag(on: tc,
                          from: NSPoint(x: cmd.fromX ?? 0, y: cmd.fromY ?? 0),
                          to: NSPoint(x: cmd.toX ?? 0, y: cmd.toY ?? 0))
            }
        case "mouseDragNoUp":
            // 只 down+drag 不 up:验证 bug4 拖动中实时(松手前 spine 已变)
            if let tc = findTimelineContentView() {
                synthDrag(on: tc,
                          from: NSPoint(x: cmd.fromX ?? 0, y: cmd.fromY ?? 0),
                          to: NSPoint(x: cmd.toX ?? 0, y: cmd.toY ?? 0), withUp: false)
            }
        case "setPanelWidth":
            if let p = cmd.panel, let kind = PanelKind(rawValue: p) {
                store.dispatch(.setPanelWidth(kind, cmd.width ?? 300))
            }
        case "blade":       store.dispatch(.setPlayhead(.seconds(cmd.seconds ?? 0))); store.bladeAtPlayhead()
        case "deleteSelected": store.deleteSelected()
        case "selectSpineClip":
            if let id = spineClipID(at: cmd.index ?? 0) { store.dispatch(.selectClip(id)) }
        case "relocateSpineClip":
            if let id = spineClipID(at: cmd.index ?? 0) {
                store.dispatch(.relocateClip(id, lane: cmd.lane ?? 0, time: .seconds(cmd.seconds ?? 0)))
            }
        case "positionMove":
            if let id = spineClipID(at: cmd.index ?? 0) {
                store.dispatch(.positionMove(id, time: .seconds(cmd.seconds ?? 0)))
            }
        case "dispatchAction":
            // 自测:直接执行一个 catalog 动作,不经 LLM。type 走 path 字段,参数从通用字段组装。
            if let type = cmd.path {
                var args: [String: Any] = ["type": type]
                if let i = cmd.index { args["clipIndex"] = i; args["assetIndex"] = i; args["spineIndex"] = i; args["fromClipIndex"] = i }
                if let s = cmd.seconds { args["atSeconds"] = s; args["seconds"] = s; args["value"] = s }
                if let l = cmd.lane { args["lane"] = l }
                if let w = cmd.width { args["value"] = w; args["pxPerSecond"] = w }
                if let action = AgentActionCatalog.find(type) { MainActor.assumeIsolated { _ = action.apply(store, args) } }
            }
        case "setGapDuration":
            store.dispatch(.setGapDuration(at: cmd.index ?? 0, duration: .seconds(cmd.seconds ?? 1)))
        case "trimClip":
            // edge 用 tool 字段传 "head"/"tail";seconds=tail新时长 或 head deltaIn;index=spine下标
            let i = cmd.index ?? -1
            if store.document.sequence.spine.indices.contains(i),
               case .clip(let c) = store.document.sequence.spine[i] {
                let assetDur = store.document.assetLibrary.first { $0.id == c.assetID }?.duration ?? c.duration
                if cmd.tool == "head" {
                    store.dispatch(.trimLeft(at: i, deltaIn: .seconds(cmd.seconds ?? 0)))
                } else {
                    store.dispatch(.trimRight(at: i, newDuration: .seconds(cmd.seconds ?? 1), assetDuration: assetDur))
                }
            }
        default: NSLog("[DebugControlServer] unknown op \(cmd.op)")
        }
    }

    private func spineClipID(at index: Int) -> ClipID? {
        var n = 0
        for el in store.document.sequence.spine {
            if case .clip(let c) = el {
                if n == index { return c.id }
                n += 1
            }
        }
        return nil
    }

    private func findTimelineContentView() -> TimelineContentView? {
        guard let root = window?.contentView else { return nil }
        var stack: [NSView] = [root]
        while let v = stack.popLast() {
            if let tc = v as? TimelineContentView { return tc }
            stack.append(contentsOf: v.subviews)
        }
        return nil
    }

    /// 合成鼠标拖拽:在画布局部坐标 from→to 触发 mouseDown/Dragged/Up,驱动真实工具交互。
    private func synthDrag(on view: TimelineContentView, from: NSPoint, to: NSPoint, withUp: Bool = true) {
        guard let win = view.window else { return }
        func ev(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent? {
            let wp = view.convert(p, to: nil)
            return NSEvent.mouseEvent(with: type, location: wp, modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: win.windowNumber, context: nil,
                                      eventNumber: 0, clickCount: 1, pressure: 1)
        }
        if let d = ev(.leftMouseDown, from) { view.mouseDown(with: d) }
        if let m = ev(.leftMouseDragged, to) { view.mouseDragged(with: m) }
        if withUp, let u = ev(.leftMouseUp, to) { view.mouseUp(with: u) }
    }

    // MARK: - 渲染

    private func snapshotJSON() -> Data {
        struct Snap: Encodable { let document: Document; let ui: UIState; let agentBusy: Bool }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(Snap(document: store.document, ui: store.ui, agentBusy: store.agentBusy))) ?? Data("{}".utf8)
    }

    private func screenshotPNG() -> Data? {
        guard let view = window?.contentView else { return nil }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - HTTP 响应

    private func sendJSON(_ conn: NWConnection, _ data: Data) {
        send(conn, status: "200 OK", contentType: "application/json", body: data)
    }
    private func sendPNG(_ conn: NWConnection, _ data: Data) {
        send(conn, status: "200 OK", contentType: "image/png", body: data)
    }
    private func sendText(_ conn: NWConnection, status: String, _ text: String) {
        send(conn, status: status, contentType: "text/plain; charset=utf-8", body: Data(text.utf8))
    }
    private func send(_ conn: NWConnection, status: String, contentType: String, body: Data) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }
}
#endif
