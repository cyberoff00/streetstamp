import Foundation
import AVFoundation
import Combine
import UIKit

@MainActor
final class VoiceBroadcastService: NSObject {
    static let shared = VoiceBroadcastService()

    private let tracking = TrackingService.shared
    private let synthesizer = AVSpeechSynthesizer()

    private var bag = Set<AnyCancellable>()
    private var isStarted = false

    private var journeyStartAt: Date?
    private var lastAnnouncedStep: Int = 0

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        tracking.$isTracking
            .removeDuplicates()
            .sink { [weak self] isTracking in
                guard let self else { return }
                if isTracking {
                    journeyStartAt = Date()
                    lastAnnouncedStep = 0
                } else {
                    journeyStartAt = nil
                    lastAnnouncedStep = 0
                    synthesizer.stopSpeaking(at: .immediate)
                }
            }
            .store(in: &bag)

        tracking.$totalDistance
            .sink { [weak self] totalDistance in
                self?.handleDistanceUpdate(totalDistance)
            }
            .store(in: &bag)
    }

    private func handleDistanceUpdate(_ totalDistance: Double) {
        guard tracking.isTracking, !tracking.isPaused else { return }
        guard tracking.trackingMode == .sport else { return }
        guard AppSettings.isVoiceBroadcastEnabled else { return }
        guard let start = journeyStartAt else { return }

        let intervalKM = max(1, AppSettings.voiceBroadcastIntervalKM)
        let stepMeters = Double(intervalKM) * 1000.0
        let currentStep = Int(floor(totalDistance / stepMeters))
        guard currentStep > 0, currentStep > lastAnnouncedStep else { return }

        lastAnnouncedStep = currentStep

        let milestoneKM = currentStep * intervalKM
        let elapsed = Date().timeIntervalSince(start)
        let paceMinutesPerKM = totalDistance > 1 ? (elapsed / 60.0) / (totalDistance / 1000.0) : 0

        let elapsedMinutes = Int(elapsed / 60.0)
        let paceText: String
        if paceMinutesPerKM > 0 {
            paceText = String(format: "%.1f", paceMinutesPerKM)
        } else {
            paceText = "--"
        }

        let message = String(format: L10n.t("voice_broadcast_milestone"), milestoneKM, elapsedMinutes, paceText)
        speak(message)
    }

    private func speak(_ text: String) {
        activateBackgroundSpeechAudioSessionIfNeeded()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier == "zh" ? "zh-CN" : "en-US")
        utterance.volume = 0.95
        synthesizer.speak(utterance)
    }

    private func activateBackgroundSpeechAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            print("VoiceBroadcastService audio session activate failed: \(error.localizedDescription)")
        }
    }
}

extension VoiceBroadcastService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        do {
            // Deactivate and notify other audio apps (e.g. Music) to resume.
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("VoiceBroadcastService audio session deactivate failed: \(error.localizedDescription)")
        }
    }
}
