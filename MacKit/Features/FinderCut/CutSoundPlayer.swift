import AppKit

/// Small bundled PCM sample; loaded once on first use, no audio engine or idle work.
@MainActor
final class CutSoundPlayer {
    private var sound: NSSound?
    func play() {
        if sound == nil, let url = Bundle.main.url(forResource: "Cut", withExtension: "wav") {
            sound = NSSound(contentsOf: url, byReference: false)
            sound?.volume = 0.55
        }
        sound?.stop()
        sound?.play()
    }
    func stop() { sound?.stop() }
}
