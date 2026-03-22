import XCTest
import AVFoundation
@testable import StreetStamps

@MainActor
final class VoiceBroadcastServiceTests: XCTestCase {
    func test_audioSessionController_activatesSpeechWithoutDuckingOtherAudio() {
        let session = MockVoiceBroadcastAudioSession()
        let controller = VoiceBroadcastAudioSessionController(session: session)

        controller.activateForSpeechIfNeeded()

        XCTAssertEqual(session.categoryCalls.count, 1)
        XCTAssertEqual(session.categoryCalls.first?.category, .playback)
        XCTAssertEqual(session.categoryCalls.first?.mode, .spokenAudio)
        XCTAssertEqual(session.categoryCalls.first?.options, [.mixWithOthers])
        XCTAssertEqual(session.activeCalls, [(true, [])])
    }

    func test_audioSessionController_deactivatesAndNotifiesOthersWhenSpeechEnds() {
        let session = MockVoiceBroadcastAudioSession()
        let controller = VoiceBroadcastAudioSessionController(session: session)
        controller.activateForSpeechIfNeeded()

        controller.deactivateIfNeeded()

        XCTAssertEqual(
            session.activeCalls,
            [
                (true, []),
                (false, [.notifyOthersOnDeactivation])
            ]
        )
    }

    func test_speechSynthesizerDelegate_didFinishDeactivatesAudioSession() {
        let audioSession = MockVoiceBroadcastAudioSession()
        let controller = VoiceBroadcastAudioSessionController(session: audioSession)
        let synthesizer = MockSpeechSynthesizer()
        let service = VoiceBroadcastService(
            synthesizer: synthesizer,
            audioSessionController: controller
        )
        let utterance = AVSpeechUtterance(string: "test")

        controller.activateForSpeechIfNeeded()
        synthesizer.isSpeaking = false
        service.speechSynthesizer(AVSpeechSynthesizer(), didFinish: utterance)

        XCTAssertEqual(audioSession.activeCalls.last, (false, [.notifyOthersOnDeactivation]))
    }

    func test_speechSynthesizerDelegate_didCancelDeactivatesAudioSession() {
        let audioSession = MockVoiceBroadcastAudioSession()
        let controller = VoiceBroadcastAudioSessionController(session: audioSession)
        let synthesizer = MockSpeechSynthesizer()
        let service = VoiceBroadcastService(
            synthesizer: synthesizer,
            audioSessionController: controller
        )
        let utterance = AVSpeechUtterance(string: "test")

        controller.activateForSpeechIfNeeded()
        synthesizer.isSpeaking = false
        service.speechSynthesizer(AVSpeechSynthesizer(), didCancel: utterance)

        XCTAssertEqual(audioSession.activeCalls.last, (false, [.notifyOthersOnDeactivation]))
    }
}

private final class MockVoiceBroadcastAudioSession: VoiceBroadcastAudioSessionClient {
    var categoryCalls: [(category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions)] = []
    var activeCalls: [(Bool, AVAudioSession.SetActiveOptions)] = []

    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws {
        categoryCalls.append((category, mode, options))
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        activeCalls.append((active, options))
    }
}

private final class MockSpeechSynthesizer: VoiceBroadcastSpeechSynthesizing {
    weak var delegate: AVSpeechSynthesizerDelegate?
    var isSpeaking = false

    func speak(_ utterance: AVSpeechUtterance) {
        isSpeaking = true
    }

    @discardableResult
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        let wasSpeaking = isSpeaking
        isSpeaking = false
        return wasSpeaking
    }
}
