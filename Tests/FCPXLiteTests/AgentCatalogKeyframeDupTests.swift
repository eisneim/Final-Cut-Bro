import XCTest
import CoreGraphics
@testable import FCPXLite

/// 新接入 catalog 的动作:duplicate_clip / add_transform_keyframe / clear_transform_keyframes。
@MainActor
final class AgentCatalogKeyframeDupTests: XCTestCase {
    private func storeWith2Assets() -> DocumentStore {
        let a0 = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/a.mov"), kind: .video,
                       duration: .seconds(10), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
        let a1 = Asset(id: AssetID(), url: URL(fileURLWithPath: "/tmp/b.mov"), kind: .video,
                       duration: .seconds(8), naturalSize: CGSize(width: 1920, height: 1080), frameRate: 25, hasAudio: true)
        return DocumentStore(document: Document(formatWidth: 1920, formatHeight: 1080, frameRate: 25,
                                                assetLibrary: [a0, a1], sequence: Sequence(spine: [])))
    }
    private func clipCount(_ s: DocumentStore) -> Int {
        s.document.sequence.spine.reduce(0) { if case .clip = $1 { return $0 + 1 }; return $0 }
    }
    private func clipAt(_ s: DocumentStore, _ i: Int) -> Clip? {
        var n = 0
        for el in s.document.sequence.spine { if case .clip(let c) = el { if n == i { return c }; n += 1 } }
        return nil
    }

    // MARK: - 新动作已注册

    func testNewActionsRegisteredInRightDomains() {
        XCTAssertEqual(AgentActionCatalog.find("duplicate_clip")?.domain, .timeline)
        XCTAssertEqual(AgentActionCatalog.find("add_transform_keyframe")?.domain, .adjust)
        XCTAssertEqual(AgentActionCatalog.find("clear_transform_keyframes")?.domain, .adjust)
    }

    // MARK: - duplicate_clip

    func testDuplicateClipAppendsWhenNoTime() {
        let s = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(s, ["assetIndex": 0])
        _ = AgentActionCatalog.find("duplicate_clip")!.apply(s, ["clipIndex": 0])
        XCTAssertEqual(clipCount(s), 2, "复制末尾追加")
        // 新片段 id 不同,时长一致
        XCTAssertNotEqual(clipAt(s, 0)?.id, clipAt(s, 1)?.id)
        XCTAssertEqual(clipAt(s, 1)?.duration.seconds ?? -1, 10, accuracy: 0.001)
    }

    func testDuplicateClipAtSecondsInsertsAtBoundary() {
        let s = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(s, ["assetIndex": 0])  // 10s
        _ = AgentActionCatalog.find("append")!.apply(s, ["assetIndex": 1])  // 8s,边界 0,10,18
        _ = AgentActionCatalog.find("duplicate_clip")!.apply(s, ["clipIndex": 1, "atSeconds": 10.0])
        XCTAssertEqual(clipCount(s), 3)
        // index1 应是粘贴的(8s,来自素材1),原素材1 clip 后移
        XCTAssertEqual(clipAt(s, 1)?.duration.seconds ?? -1, 8, accuracy: 0.001)
    }

    func testDuplicatePreservesAdjustAndKeyframes() {
        let s = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(s, ["assetIndex": 0])
        _ = AgentActionCatalog.find("scale")!.apply(s, ["clipIndex": 0, "value": 2.0])
        _ = AgentActionCatalog.find("add_transform_keyframe")!.apply(s, ["clipIndex": 0, "atSeconds": 1.0, "scale": 1.5])
        _ = AgentActionCatalog.find("duplicate_clip")!.apply(s, ["clipIndex": 0])
        let dup = clipAt(s, 1)
        XCTAssertEqual(dup?.adjust.transform.scale.width, 2.0)
        XCTAssertEqual(dup?.transformKeyframes.count, 1)
    }

    func testDuplicateBadIndexErrors() {
        let s = storeWith2Assets()
        let msg = AgentActionCatalog.find("duplicate_clip")!.apply(s, ["clipIndex": 9])
        XCTAssertTrue(msg.contains("错误"))
        XCTAssertEqual(clipCount(s), 0)
    }

    // MARK: - add_transform_keyframe

    func testAddTransformKeyframeBuildsAnimation() {
        let s = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(s, ["assetIndex": 0])
        _ = AgentActionCatalog.find("add_transform_keyframe")!.apply(s, ["clipIndex": 0, "atSeconds": 0.0, "scale": 1.0])
        _ = AgentActionCatalog.find("add_transform_keyframe")!.apply(s, ["clipIndex": 0, "atSeconds": 3.0, "scale": 2.0, "x": 50.0, "opacity": 0.5])
        let kfs = clipAt(s, 0)?.transformKeyframes ?? []
        XCTAssertEqual(kfs.count, 2)
        XCTAssertEqual(kfs[0].scale.width, 1.0, accuracy: 0.001)
        XCTAssertEqual(kfs[1].scale.width, 2.0, accuracy: 0.001)
        XCTAssertEqual(kfs[1].position.x, 50.0, accuracy: 0.001)
        XCTAssertEqual(kfs[1].opacity, 0.5, accuracy: 0.001)
    }

    func testAddTransformKeyframeSameTimeOverwrites() {
        let s = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(s, ["assetIndex": 0])
        _ = AgentActionCatalog.find("add_transform_keyframe")!.apply(s, ["clipIndex": 0, "atSeconds": 1.0, "scale": 1.0])
        _ = AgentActionCatalog.find("add_transform_keyframe")!.apply(s, ["clipIndex": 0, "atSeconds": 1.0, "scale": 3.0])
        let kfs = clipAt(s, 0)?.transformKeyframes ?? []
        XCTAssertEqual(kfs.count, 1, "同时间覆盖,不累加")
        XCTAssertEqual(kfs[0].scale.width, 3.0, accuracy: 0.001)
    }

    func testClearTransformKeyframes() {
        let s = storeWith2Assets()
        _ = AgentActionCatalog.find("append")!.apply(s, ["assetIndex": 0])
        _ = AgentActionCatalog.find("add_transform_keyframe")!.apply(s, ["clipIndex": 0, "atSeconds": 0.0])
        _ = AgentActionCatalog.find("add_transform_keyframe")!.apply(s, ["clipIndex": 0, "atSeconds": 2.0])
        XCTAssertEqual(clipAt(s, 0)?.transformKeyframes.count, 2)
        _ = AgentActionCatalog.find("clear_transform_keyframes")!.apply(s, ["clipIndex": 0])
        XCTAssertEqual(clipAt(s, 0)?.transformKeyframes.count, 0)
    }

    func testKeyframeActionBadIndexErrors() {
        let s = storeWith2Assets()
        let msg = AgentActionCatalog.find("add_transform_keyframe")!.apply(s, ["clipIndex": 5, "atSeconds": 0.0])
        XCTAssertTrue(msg.contains("错误"))
    }
}
