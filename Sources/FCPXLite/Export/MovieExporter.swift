// Sources/FCPXLite/Export/MovieExporter.swift
import AVFoundation

enum MovieExportError: Error { case emptyTimeline, sessionFailed(String) }

/// 把 Document 渲染成片:复用 CompositionBuilder 的合成,经 AVAssetExportSession 编码。
/// 有视频→mp4(H.264);纯音频→m4a。进度轮询 session.progress。
enum MovieExporter {
    static func export(document: Document, to url: URL,
                       progress: @escaping (Float) -> Void,
                       completion: @escaping (Result<URL, Error>) -> Void) {
        guard let item = CompositionBuilder.build(document: document) else {
            completion(.failure(MovieExportError.emptyTimeline)); return
        }
        let asset = item.asset
        let hasVideo = item.videoComposition != nil
        let preset = hasVideo ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            completion(.failure(MovieExportError.sessionFailed("无法创建导出会话"))); return
        }
        try? FileManager.default.removeItem(at: url)   // 覆盖旧文件
        session.outputURL = url
        session.outputFileType = hasVideo ? .mp4 : .m4a
        if hasVideo { session.videoComposition = item.videoComposition }
        session.audioMix = item.audioMix

        // 进度轮询(导出在后台,主线程回调 UI)。done 守卫:cancel() 不会撤回已入队的主线程 block,
        // 故用标志防止"完成后还报一次进度"打到已拆除的 UI。
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
                default: completion(.failure(session.error ?? MovieExportError.sessionFailed("status=\(session.status.rawValue)")))
                }
            }
        }
    }
}
