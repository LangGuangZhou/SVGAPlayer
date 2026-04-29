import Foundation
import AVFoundation

@objcMembers
final class SVGAAudioLayer: NSObject {

    /// Readonly for ObjC
    private(set) var audioPlayer: AVAudioPlayer?
    /// Readonly for ObjC
    let audioItem: SVGAAudioEntity

    /// Exposed to ObjC as: - (instancetype)initWithAudioItem:(SVGAAudioEntity *)audioItem videoItem:(SVGAVideoEntity *)videoItem;
    init(audioItem: SVGAAudioEntity, videoItem: SVGAVideoEntity) {
        self.audioItem = audioItem
        super.init()

        // Try to fetch audio data by key from videoItem.audiosData
        let data = videoItem.audiosData[audioItem.audioKey]

        if let data = data, let player = try? AVAudioPlayer(data: data, fileTypeHint: "mp3") {
            player.prepareToPlay()
            self.audioPlayer = player
        }
    }
}
