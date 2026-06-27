#if DEBUG
import Foundation
import Network
import AppKit

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
        case "blade":       store.dispatch(.setPlayhead(.seconds(cmd.seconds ?? 0))); store.bladeAtPlayhead()
        case "deleteSelected": store.deleteSelected()
        case "selectSpineClip":
            if let id = spineClipID(at: cmd.index ?? 0) { store.dispatch(.selectClip(id)) }
        case "relocateSpineClip":
            if let id = spineClipID(at: cmd.index ?? 0) {
                store.dispatch(.relocateClip(id, lane: cmd.lane ?? 0, time: .seconds(cmd.seconds ?? 0)))
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

    // MARK: - 渲染

    private func snapshotJSON() -> Data {
        struct Snap: Encodable { let document: Document; let ui: UIState }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(Snap(document: store.document, ui: store.ui))) ?? Data("{}".utf8)
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
