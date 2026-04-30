import AVFoundation
import Combine
import Foundation

@MainActor
final class DebugAudioPlayer: NSObject, ObservableObject {
  @Published private(set) var isPlaying: Bool = false
  @Published private(set) var currentTime: TimeInterval = 0
  @Published private(set) var duration: TimeInterval = 0
  @Published private(set) var currentURL: URL?

  private var player: AVAudioPlayer?
  private var displayTimer: Timer?

  func toggle(url: URL) {
    if currentURL == url, let player {
      if player.isPlaying {
        player.pause()
        isPlaying = false
        stopTimer()
      } else {
        player.play()
        isPlaying = true
        startTimer()
      }
      return
    }

    stop()

    do {
      let newPlayer = try AVAudioPlayer(contentsOf: url)
      newPlayer.delegate = self
      newPlayer.prepareToPlay()
      player = newPlayer
      currentURL = url
      duration = newPlayer.duration
      currentTime = 0
      newPlayer.play()
      isPlaying = true
      startTimer()
    } catch {
      AppLogger.app.error("DebugAudioPlayer: failed to load \(url.path): \(error.localizedDescription)")
    }
  }

  func stop() {
    player?.stop()
    player = nil
    isPlaying = false
    currentTime = 0
    duration = 0
    currentURL = nil
    stopTimer()
  }

  func seek(to time: TimeInterval) {
    guard let player else { return }
    let clamped = max(0, min(time, player.duration))
    player.currentTime = clamped
    currentTime = clamped
  }

  private func startTimer() {
    stopTimer()
    displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, let player = self.player else { return }
        self.currentTime = player.currentTime
      }
    }
  }

  private func stopTimer() {
    displayTimer?.invalidate()
    displayTimer = nil
  }
}

extension DebugAudioPlayer: AVAudioPlayerDelegate {
  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in
      self.isPlaying = false
      self.currentTime = 0
      self.stopTimer()
    }
  }
}
