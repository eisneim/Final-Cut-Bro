import Foundation
import CoreGraphics

extension AgentActionCatalog {
    // MARK: - system 域(文件读写/目录/命令)

    static let system: [AgentAction] = [
        AgentAction(type: "read_file", domain: .system,
                    doc: "读取本地文件内容(文本,前 2000 行)。返回文件文本或错误。path 必须是绝对路径。",
                    params: [ParamSpec(name: "path", kind: .string, required: true, doc: "文件绝对路径")]) { _, a in
            guard let p = strArg(a, "path") else { return "错误:缺 path" }
            let url = URL(fileURLWithPath: p)
            guard FileManager.default.fileExists(atPath: p) else { return "错误:文件不存在 \(p)" }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                if lines.count > 2000 {
                    let head = lines.prefix(2000).joined(separator: "\n")
                    return "\(head)\n…(共 \(lines.count) 行,已截断到前 2000 行)"
                }
                return text
            } catch { return "错误:读取失败 \(error.localizedDescription)" }
        },
        AgentAction(type: "write_file", domain: .system,
                    doc: "把文本写入本地文件(覆盖已有内容)。⚠️ 需要用户确认才能执行。path 必须是绝对路径。",
                    params: [ParamSpec(name: "path", kind: .string, required: true, doc: "文件绝对路径"),
                             ParamSpec(name: "content", kind: .string, required: true, doc: "要写入的文本内容")]) { store, a in
            guard let p = strArg(a, "path"), let content = strArg(a, "content") else { return "错误:缺 path 或 content" }
            let exists = FileManager.default.fileExists(atPath: p)
            let msg = exists ? "覆盖已有文件 \(p)(\(content.count) 字符)" : "创建新文件 \(p)(\(content.count) 字符)"
            // 通过 confirm 机制让用户确认;实际写入由 confirm 回调执行
            store.requestAgentConfirm(tool: "write_file", message: msg, args: a) { confirmed in
                guard confirmed else { return "用户取消了写入" }
                do {
                    try content.write(toFile: p, atomically: true, encoding: .utf8)
                    return "已写入 \(p)(\(content.count) 字符)"
                } catch { return "错误:写入失败 \(error.localizedDescription)" }
            }
            return "__PENDING_CONFIRM__"
        },
        AgentAction(type: "edit_file", domain: .system,
                    doc: "编辑本地文件:把 oldText 替换为 newText(精确匹配)。⚠️ 需要用户确认。path 必须是绝对路径。",
                    params: [ParamSpec(name: "path", kind: .string, required: true, doc: "文件绝对路径"),
                             ParamSpec(name: "oldText", kind: .string, required: true, doc: "要替换的原文"),
                             ParamSpec(name: "newText", kind: .string, required: true, doc: "替换后的新文本")]) { store, a in
            guard let p = strArg(a, "path"), let old = strArg(a, "oldText"), let new = strArg(a, "newText") else {
                return "错误:缺参数"
            }
            guard FileManager.default.fileExists(atPath: p) else { return "错误:文件不存在 \(p)" }
            let msg = "编辑 \(URL(fileURLWithPath: p).lastPathComponent):把 \"\(old.prefix(50))\" 替换为 \"\(new.prefix(50))\""
            store.requestAgentConfirm(tool: "edit_file", message: msg, args: a) { confirmed in
                guard confirmed else { return "用户取消了编辑" }
                do {
                    var text = try String(contentsOfFile: p, encoding: .utf8)
                    guard text.contains(old) else { return "错误:文件中未找到要替换的文本" }
                    text = text.replacingOccurrences(of: old, with: new)
                    try text.write(toFile: p, atomically: true, encoding: .utf8)
                    return "已编辑 \(URL(fileURLWithPath: p).lastPathComponent)"
                } catch { return "错误:编辑失败 \(error.localizedDescription)" }
            }
            return "__PENDING_CONFIRM__"
        },
        AgentAction(type: "list_directory", domain: .system,
                    doc: "列出目录下的文件和子目录(最多 200 项)。path 省略则列出用户桌面。",
                    params: [ParamSpec(name: "path", kind: .string, required: false, doc: "目录绝对路径,省略=桌面")]) { _, a in
            let p = strArg(a, "path") ?? (NSHomeDirectory() + "/Desktop")
            let url = URL(fileURLWithPath: p)
            guard FileManager.default.fileExists(atPath: p) else { return "错误:目录不存在 \(p)" }
            do {
                let items = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
                let prefix = items.prefix(200)
                var out = "\(p)/ (\(items.count) 项)\n"
                for item in prefix {
                    let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    let size = (try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                    let tag = isDir ? "📁" : "📄"
                    let sizeStr = isDir ? "" : " \(humanSize(size))"
                    out += "  \(tag) \(item.lastPathComponent)\(sizeStr)\n"
                }
                if items.count > 200 { out += "  …(共 \(items.count) 项,已截断)" }
                return out
            } catch { return "错误:读取目录失败 \(error.localizedDescription)" }
        },
    ]

    /// shell 命令域 → 独立成 `shell` 工具(不再混在 file_ops 文件工具里)。
    static let shell: [AgentAction] = [
        AgentAction(type: "run_command", domain: .shell,
                    doc: "在本机 shell(/bin/bash -lc)执行命令,返回退出码 + stdout/stderr(前 8000 字符)。"
                       + "用途:ffprobe/ffmpeg 探测音视频与音量、python 做数据分析(如找静音区间)等。"
                       + "【素材文件的绝对路径见 query_timeline 的\"路径:\"行,直接用它,不要 find 全盘找文件】。"
                       + "⚠️ 高危命令(rm -rf/sudo/dd/mkfs/关机/管道执行远程脚本等)会弹确认卡片,用户点允许才执行;"
                       + "普通命令(python/ffmpeg/ffprobe/ls 等)直接后台执行(不冻结界面)。cwd 可选工作目录。",
                    params: [ParamSpec(name: "command", kind: .string, required: true, doc: "shell 命令"),
                             ParamSpec(name: "cwd", kind: .string, required: false, doc: "工作目录(绝对路径),省略=默认")]) { store, a in
            guard let command = strArg(a, "command"), !command.isEmpty else { return "错误:缺 command" }
            let cwd = strArg(a, "cwd")
            if isDangerousCommand(command) {
                // 高危 → 确认卡片;确认后同步执行(这类命令 rm/sudo 通常很快)
                store.requestAgentConfirm(tool: "run_command", message: "⚠️ 高危命令,确认执行?\n\(command)", args: a) { confirmed in
                    guard confirmed else { return "用户拒绝执行该命令" }
                    return runShell(command, cwd: cwd)
                }
                return "__PENDING_CONFIRM__"
            }
            // 普通命令 → 后台线程执行(ffmpeg/python 可能耗时,主线程不冻结),结果经 agentAsyncResult 回传。
            store.agentAsyncResult = nil
            DispatchQueue.global(qos: .userInitiated).async {
                let out = runShell(command, cwd: cwd)
                DispatchQueue.main.async { store.agentAsyncResult = (UUID(), out) }
            }
            return "__PENDING_ASYNC__"
        },
    ]

    /// 高危命令判定:破坏性删除 / 提权 / 磁盘 / 关机 / 管道执行远程脚本 → 需用户确认。
    /// 普通命令(python/ffmpeg/ffprobe/ls/grep…)直接放行。
    static func isDangerousCommand(_ cmd: String) -> Bool {
        let c = " " + cmd.lowercased() + " "
        let patterns = [
            "rm -rf", "rm -fr", "rm -r ", "rm -f ", " rm -r", " rm -f", "rmdir ",
            "sudo ", "dd if=", "dd of=", "mkfs", "diskutil ", ":(){",
            "shutdown", "reboot", " halt ", "killall", "pkill ", "launchctl ",
            "chmod -r", "chown -r", "chmod 777", "| sh", "|sh", "| bash", "|bash",
            "> /dev", "mv /", "> /etc", "> /usr", "> /bin", "> /system", "> /library",
        ]
        return patterns.contains { c.contains($0) }
    }

    /// 同步执行 shell 命令(应在后台线程调用),返回 "退出码 N\n<输出>"(截断 8000 字符,120s 超时)。
    static func runShell(_ command: String, cwd: String?) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-lc", command]   // 登录 shell:带上用户 PATH(conda/ffmpeg/python)
        if let cwd, FileManager.default.fileExists(atPath: cwd) {
            proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        // stdin 接 /dev/null:交互式命令(如 ffmpeg 不带 -y 问"是否覆盖? [y/N]")拿到 EOF 立即退出,
        // 不再永久等 stdin 卡死(这是"命令一跑就该结束、却傻等"的真正根因)。
        proc.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch { return "错误:无法执行(\(error.localizedDescription)):\(command)" }
        // 120s 超时:后台读输出,超时则终止。
        let sem = DispatchSemaphore(value: 0)
        var data = Data()
        DispatchQueue.global().async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            sem.signal()
        }
        if sem.wait(timeout: .now() + 120) == .timedOut {
            proc.terminate()
            return "错误:命令超时(120s)已终止,可能是命令本身会一直运行或在等待输入:\(command)"
        }
        proc.waitUntilExit()
        var out = String(data: data, encoding: .utf8) ?? ""
        if out.count > 8000 { out = String(out.prefix(8000)) + "\n…(输出已截断到 8000 字符)" }
        let status = proc.terminationStatus
        let tag = status == 0 ? "✅ 退出码 0" : "⚠️ 退出码 \(status)(非 0 = 命令失败)"
        return "\(tag)\n" + (out.isEmpty ? "(无输出)" : out)
    }

    /// 人类可读的文件大小。
    private static func humanSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return String(format: "%.1fKB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1fMB", Double(bytes) / 1024 / 1024) }
        return String(format: "%.1fGB", Double(bytes) / 1024 / 1024 / 1024)
    }
}
