// Tests/FCPXLiteTests/VideoEffectFiltersTests.swift
import XCTest
import CoreImage
@testable import FCPXLite

final class VideoEffectFiltersTests: XCTestCase {
    private let base = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
        .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))

    func testNoEffectsReturnsSameExtent() {
        let out = VideoEffectFilters.apply([], to: base)
        XCTAssertEqual(out.extent, base.extent)
    }

    func testDisabledEffectSkipped() {
        var e = Effect.make(.blur); e.params["radius"] = 8; e.enabled = false
        let out = VideoEffectFilters.apply([e], to: base)
        XCTAssertEqual(out.extent, base.extent)   // 禁用 → 不模糊,extent 不变
    }

    func testBlurChangesExtent() {
        var e = Effect.make(.blur); e.params["radius"] = 8; e.enabled = true
        let out = VideoEffectFilters.apply([e], to: base)
        // 高斯模糊会扩大 extent
        XCTAssertGreaterThan(out.extent.width, base.extent.width)
    }

    func testFadeIsAudioSoSkippedByVideoChain() {
        let out = VideoEffectFilters.apply([Effect.make(.fade)], to: base)
        XCTAssertEqual(out.extent, base.extent)   // fade 非视频 → 视频链跳过
    }

    func testColorControlsApplied() {
        var e = Effect.make(.color); e.params["brightness"] = 0.3
        let out = VideoEffectFilters.apply([e], to: base)
        // 渲染前后平均亮度应升高
        let ctx = CIContext()
        func avg(_ img: CIImage) -> CGFloat {
            let f = CIFilter(name: "CIAreaAverage")!
            f.setValue(img, forKey: kCIInputImageKey)
            f.setValue(CIVector(cgRect: CGRect(x: 0, y: 0, width: 16, height: 16)), forKey: "inputExtent")
            var bm = [UInt8](repeating: 0, count: 4)
            ctx.render(f.outputImage!, toBitmap: &bm, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return CGFloat(bm[0])
        }
        XCTAssertGreaterThan(avg(out), avg(base))
    }
}
