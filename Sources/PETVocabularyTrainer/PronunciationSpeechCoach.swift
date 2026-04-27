import AVFoundation
import Combine
import Foundation
import Speech

struct PronunciationPermissionProvider {
    var requestSpeechAuthorization: @Sendable () async -> Bool
    var requestMicrophoneAuthorization: @Sendable () async -> Bool

    static let live = PronunciationPermissionProvider(
        requestSpeechAuthorization: {
            await PronunciationSystemPermissionBroker.requestSpeechAuthorization()
        },
        requestMicrophoneAuthorization: {
            await PronunciationSystemPermissionBroker.requestMicrophoneAuthorization()
        }
    )
}

enum PronunciationAudioInput {
    static func isUsable(sampleRate: Double, channelCount: AVAudioChannelCount) -> Bool {
        sampleRate > 0 && channelCount > 0
    }
}

enum PronunciationAudioTap {
    typealias Handler = (AVAudioPCMBuffer, AVAudioTime) -> Void

    nonisolated static func makeHandler(request: SFSpeechAudioBufferRecognitionRequest) -> Handler {
        { [weak request] buffer, _ in
            request?.append(buffer)
        }
    }

    nonisolated static func install(
        on inputNode: AVAudioNode,
        bus: AVAudioNodeBus,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        inputNode.installTap(
            onBus: bus,
            bufferSize: 1_024,
            format: format,
            block: makeHandler(request: request)
        )
    }
}

private enum PronunciationSystemPermissionBroker {
    nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    nonisolated static func requestMicrophoneAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { isAllowed in
                    continuation.resume(returning: isAllowed)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

@MainActor
final class PronunciationSpeechCoach: NSObject, ObservableObject {
    enum CoachState: Equatable {
        case idle
        case requestingPermission
        case listening
        case checking
        case result
        case unavailable
    }

    @Published private(set) var state: CoachState = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var rating: PronunciationRating?
    @Published private(set) var message = "Tap Start Speaking, say the word clearly, then let the cat check."

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let permissionProvider: PronunciationPermissionProvider
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var autoStopTask: Task<Void, Never>?
    private var hasInstalledInputTap = false

    init(permissionProvider: PronunciationPermissionProvider = .live) {
        self.permissionProvider = permissionProvider
        super.init()
    }

    var isBusy: Bool {
        state == .requestingPermission || state == .listening || state == .checking
    }

    func start(targetWord: String) {
        guard !isBusy else { return }

        resetForNewAttempt()
        state = .requestingPermission
        message = "Checking microphone permission..."

        Task {
            let hasSpeechAccess = await permissionProvider.requestSpeechAuthorization()
            let hasMicrophoneAccess = await permissionProvider.requestMicrophoneAuthorization()

            guard hasSpeechAccess, hasMicrophoneAccess else {
                state = .unavailable
                message = "Microphone or speech permission is not available. You can still self-check below."
                return
            }

            do {
                try startRecognition(targetWord: targetWord)
            } catch {
                state = .unavailable
                message = "Speech check could not start. You can still self-check below."
            }
        }
    }

    func finish(targetWord: String) {
        guard state == .listening || state == .checking else { return }

        state = .checking
        message = "Cat is checking what it heard..."
        stopAudio()

        let spokenText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        rating = PronunciationAssessment.rate(spokenText: spokenText, targetWord: targetWord)
        state = .result
        message = feedbackMessage(for: rating)
    }

    func reset() {
        autoStopTask?.cancel()
        autoStopTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        stopAudio()
        transcript = ""
        rating = nil
        state = .idle
        message = "Tap Start Speaking, say the word clearly, then let the cat check."
    }

    private func resetForNewAttempt() {
        autoStopTask?.cancel()
        autoStopTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        stopAudio()
        transcript = ""
        rating = nil
    }

    private func startRecognition(targetWord: String) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw PronunciationSpeechError.recognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard PronunciationAudioInput.isUsable(sampleRate: format.sampleRate, channelCount: format.channelCount) else {
            throw PronunciationSpeechError.inputFormatUnavailable
        }

        if hasInstalledInputTap {
            inputNode.removeTap(onBus: 0)
            hasInstalledInputTap = false
        }

        PronunciationAudioTap.install(on: inputNode, bus: 0, format: format, request: request)
        hasInstalledInputTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stopAudio()
            throw error
        }

        state = .listening
        message = "Speak now. The cat is listening."

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finish(targetWord: targetWord)
                    }
                }

                if error != nil, self.state == .listening {
                    self.finish(targetWord: targetWord)
                }
            }
        }

        autoStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                self?.finish(targetWord: targetWord)
            }
        }
    }

    private func stopAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledInputTap = false
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    private func feedbackMessage(for rating: PronunciationRating?) -> String {
        switch rating {
        case .clear:
            return "Great pronunciation. The cat is happy."
        case .almostThere:
            return "Almost there. Try once more or continue with a reminder."
        case .needsPractice:
            return "The cat could not hear it clearly yet. Try again, or continue and review later."
        case nil:
            return "The cat could not check this attempt. Try again or self-check below."
        }
    }
}

private enum PronunciationSpeechError: Error {
    case recognizerUnavailable
    case inputFormatUnavailable
}
