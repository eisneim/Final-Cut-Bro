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

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: PlayerHostView, context: Context) {
        context.coordinator.update(sequence: sequence, store: store,
                                   playheadSeconds: playheadSeconds, isPlaying: isPlaying)
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

        func attach(to view: PlayerHostView) {
            view.playerLayer.player = player
        }

        func update(sequence: Sequence, store: DocumentStore, playheadSeconds: Double, isPlaying: Bool) {
            let fp = Self.structureFingerprint(sequence)
            if lastSequence == nil || fp != lastFingerprint {
                // 轨道结构变(增删/移动/trim/blade)→ 重建 item。
                lastSequence = sequence
                lastFingerprint = fp
                player.replaceCurrentItem(with: CompositionBuilder.build(document: store.document))
                seek(playheadSeconds)
            } else if lastSequence != sequence {
                // 仅参数变(inspector 调 transform/opacity)→ 只更新 videoComposition,不换 item(避免黑屏闪烁)。
                lastSequence = sequence
                if let item = player.currentItem,
                   let rebuilt = CompositionBuilder.build(document: store.document) {
                    item.videoComposition = rebuilt.videoComposition
                    item.audioMix = rebuilt.audioMix
                }
                if !isPlaying { seek(playheadSeconds) }
            } else if !isPlaying {
                seek(playheadSeconds)
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
                case .gap(let d): s += "g\(d.value)/\(d.timescale);"
                case .clip(let c):
                    s += "c\(c.assetID.raw):\(c.sourceIn.value)/\(c.sourceIn.timescale):\(c.duration.value)/\(c.duration.timescale);"
                    for ch in c.connected {
                        s += "k\(ch.assetID.raw):\(ch.lane):\(ch.offset.value):\(ch.sourceIn.value):\(ch.duration.value);"
                    }
                }
            }
            return s
        }

        private func seek(_ seconds: Double) {
            let t = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
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
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

/// 预览区 SwiftUI 包装:视频 + 底部播放控制条。读取 store 的观察字段以触发 updateNSView。
struct ViewerView: View {
    let store: DocumentStore

    var body: some View {
        VStack(spacing: 0) {
            PreviewView(store: store,
                        sequence: store.document.sequence,
                        playheadSeconds: store.ui.playhead.seconds,
                        isPlaying: store.ui.isPlaying)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tokens.Palette.canvas)
            transport
        }
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
