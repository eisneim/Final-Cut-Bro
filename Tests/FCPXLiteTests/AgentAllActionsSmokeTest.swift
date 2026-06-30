import XCTest
import CoreGraphics
@testable import FCPXLite

/// 自检:遍历【全部】catalog 动作,每个用合法参数调用一次,断言不返回"错误"(执行层全打通)。
/// 等于回答"哪些能力 agent 不能调用 + 都测一遍"。需真实文件的(import/export_movie 渲染)单独说明。
@MainActor
final class AgentAllActionsSmokeTest: XCTestCase {

    private func vAsset(_ dur: Double = 10) -> Asset {
        Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v\(UUID().uuidString).mov"), kind: .video,
              duration: .seconds(dur), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
    }
    /// 含项目 + 3 个素材(2视频1音频)的 store;spine 预放 3 个视频 clip。
    private func base() -> DocumentStore {
        let a0 = vAsset(), a1 = vAsset(), a2 = vAsset()
        let mk = { (a: Asset) in Clip(assetID: a.id, sourceIn: .zero, duration: .seconds(5)) }
        let doc = Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                           assetLibrary: [a0, a1, a2],
                           sequence: Sequence(spine: [.clip(mk(a0)), .clip(mk(a1)), .clip(mk(a2))]))
        return DocumentStore(document: doc)
    }
    private func run(_ s: DocumentStore, _ type: String, _ args: [String: Any]) -> String {
        guard let action = AgentActionCatalog.find(type) else { return "未注册:\(type)" }
        return action.apply(s, args.merging(["type": type]) { x, _ in x })
    }
    private func ok(_ s: DocumentStore, _ type: String, _ args: [String: Any], _ file: StaticString = #filePath, _ line: UInt = #line) {
        let r = run(s, type, args)
        XCTAssertFalse(r.contains("错误") || r.contains("未注册"), "[\(type)] 失败: \(r)", file: file, line: line)
    }

    // MARK: - timeline 域

    func testTimelineActions() {
        var s = base(); ok(s, "insert", ["assetIndex": 0, "atSeconds": 2])
        s = base(); ok(s, "append", ["assetIndex": 1])
        s = base(); ok(s, "connect", ["assetIndex": 1, "atSeconds": 1, "lane": 1])
        s = base(); ok(s, "delete", ["clipIndex": 0])
        s = base(); ok(s, "move", ["fromClipIndex": 0, "toClipIndex": 2])
        s = base(); ok(s, "blade", ["clipIndex": 0, "atSeconds": 2])
        s = base(); ok(s, "trim", ["clipIndex": 0, "edge": "tail", "seconds": 3])
        s = base(); ok(s, "trim", ["clipIndex": 0, "edge": "head", "seconds": 1])
        s = base(); ok(s, "position_move", ["clipIndex": 0, "atSeconds": 20])
        s = base(); ok(s, "duplicate_clip", ["clipIndex": 0])
        s = base(); ok(s, "duplicate_clip", ["clipIndex": 0, "atSeconds": 10])
        s = base(); ok(s, "slip", ["clipIndex": 0, "deltaSeconds": 1])
        s = base(); ok(s, "slide", ["clipIndex": 1, "deltaSeconds": 1])
        s = base(); ok(s, "add_transition", ["clipIndex": 1, "seconds": 1])
        s = base(); ok(s, "add_title", ["text": "标题", "fontSize": 80, "colorHex": "#FFCC00", "y": 300])
        s = base(); ok(s, "append_clip", ["assetIndex": 0, "fromSeconds": 2, "toSeconds": 6])
        s = base(); ok(s, "overwrite", ["assetIndex": 0, "atSeconds": 2])
        s = base(); ok(s, "move_to_lane", ["clipIndex": 1, "lane": 1, "atSeconds": 3])
        // set_gap / remove_gap:先 position_move 制造间隙
        s = base()
        _ = run(s, "position_move", ["clipIndex": 0, "atSeconds": 20])
        var gapIdx = -1
        for (i, el) in s.document.sequence.spine.enumerated() { if case .gap = el { gapIdx = i; break } }
        if gapIdx >= 0 {
            ok(s, "set_gap", ["spineIndex": gapIdx, "seconds": 3])
            ok(s, "remove_gap", ["spineIndex": gapIdx])
        } else { XCTFail("position_move 未产生 gap") }
    }

    // MARK: - adjust 域

    func testAdjustActions() {
        let s = base()
        ok(s, "scale", ["clipIndex": 0, "value": 2])
        ok(s, "position", ["clipIndex": 0, "x": 50, "y": 10])
        ok(s, "crop", ["clipIndex": 0, "left": 0.1, "right": 0.1])
        ok(s, "opacity", ["clipIndex": 0, "value": 0.5])
        ok(s, "volume", ["clipIndex": 0, "value": 0.3])
        ok(s, "add_effect", ["clipIndex": 0, "kind": "blur"])
        ok(s, "set_effect_param", ["clipIndex": 0, "effectIndex": 0, "key": "radius", "value": 8])
        ok(s, "remove_effect", ["clipIndex": 0, "effectIndex": 0])
        ok(s, "toggle_enabled", ["clipIndex": 0, "enabled": false])
        ok(s, "add_transform_keyframe", ["clipIndex": 0, "atSeconds": 1, "scale": 1.5])
        ok(s, "clear_transform_keyframes", ["clipIndex": 0])
        ok(s, "add_volume_keyframe", ["clipIndex": 0, "atSeconds": 1, "value": 0.5])
        ok(s, "rotate", ["clipIndex": 0, "degrees": 30])
        // set_title:先加一个标题再编辑它
        _ = run(s, "add_title", ["text": "原文字"])
        ok(s, "set_title", ["titleIndex": 0, "text": "新文字", "fontSize": 72, "colorHex": "#00FF00", "bold": "false", "align": 0, "x": 10, "y": 200])
    }

    // MARK: - navigate 域

    func testNavigateActions() throws {
        let s = base()
        ok(s, "playhead", ["atSeconds": 3])
        ok(s, "zoom", ["pxPerSecond": 120])
        ok(s, "tool", ["name": "blade"])
        ok(s, "select", ["clipIndex": 0])
        ok(s, "select_asset", ["assetIndex": 0])
        _ = run(s, "scale", ["clipIndex": 0, "value": 2])   // 制造一步可撤销
        ok(s, "undo", [:])
        ok(s, "redo", [:])
        ok(s, "create_project", ["name": "新项目", "width": 1080, "height": 1920, "fps": 30])
        ok(s, "rename_project", ["name": "改名了"])
        ok(s, "select_project", ["index": 0])
        ok(s, "remove_project", ["index": 1])
        ok(s, "toggle_snapping", [:])
        ok(s, "export_fcpxml", ["path": NSTemporaryDirectory() + "smoke.fcpxml"])
        ok(s, "export_movie", ["path": NSTemporaryDirectory() + "smoke.mp4"])   // 异步,返回"已开始"即算可调
        // import:用真实文件(本机有则测,无则跳过——执行层已在 T7 live 验证)
        let real = "/Users/teli/Downloads/tstvideo_副本.mp4"
        if FileManager.default.fileExists(atPath: real) { ok(s, "import", ["path": real]) }
        else { throw XCTSkip("import 需真实文件,本机缺失;T7 已 live 验证") }
    }

    /// 覆盖完整性:catalog 里每个动作要么在上面三组测过,要么显式列在"已知未测"白名单。
    func testEveryActionIsCovered() {
        let tested: Set<String> = [
            "insert","append","connect","delete","move","blade","trim","position_move","duplicate_clip",
            "slip","slide","add_transition","add_title","overwrite","set_gap","move_to_lane","remove_gap","append_clip",
            "scale","position","crop","opacity","volume","add_effect","set_effect_param","remove_effect",
            "toggle_enabled","add_transform_keyframe","clear_transform_keyframes","add_volume_keyframe",
            "rotate","set_title",
            "playhead","zoom","tool","select","select_asset","undo","redo","create_project","toggle_snapping",
            "rename_project","select_project","remove_project",
            "export_fcpxml","export_movie","import",
        ]
        let all = Set(AgentActionCatalog.all.map { $0.type })
        let missing = all.subtracting(tested)
        XCTAssertTrue(missing.isEmpty, "有 catalog 动作未被冒烟测试覆盖: \(missing.sorted())")
    }
}
