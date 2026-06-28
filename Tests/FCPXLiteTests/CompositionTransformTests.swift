import XCTest
import CoreGraphics
@testable import FCPXLite

/// 验证 CompositionBuilder.fullTransform 的几何:占满画布 + 归一化叠加层 + 真实裁剪。
/// 纯数学,无需 AVFoundation / 媒体文件 / 运行 app —— 数据驱动对照,杜绝肉眼猜测。
final class CompositionTransformTests: XCTestCase {
    private let render = CGSize(width: 1920, height: 1080)
    private let identity = CGAffineTransform.identity

    /// 把源像素点经变换映射到渲染坐标。
    private func map(_ p: CGPoint, _ t: CGAffineTransform) -> CGPoint { p.applying(t) }
    private func onCanvas(_ p: CGPoint) -> Bool {
        p.x >= -0.5 && p.x <= render.width + 0.5 && p.y >= -0.5 && p.y <= render.height + 0.5
    }

    // 同尺寸素材、无调整 → 正好铺满(四角映射到画布四角)。
    func testFullFrameFillsExactly() {
        let t = CompositionBuilder.fullTransform(adjust: Adjustments(), natural: render, pref: identity, renderSize: render)
        XCTAssertEqual(map(CGPoint(x: 0, y: 0), t).x, 0, accuracy: 0.5)
        XCTAssertEqual(map(CGPoint(x: 1920, y: 1080), t).x, 1920, accuracy: 0.5)
        XCTAssertEqual(map(CGPoint(x: 1920, y: 1080), t).y, 1080, accuracy: 0.5)
    }

    // 小分辨率叠加层(1280×720)→ 等比放大到铺满 1920×1080(修复"叠加层显小")。
    func testSmallOverlayNormalizedToFill() {
        let small = CGSize(width: 1280, height: 720)
        let t = CompositionBuilder.fullTransform(adjust: Adjustments(), natural: small, pref: identity, renderSize: render)
        // 源右下角 (1280,720) 应映射到画布右下角 (1920,1080)。
        let br = map(CGPoint(x: 1280, y: 720), t)
        XCTAssertEqual(br.x, 1920, accuracy: 0.5)
        XCTAssertEqual(br.y, 1080, accuracy: 0.5)
    }

    // 左裁 15% → 被裁的左边缘必须溢出画布(x<0),保留区铺满画布宽度。
    // 裁剪改为合成器里的矩形修剪(trim),不再影响 fullTransform 几何:加 crop 后矩阵不变。
    func testCropDoesNotAffectFullTransform() {
        var cropped = Adjustments()
        cropped.crop.left = 0.15 * 1920
        cropped.crop.top = 100
        let tNoCrop = CompositionBuilder.fullTransform(adjust: Adjustments(), natural: render, pref: identity, renderSize: render)
        let tCrop = CompositionBuilder.fullTransform(adjust: cropped, natural: render, pref: identity, renderSize: render)
        // crop 不进几何 → 两个矩阵相同(全帧 aspect-fit 不变)。
        XCTAssertEqual(tCrop.a, tNoCrop.a, accuracy: 1e-6)
        XCTAssertEqual(tCrop.d, tNoCrop.d, accuracy: 1e-6)
        XCTAssertEqual(tCrop.tx, tNoCrop.tx, accuracy: 1e-6)
        XCTAssertEqual(tCrop.ty, tNoCrop.ty, accuracy: 1e-6)
    }

    // 放大 2 倍:源中心仍在画布中心,四角向外扩(中心不动的缩放)。
    func testScale2xKeepsCenter() {
        var adj = Adjustments()
        adj.transform.scale = CGSize(width: 2, height: 2)
        let t = CompositionBuilder.fullTransform(adjust: adj, natural: render, pref: identity, renderSize: render)
        let center = map(CGPoint(x: 960, y: 540), t)
        XCTAssertEqual(center.x, 960, accuracy: 0.5)
        XCTAssertEqual(center.y, 540, accuracy: 0.5)
        // 左上角源点 (0,0) 放大 2 倍后应在画布外左上 (-960,-540)。
        let tl = map(CGPoint(x: 0, y: 0), t)
        XCTAssertEqual(tl.x, -960, accuracy: 0.5)
        XCTAssertEqual(tl.y, -540, accuracy: 0.5)
    }
}
