// Sources/FCPXLite/Export/MovieExporter.swift
import AVFoundation

enum MovieExportError: Error { case emptyTimeline, sessionFailed(String) }

/// 把 Document 渲染成片。
/// 主路径:AVAssetReader + AVAssetWriter (codec/bitrate/size 精确控制)。
/// 备用路径:AVAssetExportSession preset (若 AVAssetReader 无法启动)。
enum MovieExporter {

    static func outputFileType(for codec: ExportCodec) -> AVFileType {
        codec == .prores ? .mov : .mp4
    }

    /// 目标码率(bps),按 1080p 基准乘以分辨率面积比。ProRes 返回 nil。
    static func targetBitrate(quality: ExportQuality, size: CGSize) -> Int? {
        guard size.width > 0, size.height > 0 else { return nil }
        let base1080pPixels: Double = 1920 * 1080
        let targetPixels = Double(size.width * size.height)
        let scaleFactor = targetPixels / base1080pPixels
        let baseBps: Double
        switch quality {
        case .low:    baseBps = 2_000_000
        case .medium: baseBps = 8_000_000
        case .high:   baseBps = 20_000_000
        }
        return Int(baseBps * scaleFactor)
    }

    static func videoSettings(codec: ExportCodec, quality: ExportQuality, size: CGSize) -> [String: Any] {
        let codecType: AVVideoCodecType
        switch codec {
        case .h264:   codecType = .h264
        case .h265:   codecType = .hevc
        case .prores: codecType = .proRes422
        }
        var settings: [String: Any] = [
            AVVideoCodecKey: codecType,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        if codec != .prores, let bps = targetBitrate(quality: quality, size: size) {
            settings[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: bps]
        }
        return settings
    }

    static func export(document: Document,
                       to url: URL,
                       settings: ExportSettings,
                       progress: @escaping (Float) -> Void,
                       completion: @escaping (Result<URL, Error>) -> Void) {
        guard let item = CompositionBuilder.build(document: document) else {
            completion(.failure(MovieExportError.emptyTimeline)); return
        }
        let composition = item.asset
        let videoComposition = item.videoComposition
        let audioMix = item.audioMix
        let hasVideo = videoComposition != nil
        let fileType = outputFileType(for: settings.codec)

        // 导出尺寸【保持项目宽高比】(不再用固定横屏尺寸把竖屏拉成横屏)。
        // vc.renderSize = 项目宽高;writer 用同比例尺寸 → reader→writer 只等比缩放,不拉伸。
        let renderSize = settings.resolution.renderSize(
            projectWidth: document.formatWidth, projectHeight: document.formatHeight)

        try? FileManager.default.removeItem(at: url)

        // --- AVAssetReader path ---
        guard let reader = try? AVAssetReader(asset: composition) else {
            fallbackExport(document: document, to: url, settings: settings,
                           hasVideo: hasVideo, progress: progress, completion: completion); return
        }

        var readerOutputs: [AVAssetReaderOutput] = []

        if hasVideo, let vc = videoComposition {
            let videoOut = AVAssetReaderVideoCompositionOutput(
                videoTracks: composition.tracks(withMediaType: .video),
                videoSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                    kCVPixelFormatType_32BGRA])
            videoOut.videoComposition = vc
            videoOut.alwaysCopiesSampleData = false
            if reader.canAdd(videoOut) { reader.add(videoOut); readerOutputs.append(videoOut) }
        }

        var audioOut: AVAssetReaderAudioMixOutput? = nil
        if settings.includeAudio, !composition.tracks(withMediaType: .audio).isEmpty {
            let aOut = AVAssetReaderAudioMixOutput(
                audioTracks: composition.tracks(withMediaType: .audio),
                audioSettings: nil)
            aOut.audioMix = audioMix
            aOut.alwaysCopiesSampleData = false
            if reader.canAdd(aOut) { reader.add(aOut); audioOut = aOut }
        }

        guard reader.startReading() else {
            // 主路径(AVAssetReader+Writer,支持自定义合成器)起不来 → 记录原因再退回。
            // 退回用的 AVAssetExportSession 对【自定义 AVVideoCompositing】支持不可靠,长复杂时间线易 -11841,
            // 所以这里必须留诊断:下次 live 失败能看到主路径到底为何起不来。
            NSLog("[MovieExporter] 主路径 startReading 失败,退回 AVAssetExportSession。reader.error=\(String(describing: reader.error))")
            fallbackExport(document: document, to: url, settings: settings,
                           hasVideo: hasVideo, progress: progress, completion: completion); return
        }

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: fileType) else {
            reader.cancelReading()
            completion(.failure(MovieExportError.sessionFailed("无法创建 AVAssetWriter"))); return
        }

        var writerVideoInput: AVAssetWriterInput? = nil
        if hasVideo {
            let vSettings = videoSettings(codec: settings.codec, quality: settings.quality, size: renderSize)
            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
            vInput.expectsMediaDataInRealTime = false
            if writer.canAdd(vInput) { writer.add(vInput); writerVideoInput = vInput }
        }

        var writerAudioInput: AVAssetWriterInput? = nil
        if audioOut != nil {
            let aSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
            aInput.expectsMediaDataInRealTime = false
            if writer.canAdd(aInput) { writer.add(aInput); writerAudioInput = aInput }
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalDuration = CMTimeGetSeconds(composition.duration)
        // 视频实际内容到哪结束(音频可能更长 = 纯音乐尾巴)。超过这里就停止拉视频帧:
        // 否则 AVFoundation 对"音频更长、视频已无内容"的尾部逐帧空转,慢到像卡死。
        // 视频在此截止,音频继续 → 成片末尾是黑屏 + 音乐(标准做法),且导出飞快。
        let videoContentEnd = composition.tracks(withMediaType: .video)
            .map { CMTimeGetSeconds($0.timeRange.end) }.max() ?? totalDuration
        var doneCalled = false
        let q = DispatchQueue(label: "fcpxlite.export")

        func finish(result: Result<URL, Error>) {
            guard !doneCalled else { return }
            doneCalled = true
            DispatchQueue.main.async { completion(result) }
        }

        // Track per-input completion
        var videoFinished = (writerVideoInput == nil)
        var audioFinished = (writerAudioInput == nil)

        func checkDone() {
            guard videoFinished, audioFinished else { return }
            writerVideoInput?.markAsFinished()
            writerAudioInput?.markAsFinished()
            reader.cancelReading()
            writer.finishWriting {
                DispatchQueue.main.async { progress(1.0) }
                if writer.status == .completed {
                    finish(result: .success(url))
                } else {
                    finish(result: .failure(writer.error ?? MovieExportError.sessionFailed("writer failed")))
                }
            }
        }

        if let vInput = writerVideoInput,
           let vOut = readerOutputs.first(where: { $0 is AVAssetReaderVideoCompositionOutput }) {
            vInput.requestMediaDataWhenReady(on: q) {
                while vInput.isReadyForMoreMediaData {
                    if let buf = vOut.copyNextSampleBuffer() {
                        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buf))
                        // 视频内容已结束(后面只有更长的音频)→ 停止写视频帧,不渲染慢吞吞的黑尾。
                        if pts > videoContentEnd + 0.001 {
                            CMSampleBufferInvalidate(buf)
                            videoFinished = true
                            checkDone()
                            return
                        }
                        vInput.append(buf)
                        if totalDuration > 0 {
                            DispatchQueue.main.async { progress(Float(pts / totalDuration) * 0.9) }
                        }
                    } else {
                        videoFinished = true
                        checkDone()
                        return
                    }
                }
            }
        }

        if let aInput = writerAudioInput, let aOut = audioOut {
            aInput.requestMediaDataWhenReady(on: q) {
                while aInput.isReadyForMoreMediaData {
                    if let buf = aOut.copyNextSampleBuffer() {
                        aInput.append(buf)
                    } else {
                        audioFinished = true
                        checkDone()
                        return
                    }
                }
            }
        }

        // Pure-audio path: no video input, trigger checkDone when audio finishes
        if writerVideoInput == nil, writerAudioInput == nil {
            finish(result: .failure(MovieExportError.emptyTimeline))
        }
    }

    // MARK: - Fallback: AVAssetExportSession

    private static func fallbackExport(document: Document, to url: URL,
                                       settings: ExportSettings,
                                       hasVideo: Bool,
                                       progress: @escaping (Float) -> Void,
                                       completion: @escaping (Result<URL, Error>) -> Void) {
        guard let item = CompositionBuilder.build(document: document) else {
            completion(.failure(MovieExportError.emptyTimeline)); return
        }
        let asset = item.asset
        let preset: String
        switch settings.codec {
        case .prores: preset = hasVideo ? AVAssetExportPresetAppleProRes422LPCM : AVAssetExportPresetAppleM4A
        case .h265:   preset = hasVideo ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetAppleM4A
        case .h264:   preset = hasVideo ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            completion(.failure(MovieExportError.sessionFailed("无法创建导出会话(fallback)"))); return
        }
        try? FileManager.default.removeItem(at: url)
        session.outputURL = url
        session.outputFileType = hasVideo ? (settings.codec == .prores ? .mov : .mp4) : .m4a
        if hasVideo { session.videoComposition = item.videoComposition }
        session.audioMix = item.audioMix

        var done = false
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 0.1)
        timer.setEventHandler { if !done { progress(session.progress) } }
        timer.resume()

        session.exportAsynchronously {
            timer.cancel()
            DispatchQueue.main.async {
                done = true
                switch session.status {
                case .completed: progress(1); completion(.success(url))
                case .cancelled: completion(.failure(MovieExportError.sessionFailed("已取消")))
                default:
                    NSLog("[MovieExporter] fallback AVAssetExportSession 失败 status=\(session.status.rawValue) error=\(String(describing: session.error)) — 自定义合成器在 ExportSession 下不被支持是常见原因")
                    completion(.failure(session.error ?? MovieExportError.sessionFailed("status=\(session.status.rawValue)")))
                }
            }
        }
    }
}
