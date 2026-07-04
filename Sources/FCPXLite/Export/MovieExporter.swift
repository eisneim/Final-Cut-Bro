// Sources/FCPXLite/Export/MovieExporter.swift
import AVFoundation

enum MovieExportError: Error, CustomStringConvertible {
    case emptyTimeline
    case sessionFailed(String)
    case readerFailed(String)     // AVAssetReader 读取中失败(surface reader.error)
    case stalled(String)          // 看门狗:长时间无进度(卡死)→ 暴露诊断

    var description: String {
        switch self {
        case .emptyTimeline:        return "时间线为空,无可导出内容"
        case .sessionFailed(let m): return "导出会话失败:\(m)"
        case .readerFailed(let m):  return "读取素材失败:\(m)"
        case .stalled(let m):       return "导出卡住(超时无进度):\(m)"
        }
    }
}

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

        let totalDuration = CMTimeGetSeconds(composition.duration)
        // 视频实际内容到哪结束(音频可能更长 = 纯音乐尾巴)。视频 reader 截到这里 → 自然 EOF,不渲染黑尾。
        let videoContentEnd = composition.tracks(withMediaType: .video)
            .map { CMTimeGetSeconds($0.timeRange.end) }.max() ?? totalDuration

        // --- AVAssetReader path ---
        // C2 导出卡死修复:视频与音频用【各自独立的 AVAssetReader + 各自的串行队列】。
        // 旧实现共用一个 reader + 一条队列,视频在 videoContentEnd 处中途放弃(CMSampleBufferInvalidate 不排空)
        // 会把共享渲染管线塞死 → 音频 copyNextSampleBuffer 永远等不到 → 卡在 "audio reader finalize"。
        // 现在:视频 reader 用 timeRange 截到 videoContentEnd(自然 EOF,快),音频 reader 读全长,互不影响。
        let wantVideo = hasVideo && videoComposition != nil
        let wantAudio = settings.includeAudio && !composition.tracks(withMediaType: .audio).isEmpty

        var videoReader: AVAssetReader?
        var videoOut: AVAssetReaderVideoCompositionOutput?
        if wantVideo, let vc = videoComposition, let r = try? AVAssetReader(asset: composition) {
            let out = AVAssetReaderVideoCompositionOutput(
                videoTracks: composition.tracks(withMediaType: .video),
                videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            out.videoComposition = vc
            out.alwaysCopiesSampleData = false
            if videoContentEnd > 0, videoContentEnd < totalDuration {
                r.timeRange = CMTimeRange(start: .zero,
                                          duration: CMTime(seconds: videoContentEnd, preferredTimescale: 600))
            }
            if r.canAdd(out) { r.add(out); videoReader = r; videoOut = out }
        }

        var audioReader: AVAssetReader?
        var audioOut: AVAssetReaderAudioMixOutput?
        if wantAudio, let r = try? AVAssetReader(asset: composition) {
            let out = AVAssetReaderAudioMixOutput(
                audioTracks: composition.tracks(withMediaType: .audio), audioSettings: nil)
            out.audioMix = audioMix
            out.alwaysCopiesSampleData = false
            if r.canAdd(out) { r.add(out); audioReader = r; audioOut = out }
        }

        // 两个 reader 都起不来 → 退回 ExportSession。
        guard videoReader != nil || audioReader != nil else {
            fallbackExport(document: document, to: url, settings: settings,
                           hasVideo: hasVideo, progress: progress, completion: completion); return
        }
        if let vr = videoReader, !vr.startReading() {
            NSLog("[MovieExporter] 视频 reader startReading 失败,退回。error=\(String(describing: vr.error))")
            fallbackExport(document: document, to: url, settings: settings,
                           hasVideo: hasVideo, progress: progress, completion: completion); return
        }
        if let ar = audioReader, !ar.startReading() {
            NSLog("[MovieExporter] 音频 reader startReading 失败,退回。error=\(String(describing: ar.error))")
            fallbackExport(document: document, to: url, settings: settings,
                           hasVideo: hasVideo, progress: progress, completion: completion); return
        }

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: fileType) else {
            videoReader?.cancelReading(); audioReader?.cancelReading()
            completion(.failure(MovieExportError.sessionFailed("无法创建 AVAssetWriter"))); return
        }

        var writerVideoInput: AVAssetWriterInput? = nil
        if videoReader != nil {
            let vSettings = videoSettings(codec: settings.codec, quality: settings.quality, size: renderSize)
            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
            vInput.expectsMediaDataInRealTime = false
            if writer.canAdd(vInput) { writer.add(vInput); writerVideoInput = vInput }
        }

        var writerAudioInput: AVAssetWriterInput? = nil
        if audioReader != nil {
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

        // 两条 pump 队列各自独立;共享状态(finished/done/progress)统一走串行 stateQ,线程安全。
        let qV = DispatchQueue(label: "fcpxlite.export.video")
        let qA = DispatchQueue(label: "fcpxlite.export.audio")
        let stateQ = DispatchQueue(label: "fcpxlite.export.state")
        var doneCalled = false
        var videoFinished = (writerVideoInput == nil)
        var audioFinished = (writerAudioInput == nil)
        var lastActivity = Date()
        var lastProgressPct: Float = 0
        var watchdog: DispatchSourceTimer?

        func statusStr(_ s: AVAssetReader.Status?) -> String {
            switch s {
            case .reading: return "reading"; case .completed: return "completed"
            case .failed: return "failed"; case .cancelled: return "cancelled"
            default: return "unknown"
            }
        }
        // 以下几个函数只在 stateQ 上调用,访问共享状态安全。
        func finish(result: Result<URL, Error>) {
            guard !doneCalled else { return }
            doneCalled = true
            watchdog?.cancel(); watchdog = nil
            DispatchQueue.main.async { completion(result) }
        }
        func checkDone() {
            guard !doneCalled, videoFinished, audioFinished else { return }
            watchdog?.cancel(); watchdog = nil
            writerVideoInput?.markAsFinished()
            writerAudioInput?.markAsFinished()
            videoReader?.cancelReading(); audioReader?.cancelReading()
            writer.finishWriting {
                DispatchQueue.main.async { if writer.status == .completed { progress(1.0) } }
                stateQ.async {
                    if writer.status == .completed { finish(result: .success(url)) }
                    else { finish(result: .failure(writer.error ?? MovieExportError.sessionFailed("writer failed"))) }
                }
            }
        }

        if let vInput = writerVideoInput, let vOut = videoOut {
            vInput.requestMediaDataWhenReady(on: qV) {
                while vInput.isReadyForMoreMediaData {
                    if let buf = vOut.copyNextSampleBuffer() {
                        vInput.append(buf)
                        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buf))
                        stateQ.async {
                            lastActivity = Date()
                            if totalDuration > 0 {
                                let p = Float(pts / totalDuration) * 0.9
                                if p > lastProgressPct { lastProgressPct = p; DispatchQueue.main.async { progress(p) } }
                            }
                        }
                    } else {
                        let failed = (videoReader?.status == .failed)
                        let err = videoReader?.error
                        stateQ.async {
                            if failed {
                                finish(result: .failure(MovieExportError.readerFailed("视频轨读取失败:\(String(describing: err))")))
                            } else { videoFinished = true; checkDone() }
                        }
                        return
                    }
                }
            }
        }

        if let aInput = writerAudioInput, let aOut = audioOut {
            aInput.requestMediaDataWhenReady(on: qA) {
                while aInput.isReadyForMoreMediaData {
                    if let buf = aOut.copyNextSampleBuffer() {
                        aInput.append(buf)
                        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buf))
                        stateQ.async {
                            lastActivity = Date()
                            if totalDuration > 0 {
                                let p = Float(pts / totalDuration) * 0.9
                                if p > lastProgressPct { lastProgressPct = p; DispatchQueue.main.async { progress(p) } }
                            }
                        }
                    } else {
                        let failed = (audioReader?.status == .failed)
                        let err = audioReader?.error
                        stateQ.async {
                            if failed {
                                finish(result: .failure(MovieExportError.readerFailed("音频轨读取失败:\(String(describing: err))")))
                            } else { audioFinished = true; checkDone() }
                        }
                        return
                    }
                }
            }
        }

        // 看门狗:stallTimeout 秒无进度 → 判定卡死,取消并暴露诊断。
        let stallTimeout: TimeInterval = 30
        let wd = DispatchSource.makeTimerSource(queue: stateQ)
        wd.schedule(deadline: .now() + 5, repeating: 3)
        wd.setEventHandler {
            if doneCalled { wd.cancel(); return }
            if Date().timeIntervalSince(lastActivity) > stallTimeout {
                let diag = "停在 \(Int(lastProgressPct * 100))%;video完成=\(videoFinished) audio完成=\(audioFinished);"
                    + "videoReader=\(statusStr(videoReader?.status)) audioReader=\(statusStr(audioReader?.status)) writer=\(writer.status.rawValue);"
                    + "videoErr=\(String(describing: videoReader?.error)) audioErr=\(String(describing: audioReader?.error)) writerErr=\(String(describing: writer.error))"
                NSLog("[MovieExporter] 导出卡死:\(diag)")
                videoReader?.cancelReading(); audioReader?.cancelReading(); writer.cancelWriting()
                finish(result: .failure(MovieExportError.stalled(diag)))
            }
        }
        watchdog = wd
        wd.resume()
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
