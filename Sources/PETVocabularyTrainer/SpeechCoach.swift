import AVFoundation
import Foundation

enum SpeechLanguageHint: String, Hashable, Sendable {
    case english
    case chinese
    case automatic
}

@MainActor
final class SpeechCoach {
    static let shared = SpeechCoach()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(_ text: String, language: SpeechLanguageHint) {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.rate = 0.45
        utterance.pitchMultiplier = 1.02
        utterance.voice = preferredVoice(for: cleaned, language: language)
        synthesizer.speak(utterance)
    }

    private func preferredVoice(for text: String, language: SpeechLanguageHint) -> AVSpeechSynthesisVoice? {
        switch language {
        case .english:
            return AVSpeechSynthesisVoice(language: "en-US")
        case .chinese:
            return AVSpeechSynthesisVoice(language: "zh-CN")
        case .automatic:
            return AVSpeechSynthesisVoice(language: containsCJK(text) ? "zh-CN" : "en-US")
        }
    }

    private func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF:
                return true
            default:
                return false
            }
        }
    }
}
