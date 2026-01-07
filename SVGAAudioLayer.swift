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
        var data: Data?

        if let dict = (videoItem.audiosData as Any) as? [String: Data] {
            data = dict[audioItem.audioKey]
        } else if let dict = (videoItem.audiosData as Any) as? [String: NSData],
                  let nsData = dict[audioItem.audioKey] {
            data = nsData as Data
        } else if let nsDict = (videoItem.audiosData as Any) as? NSDictionary,
                  let nsData = nsDict[audioItem.audioKey] as? NSData {
            data = nsData as Data
        }

        if let data = data, let player = try? AVAudioPlayer(data: data, fileTypeHint: "mp3") {
            player.prepareToPlay()
            self.audioPlayer = player
        }
    }
}
