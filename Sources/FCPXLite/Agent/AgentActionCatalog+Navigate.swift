import Foundation
import CoreGraphics

extension AgentActionCatalog {
    static let navigate: [AgentAction] = [
        AgentAction(type: "playhead", domain: .navigate, doc: "把播放头移到 atSeconds 秒。",
                    params: [ParamSpec(name: "atSeconds", kind: .number, required: true, doc: "时间(秒)")]) { store, a in
            store.dispatch(.setPlayhead(.seconds(numArg(a, "atSeconds") ?? 0))); return "播放头到 \(numArg(a, "atSeconds") ?? 0)s"
        },
        AgentAction(type: "zoom", domain: .navigate, doc: "设置时间线缩放 pxPerSecond(像素/秒)。",
                    params: [ParamSpec(name: "pxPerSecond", kind: .number, required: true, doc: "每秒像素数")]) { store, a in
            store.dispatch(.setZoom(numArg(a, "pxPerSecond") ?? 60)); return "缩放设为 \(numArg(a, "pxPerSecond") ?? 60)"
        },
        AgentAction(type: "tool", domain: .navigate, doc: "切换编辑工具:select/trim/position/range/blade/zoom/hand。",
                    params: [ParamSpec(name: "name", kind: .enumString(["select","trim","position","range","blade","zoom","hand"]), required: true, doc: "工具名")]) { store, a in
            guard let t = strArg(a, "name").flatMap({ EditTool(rawValue: $0) }) else { return "错误:未知工具" }
            store.dispatch(.setTool(t)); return "工具切到 \(t.rawValue)"
        },
        AgentAction(type: "select", domain: .navigate, doc: "选中主轴第 clipIndex 个片段(供 inspector 编辑)。",
                    params: [ParamSpec(name: "clipIndex", kind: .int, required: true, doc: "片段索引")]) { store, a in
            guard let id = clipID(store, intArg(a, "clipIndex") ?? -1) else { return "错误:clipIndex 无效" }
            store.dispatch(.selectClip(id)); return "已选中片段 \(intArg(a, "clipIndex")!)"
        },
        AgentAction(type: "select_asset", domain: .navigate, doc: "选中素材库第 assetIndex 个素材。",
                    params: [ParamSpec(name: "assetIndex", kind: .int, required: true, doc: "素材库索引")]) { store, a in
            let i = intArg(a, "assetIndex") ?? -1
            guard store.document.assetLibrary.indices.contains(i) else { return "错误:assetIndex 无效" }
            store.dispatch(.selectAsset(store.document.assetLibrary[i].id)); return "已选中素材 \(i)"
        },
        AgentAction(type: "list_assets", domain: .navigate,
                    doc: "列出素材库里所有素材及其【索引】(0基)、文件名、类型、时长、分辨率、帧率。多素材/多镜头剪辑前【先调这个】看清哪个文件对应哪个 assetIndex,再把 build_subtitle_cut 每段的 assetIndex 填对。",
                    params: []) { store, _ in
            let lib = store.document.assetLibrary
            guard !lib.isEmpty else { return "素材库为空(先 import)" }
            let lines = lib.enumerated().map { (i, asset) -> String in
                let w = Int(asset.naturalSize.width), h = Int(asset.naturalSize.height)
                let fps = asset.frameRate.map { String(format: "%.3g", $0) } ?? "?"
                return "[\(i)] \(asset.url.lastPathComponent) · \(asset.kind.rawValue) · \(String(format: "%.2f", asset.duration.seconds))s · \(w)×\(h) · \(fps)fps"
            }
            return "素材库(\(lib.count) 个):\n" + lines.joined(separator: "\n")
        },
        AgentAction(type: "undo", domain: .navigate, doc: "撤销上一次编辑。", params: []) { store, _ in store.undo(); return "已撤销" },
        AgentAction(type: "redo", domain: .navigate, doc: "重做。", params: []) { store, _ in store.redo(); return "已重做" },
        AgentAction(type: "import", domain: .navigate, doc: "从磁盘绝对路径导入媒体(视频/音乐)到素材库。返回它分配到的素材索引 assetIndex。",
                    params: [ParamSpec(name: "path", kind: .string, required: true, doc: "媒体文件绝对路径")]) { store, a in
            guard let p = strArg(a, "path") else { return "错误:缺 path" }
            do {
                let asset = try MediaImporter.importAsset(from: URL(fileURLWithPath: p))
                store.dispatch(.importAsset(asset))
                let idx = store.document.assetLibrary.firstIndex(where: { $0.id == asset.id }) ?? (store.document.assetLibrary.count - 1)
                return "已导入 \(URL(fileURLWithPath: p).lastPathComponent) → 素材[\(idx)]"
            }
            catch { return "错误:导入失败 \(error)" }
        },
        AgentAction(type: "export_fcpxml", domain: .navigate, doc: "把当前剪辑导出为 .fcpxml 工程文件到磁盘绝对路径(可回真 FCP 继续剪)。",
                    params: [ParamSpec(name: "path", kind: .string, required: true, doc: "目标 .fcpxml 绝对路径")]) { store, a in
            guard let p = strArg(a, "path") else { return "错误:缺 path" }
            do { try store.exportFCPXML(to: URL(fileURLWithPath: p)); return "已导出 fcpxml 到 \(p)" }
            catch { return "错误:导出失败 \(error)" }
        },
        AgentAction(type: "export_movie", domain: .navigate, doc: "把当前剪辑渲染导出为成片(有视频→mp4,纯音频→m4a)到磁盘绝对路径。异步,返回已开始。",
                    params: [ParamSpec(name: "path", kind: .string, required: true, doc: "目标文件绝对路径")]) { store, a in
            guard let p = strArg(a, "path") else { return "错误:缺 path" }
            store.exportMovie(to: URL(fileURLWithPath: p), settings: ExportSettings()); return "已开始导出成片到 \(p)(渲染中)"
        },
        AgentAction(type: "create_project", domain: .navigate,
                    doc: "新建一个项目(对应 FCP 的 Project,自带分辨率/帧率与独立时间线),并切到它。无项目时必须先建。",
                    params: [ParamSpec(name: "name", kind: .string, required: true, doc: "项目名"),
                             ParamSpec(name: "width", kind: .int, required: false, doc: "宽,默认1920"),
                             ParamSpec(name: "height", kind: .int, required: false, doc: "高,默认1080"),
                             ParamSpec(name: "fps", kind: .number, required: false, doc: "帧率,默认25")]) { store, a in
            let p = Project(name: strArg(a, "name") ?? "项目",
                            formatWidth: intArg(a, "width") ?? 1920,
                            formatHeight: intArg(a, "height") ?? 1080,
                            frameRate: numArg(a, "fps") ?? 25)
            store.dispatch(.createProject(p))
            return "已新建项目「\(p.name)」\(p.formatWidth)×\(p.formatHeight)"
        },
        AgentAction(type: "toggle_snapping", domain: .navigate,
                    doc: "切换磁吸编辑(snapping)开/关。开时切割/修剪/平移会吸附到邻近编辑点。", params: []) { store, _ in
            store.dispatch(.toggleSnapping)
            return store.ui.snappingEnabled ? "磁吸已开" : "磁吸已关"
        },
        AgentAction(type: "rename_project", domain: .navigate,
                    doc: "重命名当前项目(或第 index 个项目)。",
                    params: [ParamSpec(name: "name", kind: .string, required: true, doc: "新名字"),
                             ParamSpec(name: "index", kind: .int, required: false, doc: "项目索引,省略=当前")]) { store, a in
            guard let name = strArg(a, "name") else { return "错误:缺 name" }
            let pid: ProjectID?
            if let i = intArg(a, "index"), store.document.projects.indices.contains(i) { pid = store.document.projects[i].id }
            else { pid = store.document.currentProjectID }
            guard let id = pid else { return "错误:没有项目" }
            store.dispatch(.renameProject(id, name))
            return "已重命名为「\(name)」"
        },
        AgentAction(type: "select_project", domain: .navigate,
                    doc: "切换到第 index 个项目(0基),换出它的时间线。",
                    params: [ParamSpec(name: "index", kind: .int, required: true, doc: "项目索引,0基")]) { store, a in
            let i = intArg(a, "index") ?? -1
            guard store.document.projects.indices.contains(i) else { return "错误:index 无效" }
            store.dispatch(.selectProject(store.document.projects[i].id))
            return "已切到项目「\(store.document.projects[i].name)」"
        },
        AgentAction(type: "remove_project", domain: .navigate,
                    doc: "删除第 index 个项目(省略=当前)。删当前会切到剩下的项目或回到无项目门控。",
                    params: [ParamSpec(name: "index", kind: .int, required: false, doc: "项目索引,省略=当前")]) { store, a in
            let pid: ProjectID?
            if let i = intArg(a, "index"), store.document.projects.indices.contains(i) { pid = store.document.projects[i].id }
            else { pid = store.document.currentProjectID }
            guard let id = pid else { return "错误:没有项目" }
            store.dispatch(.removeProject(id))
            return "已删除项目"
        },
    ]
}
