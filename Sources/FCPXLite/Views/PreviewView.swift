import SwiftUI
import AVFoundation
import AppKit

/// 预览区:用 AVPlayer 实时播放由文档构建的合成。
/// 序列变化 → 重建 item;播放头移动(非播放态)→ seek;isPlaying → play/pause。
/// 播放时由周期观察器把当前时间写回 store.ui.playhead,驱动时间线红线移动。
struct PreviewView: NSViewRepresentable {
    let store: DocumentStore
    let sequence: Sequence        // 变化触发重建
    let playheadSeconds: Double
    let isPlaying: Bool
    let skimming: Bool            // true=时间轴 skimming 中(playheadSeconds 实为 skimmer 时间)→ 容差 seek

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: PlayerHostView, context: Context) {
        context.coordinator.update(sequence: sequence, store: store,
                                   playheadSeconds: playheadSeconds, isPlaying: isPlaying, skimming: skimming)
    }

    static func dismantleNSView(_ nsView: PlayerHostView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator {
        let player = AVPlayer()
        private var lastSequence: Sequence?
        private var timeObserver: Any?
        private var observing = false
        private var lastFingerprint: String = ""
        private var lastPlayheadSeconds: Double = -1
        private var lastIsPlaying: Bool = false

        func attach(to view: PlayerHostView) {
            view.playerLayer.player = player
        }

        func update(sequence: Sequence, store: DocumentStore, playheadSeconds: Double, isPlaying: Bool, skimming: Bool) {
            // 先做廉价判断:播放头/播放态/序列是否变。序列比较用 Equatable(O(N)),但避免了每次都拼
            // 全 spine 指纹字符串(流式对话时每 token 都会触发 updateNSView → 否则每 token 拼一遍全 spine)。
            let playheadChanged = abs(playheadSeconds - lastPlayheadSeconds) > 0.001
            let playingChanged = isPlaying != lastIsPlaying
            let seqChanged = lastSequence == nil || lastSequence != sequence
            guard seqChanged || playheadChanged || playingChanged else { return }
            // 仅在序列真的变了时才拼指纹,判定是"结构变(需重建 item)"还是"仅参数变(只更新 videoComposition)"。
            let structureChanged: Bool
            if seqChanged {
                let fp = Self.structureFingerprint(sequence)
                structureChanged = lastSequence == nil || fp != lastFingerprint
                lastFingerprint = fp
            } else {
                structureChanged = false
            }
            lastPlayheadSeconds = playheadSeconds
            lastIsPlaying = isPlaying
            // skimming 中:容差 seek(snap 到最近可解码帧),快速划过不逐帧精确解码卡顿。
            let exactSeek = !isPlaying && !skimming

            if structureChanged {
                // 轨道结构变(增删/移动/trim/blade)→ 重建 item。
                lastSequence = sequence
                player.replaceCurrentItem(with: CompositionBuilder.build(document: store.document))
                seek(playheadSeconds, exact: exactSeek)
            } else if seqChanged {
                // 仅参数变(inspector 调 transform/opacity)→ 只更新 videoComposition,不换 item(避免黑屏闪烁)。
                lastSequence = sequence
                if let item = player.currentItem,
                   let rebuilt = CompositionBuilder.build(document: store.document) {
                    item.videoComposition = rebuilt.videoComposition
                    item.audioMix = rebuilt.audioMix
                }
                if !isPlaying { seek(playheadSeconds, exact: exactSeek) }
            } else if !isPlaying {
                seek(playheadSeconds, exact: exactSeek)
            } else {
                // 播放中:若外部 playhead 与播放器当前时间差距明显(>0.3s),说明是用户主动拖动/跳转
                // (而非 time observer 的自然推进)→ 立即【容差】seek 到新位置继续播(exact=false 避免逐帧解码卡顿)。
                let cur = player.currentTime().seconds
                if cur.isFinite, abs(cur - playheadSeconds) > 0.3 {
                    seek(playheadSeconds, exact: false)
                }
            }
            if isPlaying { player.play() } else { player.pause() }
            ensureObserver(store: store)
        }

        /// 结构指纹:只反映影响轨道布局的字段(spine clip 的 asset/in/out/lane/offset),
        /// 不含 adjust → adjust 变不会触发重建。
        private static func structureFingerprint(_ seq: Sequence) -> String {
            var s = ""
            for el in seq.spine {
                switch el {
                case .gap(_, let d): s += "g\(d.value)/\(d.timescale);"
                case .clip(let c):
                    s += "c\(c.assetID.raw):\(c.sourceIn.value)/\(c.sourceIn.timescale):\(c.duration.value)/\(c.duration.timescale);"
                    for ch in c.connected {
                        s += "k\(ch.assetID.raw):\(ch.lane):\(ch.offset.value):\(ch.sourceIn.value):\(ch.duration.value);"
                    }
                }
            }
            return s
        }

        private func seek(_ seconds: Double, exact: Bool) {
            let t = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            // 播放中(exact=false):容差 seek → snap 到最近可解码帧,点击跳转瞬时完成、不逐帧精确解码。
            // 暂停时(exact=true):零容差 → 精确定位到该帧(帧步进/精修需要)。
            let tol: CMTime = exact ? .zero : CMTime(seconds: 0.15, preferredTimescale: 600)
            let t0 = DispatchTime.now().uptimeNanoseconds
            player.seek(to: t, toleranceBefore: tol, toleranceAfter: tol) { _ in
                PerfProbe.shared.record("player.seek(\(exact ? "exact" : "tol"))",
                                        Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000)
            }
        }

        private func ensureObserver(store: DocumentStore) {
            guard !observing else { return }
            observing = true
            let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak store] time in
                guard let store, store.ui.isPlaying else { return }   // 仅播放时驱动播放头(避免与 seek 形成回路)
                let secs = time.seconds
                if secs.isFinite { store.dispatch(.setPlayhead(Time.seconds(secs))) }
            }
        }

        func teardown() {
            if let timeObserver { player.removeTimeObserver(timeObserver) }
            timeObserver = nil
            observing = false
        }
    }
}

/// 承载 AVPlayerLayer 的 NSView。
final class PlayerHostView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        // 自动跟随父层尺寸(inspector 开关/缩放容器时,不靠 layout() 也能跟上)
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.frame = bounds
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // 覆盖所有 resize 路径(layout 不一定每次都触发,但 setFrameSize 一定)。
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncLayer()
    }
    override func layout() {
        super.layout()
        syncLayer()
    }
    /// 关隐式动画地把 playerLayer 贴满 bounds(消除开关 inspector 时的位移/偏移)。
    private func syncLayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

/// 预览区 SwiftUI 包装:视频 + 底部播放控制条。读取 store 的观察字段以触发 updateNSView。
struct ViewerView: View {
    let store: DocumentStore
    @StateObject private var skim = SkimFrameProvider()

    private var skimAsset: Asset? {
        guard let id = store.ui.skimAssetID else { return nil }
        return store.document.assetLibrary.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PreviewView(store: store,
                            sequence: store.document.sequence,
                            playheadSeconds: store.ui.timelineSkimSeconds ?? store.ui.playhead.seconds,
                            isPlaying: store.ui.isPlaying && store.ui.timelineSkimSeconds == nil,
                            skimming: store.ui.timelineSkimSeconds != nil)
                    .background(Tokens.Palette.canvas)
                // Skim 覆盖层:划过素材池素材时,盖在播放器上显示该素材当前帧(不碰播放器)。
                if store.ui.skimAssetID != nil, let cg = skim.image {
                    Image(decorative: cg, scale: 1)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        .overlay(alignment: .topLeading) {
                            Text("Skim").font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color(TimelineColors.playheadRed)).padding(6)
                        }
                        .allowsHitTesting(false)
                }
                // 标题 on-screen 控制:选中标题时,画面内可拖动+双击改文字。
                TitleOverlay(store: store)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // skim 状态变化 → 请求该帧(asset+seconds 任一变都重算)。
            .onChange(of: store.ui.skimAssetID) { _, _ in updateSkim() }
            .onChange(of: store.ui.skimSeconds) { _, _ in updateSkim() }
            transport
        }
    }

    private func updateSkim() {
        if let asset = skimAsset { skim.request(asset: asset, seconds: store.ui.skimSeconds) }
        else { skim.clear() }
    }

    private var transport: some View {
        HStack(spacing: 10) {
            Button { store.dispatch(.togglePlay) } label: {
                Image(systemName: store.ui.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(Tokens.Palette.textIcon)
            }
            .buttonStyle(.plain)
            .help("播放 / 暂停 (空格)")

            Text(timecode(store.ui.playhead.seconds))
                .font(Tokens.Typeface.timecode)
                .foregroundStyle(Tokens.Palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Tokens.Palette.chrome)
    }

    private func timecode(_ s: Double) -> String {
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
