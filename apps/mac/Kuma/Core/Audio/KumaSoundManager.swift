import Foundation
import AVFoundation
import AppKit
import os

@MainActor
public final class KumaSoundManager: NSObject, AVAudioPlayerDelegate {
    private static let logger = Logger(subsystem: "lokastudio.kuma", category: "KumaSoundManager")
    public static let shared = KumaSoundManager()

    private var audioPlayer: AVAudioPlayer?

    private override init() {
        super.init()
        syncCustomNotificationSoundToUserLibrary()
    }

    /// Ensures the custom notification sound is installed in ~/Library/Sounds/
    /// so macOS notification daemon (usernoted) can access and play it for native notifications.
    public func syncCustomNotificationSoundToUserLibrary() {
        guard let bundleSoundURL = Bundle.main.url(forResource: "kuma-alert", withExtension: "caf") else {
            return
        }

        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let userSoundsDirectory = homeDirectory.appendingPathComponent("Library/Sounds", isDirectory: true)
        let destinationURL = userSoundsDirectory.appendingPathComponent("kuma-alert.caf")

        let userSoundsPath = userSoundsDirectory.path(percentEncoded: false)
        let destinationPath = destinationURL.path(percentEncoded: false)

        do {
            if !fileManager.fileExists(atPath: userSoundsPath) {
                try fileManager.createDirectory(at: userSoundsDirectory, withIntermediateDirectories: true)
            }

            if fileManager.fileExists(atPath: destinationPath) {
                return // Sound is already installed, skip redundant disk I/O on startup
            }

            try fileManager.copyItem(at: bundleSoundURL, to: destinationURL)
        } catch {
            Self.logger.error("Could not sync sound to ~/Library/Sounds: \(error.localizedDescription)")
        }
    }

    /// Plays the custom notification sound (`kuma-alert.caf`).
    public func playNotificationSound() {
        guard let soundURL = Bundle.main.url(forResource: "kuma-alert", withExtension: "caf") else {
            NSSound.beep()
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.volume = 0.45 // Standardized preview volume (~45%) for comfortable listening
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.audioPlayer = player
        } catch {
            Self.logger.error("Failed to play notification sound: \(error.localizedDescription)")
            NSSound.beep()
        }
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finishedID = ObjectIdentifier(player)
        Task { @MainActor in
            if let current = self.audioPlayer, ObjectIdentifier(current) == finishedID {
                self.audioPlayer = nil
            }
        }
    }
}

