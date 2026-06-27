import AVFoundation

/// 文档 → 可播放合成。v1:主轴(spine)的视频+音频按时间拼接到一条视频轨 + 一条音频轨。
/// 静止图片暂跳过(占位推进时间,预览处为黑场);连接片段(lane!=0)的视频叠加留待后续。
/// AVPlayer 实时解码源帧并合成,不重新编码;空内容返回 nil。
enum CompositionBuilder {

    private static func cm(_ t: Time) -> CMTime {
        CMTime(value: t.value, timescale: t.timescale)
    }

    static func build(document: Document) -> AVPlayerItem? {
        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(withMediaType: .video,
                                                         preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                                                         preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }

        let library = Dictionary(uniqueKeysWithValues: document.assetLibrary.map { ($0.id, $0) })

        var cursor = CMTime.zero
        var inserted = false

        for element in document.sequence.spine {
            let elementDuration = cm(element.duration)
            defer { cursor = cursor + elementDuration }  // 间隙/图片也推进时间,保持对齐

            guard case .clip(let clip) = element,
                  let asset = library[clip.assetID],
                  asset.kind != .image           // 图片暂不支持预览(TODO: 静止图转视频轨)
            else { continue }

            let avAsset = AVURLAsset(url: asset.url)
            let srcRange = CMTimeRange(start: cm(clip.sourceIn), duration: cm(clip.duration))

            // deprecated 同步取轨,v1 可用(与 MediaImporter 一致)
            if let vTrack = avAsset.tracks(withMediaType: .video).first {
                do {
                    try videoTrack.insertTimeRange(srcRange, of: vTrack, at: cursor)
                    inserted = true
                } catch {
                    print("[CompositionBuilder] 视频插入失败 \(asset.url.lastPathComponent): \(error)")
                }
            }
            if asset.hasAudio, let aTrack = avAsset.tracks(withMediaType: .audio).first {
                do {
                    try audioTrack.insertTimeRange(srcRange, of: aTrack, at: cursor)
                } catch {
                    print("[CompositionBuilder] 音频插入失败 \(asset.url.lastPathComponent): \(error)")
                }
            }
        }

        guard inserted else { return nil }
        return AVPlayerItem(asset: composition)
    }
}
