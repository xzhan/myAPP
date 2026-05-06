import AVFoundation
import AppKit
import Combine
import Foundation
import Speech

enum PronunciationPermissionStatus: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case unavailable

    var isAuthorized: Bool {
        self == .authorized
    }
}

struct PronunciationPermissionRecovery: Equatable {
    let title: String
    let detail: String
    let settingsURL: URL
}

struct PronunciationPermissionProvider {
    var requestSpeechAuthorization: @Sendable () async -> PronunciationPermissionStatus
    var requestMicrophoneAuthorization: @Sendable () async -> PronunciationPermissionStatus

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
    nonisolated static func requestSpeechAuthorization() async -> PronunciationPermissionStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized:
                    continuation.resume(returning: .authorized)
                case .denied:
                    continuation.resume(returning: .denied)
                case .restricted:
                    continuation.resume(returning: .restricted)
                case .notDetermined:
                    continuation.resume(returning: .unavailable)
                @unknown default:
                    continuation.resume(returning: .unavailable)
                }
            }
        }
    }

    nonisolated static func requestMicrophoneAuthorization() async -> PronunciationPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { isAllowed in
                    continuation.resume(returning: isAllowed ? .authorized : .denied)
                }
            }
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unavailable
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
    @Published private(set) var permissionRecovery: PronunciationPermissionRecovery?
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
            let speechStatus = await permissionProvider.requestSpeechAuthorization()
            let microphoneStatus = await permissionProvider.requestMicrophoneAuthorization()

            guard speechStatus.isAuthorized, microphoneStatus.isAuthorized else {
                configureUnavailablePermissionState(speechStatus: speechStatus, microphoneStatus: microphoneStatus)
                return
            }

            permissionRecovery = nil

            do {
                try startRecognition(targetWord: targetWord)
            } catch {
                state = .unavailable
                permissionRecovery = nil
                message = "Speech check could not start. You can still self-check below."
                return
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
        permissionRecovery = nil
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
        permissionRecovery = nil
    }

    func openPermissionSettings() {
        guard let permissionRecovery else { return }
        NSWorkspace.shared.open(permissionRecovery.settingsURL)
    }

    private func configureUnavailablePermissionState(
        speechStatus: PronunciationPermissionStatus,
        microphoneStatus: PronunciationPermissionStatus
    ) {
        state = .unavailable

        if microphoneStatus == .denied || microphoneStatus == .restricted {
            permissionRecovery = PronunciationPermissionRecovery(
                title: "Open Microphone Settings",
                detail: "Turn on PETVocabularyTrainer in System Settings > Privacy & Security > Microphone, then return here and tap Check Again.",
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            )
            message = "Microphone access is off. Open System Settings to allow it, then come back and try again."
            return
        }

        if speechStatus == .denied || speechStatus == .restricted {
            permissionRecovery = PronunciationPermissionRecovery(
                title: "Open Speech Recognition Settings",
                detail: "Turn on PETVocabularyTrainer in System Settings > Privacy & Security > Speech Recognition, then return here and tap Check Again.",
                settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
            )
            message = "Speech Recognition access is off. Open System Settings to allow it, then come back and try again."
            return
        }

        permissionRecovery = nil
        message = "Microphone or speech permission is not available. You can still self-check below."
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
            return "Great! Cat heard the word clearly."
        case .almostThere:
            return "Nice! Cat almost heard it. Let's keep going."
        case .needsPractice:
            return "Cat did not hear it clearly. Maybe the mic missed it. Try once more."
        case nil:
            return "The cat could not check this attempt. Try again or self-check below."
        }
    }
}

private enum PronunciationSpeechError: Error {
    case recognizerUnavailable
    case inputFormatUnavailable
}
