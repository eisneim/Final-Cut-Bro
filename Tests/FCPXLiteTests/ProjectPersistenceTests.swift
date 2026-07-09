import XCTest
import CoreGraphics
@testable import FCPXLite

/// 项目持久化:整个 Document 存成 .fcbro(JSON)再读回,素材/时间轴/效果/字幕/关键帧完全还原。
@MainActor
final class ProjectPersistenceTests: XCTestCase {

    /// 构造一个"内容丰富"的文档:2 素材、2 项目,含特效/调色/字幕/音量关键帧/连接片段。
    private func richDocument() -> Document {
        let a0 = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/v0.mov"), kind: .video,
                       duration: .seconds(40), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
        let a1 = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/music.m4a"), kind: .audio,
                       duration: .seconds(60), naturalSize: .zero, frameRate: nil, hasAudio: true)

        var blur = Effect.make(.blur); blur.params["radius"] = 12
        var adj = Adjustments(); adj.opacity = 0.7; adj.transform.scale = CGSize(width: 1.5, height: 1.5); adj.volume = 0.8
        var titleSpec = TitleSpec(text: "字幕一", fontSize: 56, colorHex: "#FFEE00")
        titleSpec.position = CGPoint(x: 0, y: 380)
        let title = Clip(assetID: AssetID(), sourceIn: .zero, duration: .seconds(3),
                         lane: 1, offset: .seconds(1), title: titleSpec)
        let video = Clip(assetID: a0.id, sourceIn: .seconds(2), duration: .seconds(10),
                         connected: [title], adjust: adj, effects: [blur],
                         volumeKeyframes: [VolumeKeyframe(time: .seconds(1), value: 0.3)])
        let p0 = Project(name: "主项目", formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                         sequence: Sequence(spine: [.clip(video)]))
        let p1 = Project(name: "竖屏项目", formatWidth: 1080, formatHeight: 1920, frameRate: 30,
                         sequence: Sequence(spine: [.gap(duration: .seconds(2))]))
        return Document(assetLibrary: [a0, a1], projects: [p0, p1], currentProjectID: p1.id)
    }

    /// 编码→解码 完全相等(含特效/调色/字幕/关键帧/多项目/当前项目)。
    func testRoundTripPreservesEverything() throws {
        let doc = richDocument()
        let data = try ProjectPersistence.encode(doc)
        let back = try ProjectPersistence.decode(data)
        XCTAssertEqual(back, doc, "解码后的文档应与原文档完全一致")
    }

    /// 文件带版本号(便于将来迁移)。
    func testFileHasVersion() throws {
        let data = try ProjectPersistence.encode(richDocument())
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["version"] as? Int, ProjectPersistence.currentVersion)
        XCTAssertNotNil(obj?["document"], "应有 document 字段")
    }

    /// 存到磁盘再从磁盘读回,内容一致。
    func testSaveLoadFileOnDisk() throws {
        let doc = richDocument()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("persist_\(UUID().uuidString).\(ProjectPersistence.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        try ProjectPersistence.save(doc, to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try ProjectPersistence.load(from: url), doc)
    }

    /// store.openProject:整体替换文档、复位播放头与选择、清空撤销栈。
    func testOpenProjectResetsUIAndLoads() throws {
        let doc = richDocument()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("persist_\(UUID().uuidString).\(ProjectPersistence.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        try ProjectPersistence.save(doc, to: url)

        // 一个"脏"store:播放头非零、有选择、有撤销历史
        let store = DocumentStore(document: Document(formatWidth: 1280, formatHeight: 720, frameRate: 25,
                                                     assetLibrary: [], sequence: Sequence(spine: [])))
        store.ui.playhead = .seconds(9)
        store.ui.selectedClipID = ClipID()
        store.ui.selectedAssetIDs = [AssetID()]

        try store.openProject(from: url)

        XCTAssertEqual(store.document, doc, "文档应被打开的项目整体替换")
        XCTAssertEqual(store.ui.playhead, .zero, "播放头应复位")
        XCTAssertNil(store.ui.selectedClipID, "选择应清空")
        XCTAssertTrue(store.ui.selectedAssetIDs.isEmpty)
        XCTAssertFalse(store.canUndo, "打开新项目后不应有可撤销历史")
    }

    /// 素材缺失(源文件不存在)也能加载 —— 元数据都在文档里,时间轴照常还原。
    func testLoadsEvenIfMediaMissing() throws {
        let doc = richDocument()   // 引用的是 /tmp 下不存在的假路径
        let back = try ProjectPersistence.decode(try ProjectPersistence.encode(doc))
        XCTAssertEqual(back.assetLibrary.count, 2)
        XCTAssertEqual(back.currentProject?.name, "竖屏项目")
    }
}
