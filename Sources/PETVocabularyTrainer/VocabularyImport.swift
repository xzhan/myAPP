import Foundation
import PDFKit

struct ImportedWordLibrary: Hashable, Sendable {
    let words: [VocabularyWord]
    let metadata: WordLibraryMetadata
    let wordPages: [ImportedWordPage]
    let questPages: [QuestPage]
}

struct ImportedQuestOverlay: Hashable, Sendable {
    let words: [VocabularyWord]
    let questPages: [QuestPage]
    let sourceFilename: String
}

struct ImportedReadingLibrary: Hashable, Sendable {
    let quests: [ReadingQuest]
    let metadata: ReadingLibraryMetadata
}

struct ImportedWordEntry: Hashable, Sendable {
    let english: String
    let primaryChinese: String
    let topic: WordTopic?
}

enum VocabularyImportError: LocalizedError, Sendable {
    case unsupportedFileType(String)
    case unreadablePDF
    case invalidJSON
    case invalidTextFormat
    case noWordsFound
    case tooFewWords(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let type):
            return "This importer does not support \(type) yet. Try PDF, CSV, TXT, or JSON."
        case .unreadablePDF:
            return "The PDF could not be read. Make sure it contains selectable text."
        case .invalidJSON:
            return "The JSON file does not match the expected vocabulary format."
        case .invalidTextFormat:
            return "The text file could not be parsed into English and Chinese word pairs."
        case .noWordsFound:
            return "No vocabulary entries were found in that file."
        case .tooFewWords(let count):
            return "Only \(count) words were found. Import a larger PET word bank before starting placement."
        }
    }
}

enum ReadingImportError: LocalizedError, Sendable {
    case unsupportedFileType(String)
    case unreadablePDF(String)
    case noSupportedFilesFound
    case invalidReadingFormat(String)
    case noReadingQuestsFound

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let type):
            return "Reading import supports `.txt` and `.pdf` files, or folders that contain those files. `\(type)` is not supported."
        case .unreadablePDF(let filename):
            return "\(filename) could not be read as selectable PDF text."
        case .noSupportedFilesFound:
            return "No supported `.txt` or `.pdf` reading files were found in that selection."
        case .invalidReadingFormat(let filename):
            return "\(filename) does not match the expected Reading Quest text format."
        case .noReadingQuestsFound:
            return "No reading quests could be imported from that selection."
        }
    }
}

enum VocabularyImportService {
    static func isQuestOverlayFile(at url: URL) -> Bool {
        guard importedSource(for: url) == .json || importedSource(for: url) == .questJSON,
              let data = try? Data(contentsOf: url) else {
            return false
        }
        return (try? QuestJSONParser.parse(data: data)) != nil
    }

    static func importWordLibrary(from url: URL, seedWords: [VocabularyWord]) throws -> ImportedWordLibrary {
        let source = importedSource(for: url)
        let importedEntries: [ImportedWordEntry]
        let wordPages: [ImportedWordPage]
        let questPages: [QuestPage]

        switch source {
        case .pdf:
            let parsedPDF = try PETPDFPageParser.parse(documentAt: url)
            importedEntries = parsedPDF.entries
            let words = finalizeWords(from: importedEntries, seedWords: seedWords)
            guard !words.isEmpty else {
                throw VocabularyImportError.noWordsFound
            }
            guard words.count >= 100 else {
                throw VocabularyImportError.tooFewWords(words.count)
            }

            let wordsByEnglishKey = Dictionary(grouping: words, by: { normalizeEnglishKey($0.english) })
            let builtWordPages = buildWordPages(
                from: parsedPDF.pages,
                wordsByEnglishKey: wordsByEnglishKey,
                sourceFilename: url.lastPathComponent
            )

            return ImportedWordLibrary(
                words: words,
                metadata: WordLibraryMetadata(
                    name: url.deletingPathExtension().lastPathComponent,
                    sourceFilename: url.lastPathComponent,
                    importedAt: .now,
                    wordCount: words.count,
                    source: .pdf
                ),
                wordPages: builtWordPages,
                questPages: []
            )
        case .json, .questJSON:
            let data = try Data(contentsOf: url)
            if let parsedQuest = try? QuestJSONParser.parse(data: data) {
                let words = finalizeWords(from: parsedQuest.entries, seedWords: seedWords)
                guard !words.isEmpty else {
                    throw VocabularyImportError.noWordsFound
                }

                let wordsByEnglishKey = Dictionary(grouping: words, by: { normalizeEnglishKey($0.english) })
                let pages = buildQuestPages(from: parsedQuest.pages, wordsByEnglishKey: wordsByEnglishKey)
                guard !pages.isEmpty else {
                    throw VocabularyImportError.invalidJSON
                }

                return ImportedWordLibrary(
                    words: words,
                    metadata: WordLibraryMetadata(
                        name: url.deletingPathExtension().lastPathComponent,
                        sourceFilename: url.lastPathComponent,
                        importedAt: .now,
                        wordCount: words.count,
                        source: .questJSON
                    ),
                    wordPages: [],
                    questPages: pages
                )
            }

            importedEntries = try JSONVocabularyParser.parse(data: data)
            wordPages = []
            questPages = []
        case .csv:
            let text = try String(contentsOf: url, encoding: .utf8)
            importedEntries = try DelimitedVocabularyParser.parse(text: text)
            wordPages = []
            questPages = []
        case .plainText:
            let text = try String(contentsOf: url, encoding: .utf8)
            importedEntries = try DelimitedVocabularyParser.parse(text: text)
            wordPages = []
            questPages = []
        }

        guard !importedEntries.isEmpty else {
            throw VocabularyImportError.noWordsFound
        }

        let words = finalizeWords(from: importedEntries, seedWords: seedWords)
        guard !words.isEmpty else {
            throw VocabularyImportError.noWordsFound
        }
        guard words.count >= 100 else {
            throw VocabularyImportError.tooFewWords(words.count)
        }

        return ImportedWordLibrary(
            words: words,
            metadata: WordLibraryMetadata(
                name: url.deletingPathExtension().lastPathComponent,
                sourceFilename: url.lastPathComponent,
                importedAt: .now,
                wordCount: words.count,
                source: source
            ),
            wordPages: wordPages,
            questPages: questPages
        )
    }

    static func importQuestOverlay(
        from url: URL,
        existingWords: [VocabularyWord],
        seedWords: [VocabularyWord]
    ) throws -> ImportedQuestOverlay {
        let data = try Data(contentsOf: url)
        let parsedQuest = try QuestJSONParser.parse(data: data)
        let mergedWords = appendMissingWords(
            from: parsedQuest.entries,
            to: existingWords,
            seedWords: seedWords
        )
        let wordsByEnglishKey = Dictionary(grouping: mergedWords, by: { normalizeEnglishKey($0.english) })
        let pages = buildQuestPages(from: parsedQuest.pages, wordsByEnglishKey: wordsByEnglishKey)
        guard !pages.isEmpty else {
            throw VocabularyImportError.invalidJSON
        }

        return ImportedQuestOverlay(
            words: mergedWords,
            questPages: pages,
            sourceFilename: url.lastPathComponent
        )
    }

    private static func importedSource(for url: URL) -> ImportedWordLibrarySource {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return .pdf
        case "json":
            return .json
        case "csv":
            return .csv
        case "txt", "tsv":
            return .plainText
        default:
            return .plainText
        }
    }

    private static func finalizeWords(from entries: [ImportedWordEntry], seedWords: [VocabularyWord]) -> [VocabularyWord] {
        let topicMap = makeTopicMap(from: seedWords)
        let mergedEntries = mergeExactEnglishDuplicates(entries)
        var slugCounts: [String: Int] = [:]

        return mergedEntries.map { entry in
            let baseSlug = slug(from: entry.english)
            let nextCount = (slugCounts[baseSlug] ?? 0) + 1
            slugCounts[baseSlug] = nextCount

            let topic = entry.topic ?? ImportedWordTopicClassifier.classify(
                english: entry.english,
                chinese: entry.primaryChinese,
                seedTopicByEnglishKey: topicMap
            )

            return VocabularyWord(
                id: nextCount == 1 ? baseSlug : "\(baseSlug)-\(nextCount)",
                english: entry.english,
                primaryChinese: entry.primaryChinese,
                topic: topic
            )
        }
    }

    private static func buildQuestPages(
        from pages: [QuestJSONParser.ParsedQuestPage],
        wordsByEnglishKey: [String: [VocabularyWord]]
    ) -> [QuestPage] {
        pages.compactMap { page in
            let questions = page.bundles.compactMap { bundle -> PersistedQuestion? in
                guard let wordID = matchedWordID(for: bundle, wordsByEnglishKey: wordsByEnglishKey) else {
                    return nil
                }

                return PersistedQuestion(
                    wordID: wordID,
                    choices: bundle.meaningOptions,
                    style: .wordExercise,
                    exampleSentence: bundle.exampleSentence,
                    meaningPrompt: bundle.meaningPrompt,
                    meaningCorrectChoice: bundle.meaningCorrectChoice,
                    spellingPromptText: bundle.spellingPromptText,
                    spellingCorrectAnswer: bundle.spellingCorrectAnswer,
                    translationPrompt: bundle.translationPrompt,
                    translationChoices: bundle.translationChoices,
                    translationCorrectChoice: bundle.translationCorrectChoice,
                    memoryTip: bundle.memoryTip,
                    exampleTranslation: bundle.exampleTranslation,
                    sourcePageNumber: page.pageNumber,
                    sourcePageTitle: page.title
                )
            }

            guard !questions.isEmpty else {
                return nil
            }

            return QuestPage(
                pageNumber: page.pageNumber,
                title: page.title,
                questions: questions
            )
        }
    }

    private static func buildWordPages(
        from pages: [PETPDFPageParser.ParsedWordPage],
        wordsByEnglishKey: [String: [VocabularyWord]],
        sourceFilename: String
    ) -> [ImportedWordPage] {
        pages.compactMap { page in
            let wordIDs = page.entries.compactMap { matchedWordID(for: $0, wordsByEnglishKey: wordsByEnglishKey) }
                .reduce(into: [String]()) { partialResult, wordID in
                    if !partialResult.contains(wordID) {
                        partialResult.append(wordID)
                    }
                }

            guard !wordIDs.isEmpty else {
                return nil
            }

            return ImportedWordPage(
                pageNumber: page.pageNumber,
                title: page.title,
                wordIDs: wordIDs,
                sourceFilename: sourceFilename
            )
        }
    }

    private static func matchedWordID(
        for bundle: QuestJSONParser.ParsedQuestBundle,
        wordsByEnglishKey: [String: [VocabularyWord]]
    ) -> String? {
        matchedWordID(
            english: bundle.word,
            meaning: bundle.meaning,
            wordsByEnglishKey: wordsByEnglishKey
        )
    }

    private static func matchedWordID(
        for entry: ImportedWordEntry,
        wordsByEnglishKey: [String: [VocabularyWord]]
    ) -> String? {
        matchedWordID(
            english: entry.english,
            meaning: entry.primaryChinese,
            wordsByEnglishKey: wordsByEnglishKey
        )
    }

    private static func matchedWordID(
        english: String,
        meaning: String,
        wordsByEnglishKey: [String: [VocabularyWord]]
    ) -> String? {
        let candidates = wordsByEnglishKey[normalizeEnglishKey(english)] ?? []
        guard !candidates.isEmpty else { return nil }

        let bundleMeaning = normalizeMeaningKey(meaning)
        if let match = candidates.first(where: { candidate in
            let candidateMeaning = normalizeMeaningKey(candidate.primaryChinese)
            return candidateMeaning == bundleMeaning
                || candidateMeaning.contains(bundleMeaning)
                || bundleMeaning.contains(candidateMeaning)
        }) {
            return match.id
        }

        return candidates.first?.id
    }

    private static func appendMissingWords(
        from entries: [ImportedWordEntry],
        to existingWords: [VocabularyWord],
        seedWords: [VocabularyWord]
    ) -> [VocabularyWord] {
        let mergedEntries = mergeExactEnglishDuplicates(entries)
        let wordsByEnglishKey = Dictionary(grouping: existingWords, by: { normalizeEnglishKey($0.english) })
        let missingEntries = mergedEntries.filter { entry in
            matchedWordID(for: entry, wordsByEnglishKey: wordsByEnglishKey) == nil
        }
        guard !missingEntries.isEmpty else {
            return existingWords
        }

        let topicMap = makeTopicMap(from: seedWords + existingWords)
        var usedIDs = Set(existingWords.map(\.id))
        var appendedWords: [VocabularyWord] = []

        for entry in missingEntries {
            let topic = entry.topic ?? ImportedWordTopicClassifier.classify(
                english: entry.english,
                chinese: entry.primaryChinese,
                seedTopicByEnglishKey: topicMap
            )
            let baseSlug = slug(from: entry.english)
            let wordID = nextAvailableWordID(baseSlug: baseSlug, usedIDs: &usedIDs)
            appendedWords.append(
                VocabularyWord(
                    id: wordID,
                    english: entry.english,
                    primaryChinese: entry.primaryChinese,
                    topic: topic
                )
            )
        }

        return existingWords + appendedWords
    }

    private static func makeTopicMap(from words: [VocabularyWord]) -> [String: WordTopic] {
        var topicMap: [String: WordTopic] = [:]

        for word in words {
            let key = normalizeEnglishKey(word.english)
            if topicMap[key] == nil {
                topicMap[key] = word.topic
            }
        }

        return topicMap
    }

    private static func nextAvailableWordID(baseSlug: String, usedIDs: inout Set<String>) -> String {
        if usedIDs.insert(baseSlug).inserted {
            return baseSlug
        }

        var suffix = 2
        while true {
            let candidate = "\(baseSlug)-\(suffix)"
            if usedIDs.insert(candidate).inserted {
                return candidate
            }
            suffix += 1
        }
    }

    private static func mergeExactEnglishDuplicates(_ entries: [ImportedWordEntry]) -> [ImportedWordEntry] {
        var orderedEnglish: [String] = []
        var mergedByEnglish: [String: ImportedWordEntry] = [:]

        for entry in entries {
            if let existing = mergedByEnglish[entry.english] {
                let combinedChinese = mergeChinese(existing.primaryChinese, entry.primaryChinese)
                mergedByEnglish[entry.english] = ImportedWordEntry(
                    english: existing.english,
                    primaryChinese: combinedChinese,
                    topic: existing.topic ?? entry.topic
                )
            } else {
                orderedEnglish.append(entry.english)
                mergedByEnglish[entry.english] = entry
            }
        }

        return orderedEnglish.compactMap { mergedByEnglish[$0] }
    }

    private static func mergeChinese(_ lhs: String, _ rhs: String) -> String {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)

        if left == right {
            return left
        }
        if left.contains(right) {
            return left
        }
        if right.contains(left) {
            return right
        }

        return "\(left)；\(right)"
    }

    private static func normalizeEnglishKey(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private static func normalizeMeaningKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private static func slug(from value: String) -> String {
        let lowered = value.lowercased()
        let replaced = lowered.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        let collapsed = String(replaced)
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return collapsed.isEmpty ? UUID().uuidString.lowercased() : collapsed
    }
}

private enum PETPDFPageParser {
    struct ParsedWordPage {
        let pageNumber: Int
        let title: String
        let entries: [ImportedWordEntry]
    }

    struct ParsedPDFImport {
        let entries: [ImportedWordEntry]
        let pages: [ParsedWordPage]
    }

    static func parse(documentAt url: URL) throws -> ParsedPDFImport {
        guard let document = PDFDocument(url: url) else {
            throw VocabularyImportError.unreadablePDF
        }

        var allEntries: [ImportedWordEntry] = []
        var pages: [ParsedWordPage] = []
        let fileStem = url.deletingPathExtension().lastPathComponent

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let rawText = page.string?.replacingOccurrences(of: "\r", with: "\n") else {
                continue
            }

            let entries = try PETPDFWordParser.parse(text: rawText)
            guard !entries.isEmpty else {
                continue
            }

            let pageNumber = extractPageNumber(from: rawText) ?? (pageIndex + 1)
            let title = "\(fileStem)_Page_\(pageNumber)"
            allEntries.append(contentsOf: entries)
            pages.append(
                ParsedWordPage(
                    pageNumber: pageNumber,
                    title: title,
                    entries: entries
                )
            )
        }

        guard !allEntries.isEmpty else {
            throw VocabularyImportError.noWordsFound
        }

        return ParsedPDFImport(entries: allEntries, pages: pages.sorted { $0.pageNumber < $1.pageNumber })
    }

    private static func extractPageNumber(from text: String) -> Int? {
        let pattern = #"第(\d+)关"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[range])
    }
}

private enum QuestJSONParser {
    struct ParsedQuestBundle {
        let word: String
        let meaningPrompt: String
        let meaningOptions: [String]
        let meaningCorrectChoice: String
        let spellingPromptText: String
        let spellingCorrectAnswer: String
        let translationPrompt: String?
        let translationChoices: [String]
        let translationCorrectChoice: String?
        let exampleSentence: String?
        let exampleTranslation: String?
        let memoryTip: String?
        let meaning: String
    }

    struct ParsedQuestPage {
        let pageNumber: Int
        let title: String
        let bundles: [ParsedQuestBundle]
    }

    struct ParsedQuestImport {
        let entries: [ImportedWordEntry]
        let pages: [ParsedQuestPage]
    }

    private struct RawQuestFile: Decodable {
        let vocabQuestVersion: Int?
        let exportType: String?
        let sessions: [RawQuestSession]
    }

    private struct RawQuestSession: Decodable {
        let id: String?
        let title: String
        let questions: [RawQuestQuestion]
        let originalVocab: [RawQuestVocab]?

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case questions
            case originalVocab
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            questions = try container.decode([RawQuestQuestion].self, forKey: .questions)
            originalVocab = try container.decodeIfPresent([RawQuestVocab].self, forKey: .originalVocab)
        }
    }

    private struct RawQuestVocab: Decodable {
        let id: String?
        let word: String
        let meaning: String
        let example: String?
        let exampleTranslation: String?
    }

    private struct RawQuestQuestion: Decodable {
        let id: String?
        let type: String
        let question: String
        let options: [String]?
        let correctAnswer: String?
        let explanation: String?
        let memoryTip: String?
        let word: String?
        let meaning: String?
        let example: String?
        let exampleTranslation: String?
    }

    static func parse(data: Data) throws -> ParsedQuestImport {
        let decoder = JSONDecoder()
        guard let file = try? decoder.decode(RawQuestFile.self, from: data),
              file.exportType == "quests" || !file.sessions.isEmpty else {
            throw VocabularyImportError.invalidJSON
        }

        var allEntries: [ImportedWordEntry] = []
        var pagesByNumber: [Int: ParsedQuestPage] = [:]

        for session in file.sessions {
            guard let pageNumber = extractPageNumber(from: session.title) else { continue }

            let bundles = buildBundles(from: session)
            guard !bundles.isEmpty else { continue }

            if let originalVocab = session.originalVocab, !originalVocab.isEmpty {
                allEntries.append(contentsOf: originalVocab.map {
                    ImportedWordEntry(english: $0.word, primaryChinese: $0.meaning, topic: nil)
                })
            } else {
                allEntries.append(contentsOf: bundles.map {
                    ImportedWordEntry(english: $0.word, primaryChinese: $0.meaning, topic: nil)
                })
            }

            let candidatePage = ParsedQuestPage(pageNumber: pageNumber, title: session.title, bundles: bundles)
            if let existing = pagesByNumber[pageNumber] {
                if candidatePage.bundles.count > existing.bundles.count {
                    pagesByNumber[pageNumber] = candidatePage
                }
            } else {
                pagesByNumber[pageNumber] = candidatePage
            }
        }

        let pages = pagesByNumber.values.sorted { $0.pageNumber < $1.pageNumber }
        guard !pages.isEmpty else {
            throw VocabularyImportError.invalidJSON
        }

        return ParsedQuestImport(entries: allEntries, pages: pages)
    }

    private static func buildBundles(from session: RawQuestSession) -> [ParsedQuestBundle] {
        var orderedWords: [String] = []
        var questionsByWord: [String: [RawQuestQuestion]] = [:]
        let originalVocabByWord = mergeOriginalVocabByWord(session.originalVocab ?? [])

        for question in session.questions {
            guard let rawWord = question.word?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawWord.isEmpty else {
                continue
            }

            let key = normalizeWordKey(rawWord)
            if questionsByWord[key] == nil {
                orderedWords.append(key)
            }
            questionsByWord[key, default: []].append(question)
        }

        return orderedWords.compactMap { key in
            guard let groupedQuestions = questionsByWord[key], !groupedQuestions.isEmpty else {
                return nil
            }

            let multipleChoice = groupedQuestions.first { $0.type == "multiple_choice" }
            let fillInBlank = groupedQuestions.first { $0.type == "fill_in_blank" }
            let sentenceTranslation = groupedQuestions.first { $0.type == "sentence_translation" }
            let rawWord = multipleChoice?.word ?? fillInBlank?.word ?? sentenceTranslation?.word ?? originalVocabByWord[key]?.word
            let meaning = multipleChoice?.meaning ?? fillInBlank?.meaning ?? sentenceTranslation?.meaning ?? originalVocabByWord[key]?.meaning

            guard let word = rawWord?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let finalMeaning = meaning?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !word.isEmpty,
                  !finalMeaning.isEmpty else {
                return nil
            }

            let exampleSentence = multipleChoice?.example ?? fillInBlank?.example ?? sentenceTranslation?.example ?? originalVocabByWord[key]?.example
            let exampleTranslation = multipleChoice?.exampleTranslation ?? fillInBlank?.exampleTranslation ?? sentenceTranslation?.exampleTranslation ?? originalVocabByWord[key]?.exampleTranslation
            let meaningPrompt = normalizedPrompt(multipleChoice?.question) ?? exampleSentence ?? word
            let meaningOptions = (multipleChoice?.options ?? [finalMeaning]).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let meaningCorrectChoice = normalizedPrompt(multipleChoice?.correctAnswer) ?? finalMeaning
            let spellingPromptText = normalizedPrompt(fillInBlank?.question) ?? "\(finalMeaning): ___"
            let spellingCorrectAnswer = normalizedPrompt(fillInBlank?.correctAnswer) ?? word
            let translationPrompt = normalizedPrompt(sentenceTranslation?.question)
            let translationChoices = sentenceTranslation?.options?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
            let translationCorrectChoice = normalizedPrompt(sentenceTranslation?.correctAnswer)
            let memoryTip = normalizedPrompt(multipleChoice?.memoryTip)
                ?? normalizedPrompt(fillInBlank?.memoryTip)
                ?? normalizedPrompt(sentenceTranslation?.memoryTip)

            return ParsedQuestBundle(
                word: word,
                meaningPrompt: meaningPrompt,
                meaningOptions: meaningOptions,
                meaningCorrectChoice: meaningCorrectChoice,
                spellingPromptText: spellingPromptText,
                spellingCorrectAnswer: spellingCorrectAnswer,
                translationPrompt: translationPrompt,
                translationChoices: translationChoices,
                translationCorrectChoice: translationCorrectChoice,
                exampleSentence: normalizedPrompt(exampleSentence),
                exampleTranslation: normalizedPrompt(exampleTranslation),
                memoryTip: memoryTip,
                meaning: finalMeaning
            )
        }
    }

    private static func extractPageNumber(from title: String) -> Int? {
        let pattern = #"Page[_ ](\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else {
            return nil
        }
        return Int(title[range])
    }

    private static func normalizeWordKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private static func normalizedPrompt(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func mergeOriginalVocabByWord(_ entries: [RawQuestVocab]) -> [String: RawQuestVocab] {
        var merged: [String: RawQuestVocab] = [:]

        for entry in entries {
            let key = normalizeWordKey(entry.word)
            if let existing = merged[key] {
                merged[key] = mergedOriginalVocab(existing, entry)
            } else {
                merged[key] = entry
            }
        }

        return merged
    }

    private static func mergedOriginalVocab(_ lhs: RawQuestVocab, _ rhs: RawQuestVocab) -> RawQuestVocab {
        RawQuestVocab(
            id: preferredNonEmpty(lhs.id, rhs.id),
            word: preferredLongerText(lhs.word, rhs.word) ?? lhs.word,
            meaning: preferredLongerText(lhs.meaning, rhs.meaning) ?? lhs.meaning,
            example: preferredLongerText(lhs.example, rhs.example),
            exampleTranslation: preferredLongerText(lhs.exampleTranslation, rhs.exampleTranslation)
        )
    }

    private static func preferredNonEmpty(_ lhs: String?, _ rhs: String?) -> String? {
        let left = normalizedPrompt(lhs)
        let right = normalizedPrompt(rhs)
        return left ?? right
    }

    private static func preferredLongerText(_ lhs: String?, _ rhs: String?) -> String? {
        let left = normalizedPrompt(lhs)
        let right = normalizedPrompt(rhs)

        switch (left, right) {
        case let (left?, right?):
            if left == right {
                return left
            }
            return right.count > left.count ? right : left
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        case (nil, nil):
            return nil
        }
    }
}

private enum PDFVocabularyTextExtractor {
    static func extractText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw VocabularyImportError.unreadablePDF
        }

        let allPages = (0..<document.pageCount).compactMap { index in
            document.page(at: index)?.string?.replacingOccurrences(of: "\r", with: "")
        }

        let joined = allPages.joined(separator: "\n")
        guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VocabularyImportError.unreadablePDF
        }

        return joined
    }
}

enum ReadingImportService {
    static func importReadingLibrary(from urls: [URL]) throws -> ImportedReadingLibrary {
        let sourceFiles = try collectSourceFiles(from: urls)
        guard !sourceFiles.isEmpty else {
            throw ReadingImportError.noSupportedFilesFound
        }

        var questsByKey: [String: ReadingQuest] = [:]

        for fileURL in sourceFiles {
            let importedQuests: [ReadingQuest]

            switch fileURL.pathExtension.lowercased() {
            case "txt":
                let text = try String(contentsOf: fileURL, encoding: .utf8)
                importedQuests = [try ReadingTXTParser.parse(text: text, sourceFilename: fileURL.lastPathComponent)]
            case "pdf":
                importedQuests = try ReadingPDFParser.parse(documentAt: fileURL)
            default:
                throw ReadingImportError.unsupportedFileType(fileURL.pathExtension)
            }

            for quest in importedQuests {
                let key = readingQuestKey(for: quest)
                if let existingQuest = questsByKey[key] {
                    questsByKey[key] = preferredQuest(existingQuest, quest)
                } else {
                    questsByKey[key] = quest
                }
            }
        }

        let quests = questsByKey.values.sorted(by: readingQuestOrder(lhs:rhs:))
        guard !quests.isEmpty else {
            throw ReadingImportError.noReadingQuestsFound
        }

        let rootName: String
        if urls.count == 1 {
            rootName = urls[0].deletingPathExtension().lastPathComponent
        } else {
            rootName = "Reading Pack"
        }

        return ImportedReadingLibrary(
            quests: quests,
            metadata: ReadingLibraryMetadata(
                name: rootName,
                importedAt: .now,
                articleCount: quests.count
            )
        )
    }

    private static func collectSourceFiles(from urls: [URL]) throws -> [URL] {
        let fileManager = FileManager.default
        var collected: [URL] = []

        for url in urls {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )

                while let nestedURL = enumerator?.nextObject() as? URL {
                    let ext = nestedURL.pathExtension.lowercased()
                    guard ext == "txt" || ext == "pdf" else { continue }
                    collected.append(nestedURL)
                }
                continue
            }

            let ext = url.pathExtension.lowercased()
            guard ext == "txt" || ext == "pdf" else {
                throw ReadingImportError.unsupportedFileType(url.pathExtension)
            }
            collected.append(url)
        }

        return collected.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private static func readingQuestKey(for quest: ReadingQuest) -> String {
        if let pageNumber = quest.pageNumber {
            return "page-\(pageNumber)"
        }
        return "id-\(quest.id)"
    }

    private static func preferredQuest(_ lhs: ReadingQuest, _ rhs: ReadingQuest) -> ReadingQuest {
        let leftScore = questRichnessScore(lhs)
        let rightScore = questRichnessScore(rhs)
        if rightScore != leftScore {
            return rightScore > leftScore ? rhs : lhs
        }

        return rhs.passage.count > lhs.passage.count ? rhs : lhs
    }

    private static func questRichnessScore(_ quest: ReadingQuest) -> Int {
        var score = quest.questionCount * 10
        if quest.isQuizReady { score += 100 }
        if quest.pageNumber != nil { score += 5 }
        return score
    }

    private static func readingQuestOrder(lhs: ReadingQuest, rhs: ReadingQuest) -> Bool {
        switch (lhs.pageNumber, rhs.pageNumber) {
        case let (left?, right?):
            if left != right { return left < right }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

private enum ReadingPDFParser {
    static func parse(documentAt url: URL) throws -> [ReadingQuest] {
        guard let document = PDFDocument(url: url) else {
            throw ReadingImportError.unreadablePDF(url.lastPathComponent)
        }

        var quests: [ReadingQuest] = []
        let fileStem = url.deletingPathExtension().lastPathComponent

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let rawText = page.string?.replacingOccurrences(of: "\r", with: "\n") else {
                continue
            }

            let normalizedText = normalizePDFPageText(rawText)
            guard !normalizedText.isEmpty else { continue }

            if let structuredQuest = try? ReadingTXTParser.parse(text: normalizedText, sourceFilename: url.lastPathComponent) {
                quests.append(
                    ReadingQuest(
                        id: structuredQuest.id,
                        title: structuredQuest.title,
                        pageNumber: structuredQuest.pageNumber ?? (pageIndex + 1),
                        passage: structuredQuest.passage,
                        questions: structuredQuest.questions,
                        sourceFilename: url.lastPathComponent
                    )
                )
                continue
            }

            let pageNumber = pageIndex + 1
            let title = "\(fileStem)_Page_\(pageNumber)"
            quests.append(
                ReadingQuest(
                    id: "\(ReadingTXTParser.readingSlug(from: title))-\(pageNumber)",
                    title: title,
                    pageNumber: pageNumber,
                    passage: normalizedText,
                    questions: [],
                    sourceFilename: url.lastPathComponent
                )
            )
        }

        guard !quests.isEmpty else {
            throw ReadingImportError.unreadablePDF(url.lastPathComponent)
        }

        return quests
    }

    private static func normalizePDFPageText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum ReadingTXTParser {
    static func parse(text: String, sourceFilename: String) throws -> ReadingQuest {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let title = try parseTitle(from: normalized, sourceFilename: sourceFilename)
        let passage = try sectionBody(marker: "--- READING PASSAGE ---", in: normalized, sourceFilename: sourceFilename)
        let questionsBlock = try questionsSection(in: normalized, sourceFilename: sourceFilename)
        let answersByNumber = parseAnswerMap(from: normalized)
        let questions = try parseQuestions(from: questionsBlock, answersByNumber: answersByNumber, sourceFilename: sourceFilename)

        return ReadingQuest(
            id: readingSlug(from: title),
            title: title,
            pageNumber: readingPageNumber(from: title),
            passage: passage,
            questions: questions,
            sourceFilename: sourceFilename
        )
    }

    private static func parseTitle(from text: String, sourceFilename: String) throws -> String {
        guard let titleLine = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            throw ReadingImportError.invalidReadingFormat(sourceFilename)
        }

        let prefix = "Reading Quest:"
        guard titleLine.hasPrefix(prefix) else {
            throw ReadingImportError.invalidReadingFormat(sourceFilename)
        }

        let title = titleLine.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw ReadingImportError.invalidReadingFormat(sourceFilename)
        }

        return title
    }

    private static func questionsSection(in text: String, sourceFilename: String) throws -> String {
        let marker = "--- QUESTIONS ---"
        guard let markerRange = text.range(of: marker) else {
            throw ReadingImportError.invalidReadingFormat(sourceFilename)
        }

        let questionsStart = markerRange.upperBound
        let answersMarker = "--- ANSWERS ---"
        let questionsEnd = text[questionsStart...].range(of: answersMarker)?.lowerBound ?? text.endIndex
        let block = text[questionsStart..<questionsEnd].trimmingCharacters(in: .whitespacesAndNewlines)

        guard !block.isEmpty else {
            throw ReadingImportError.invalidReadingFormat(sourceFilename)
        }

        return block
    }

    private static func sectionBody(marker: String, in text: String, sourceFilename: String) throws -> String {
        guard let markerRange = text.range(of: marker) else {
            throw ReadingImportError.invalidReadingFormat(sourceFilename)
        }

        let sectionStart = markerRange.upperBound
        let nextMarker = "--- QUESTIONS ---"
        let sectionEnd = text[sectionStart...].range(of: nextMarker)?.lowerBound ?? text.endIndex
        let body = text[sectionStart..<sectionEnd].trimmingCharacters(in: .whitespacesAndNewlines)

        guard !body.isEmpty else {
            throw ReadingImportError.invalidReadingFormat(sourceFilename)
        }

        return body
    }

    private static func parseQuestions(
        from block: String,
        answersByNumber: [Int: String],
        sourceFilename: String
    ) throws -> [ReadingQuestQuestion] {
        let questionPattern = try NSRegularExpression(pattern: #"^\s*(\d+)\.\s+(.+)$"#)
        let optionPattern = try NSRegularExpression(pattern: #"^\s*([A-Z])\)\s+(.+)$"#)
        let inlineAnswerPattern = try NSRegularExpression(pattern: #"^\s*Answer\s*:\s*([A-Z])\s*$"#, options: [.caseInsensitive])

        struct DraftQuestion {
            var number: Int
            var prompt: String
            var choices: [ReadingQuestChoice]
            var inlineAnswer: String?
        }

        func match(_ regex: NSRegularExpression, in line: String) -> NSTextCheckingResult? {
            regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
        }

        func substring(_ line: String, match: NSTextCheckingResult, group: Int) -> String? {
            guard let range = Range(match.range(at: group), in: line) else { return nil }
            return String(line[range])
        }

        func appendDraft(_ draft: DraftQuestion?, to questions: inout [ReadingQuestQuestion]) throws {
            guard let draft else { return }
            guard !draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  draft.choices.count >= 2 else {
                throw ReadingImportError.invalidReadingFormat(sourceFilename)
            }

            let answerLetter = draft.inlineAnswer?.uppercased() ?? answersByNumber[draft.number]?.uppercased()
            questions.append(
                ReadingQuestQuestion(
                    number: draft.number,
                    prompt: draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                    choices: draft.choices,
                    correctChoiceLetter: answerLetter
                )
            )
        }

        var questions: [ReadingQuestQuestion] = []
        var current: DraftQuestion?

        for rawLine in block.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if let questionMatch = match(questionPattern, in: line),
               let numberText = substring(line, match: questionMatch, group: 1),
               let prompt = substring(line, match: questionMatch, group: 2),
               let number = Int(numberText) {
                try appendDraft(current, to: &questions)
                current = DraftQuestion(number: number, prompt: prompt, choices: [], inlineAnswer: nil)
                continue
            }

            if let optionMatch = match(optionPattern, in: line),
               let letter = substring(line, match: optionMatch, group: 1),
               let text = substring(line, match: optionMatch, group: 2) {
                guard current != nil else {
                    throw ReadingImportError.invalidReadingFormat(sourceFilename)
                }

                current?.choices.append(
                    ReadingQuestChoice(letter: letter.uppercased(), text: text)
                )
                continue
            }

            if let answerMatch = match(inlineAnswerPattern, in: line),
               let answerLetter = substring(line, match: answerMatch, group: 1) {
                guard current != nil else {
                    throw ReadingImportError.invalidReadingFormat(sourceFilename)
                }

                current?.inlineAnswer = answerLetter.uppercased()
                continue
            }

            guard var draft = current else {
                throw ReadingImportError.invalidReadingFormat(sourceFilename)
            }

            if draft.choices.isEmpty {
                draft.prompt += " " + line
            } else if let lastChoice = draft.choices.last {
                let updated = ReadingQuestChoice(letter: lastChoice.letter, text: lastChoice.text + " " + line)
                draft.choices[draft.choices.count - 1] = updated
            } else {
                draft.prompt += " " + line
            }
            current = draft
        }

        try appendDraft(current, to: &questions)

        guard !questions.isEmpty else {
            throw ReadingImportError.invalidReadingFormat(sourceFilename)
        }

        return questions
    }

    private static func parseAnswerMap(from text: String) -> [Int: String] {
        guard let answersRange = text.range(of: "--- ANSWERS ---") else {
            return [:]
        }

        let block = String(text[answersRange.upperBound...])
        let regex = try? NSRegularExpression(pattern: #"^\s*(\d+)\.\s*([A-Z])\s*$"#, options: [.anchorsMatchLines, .caseInsensitive])
        let fullRange = NSRange(block.startIndex..., in: block)
        let body = block

        guard let regex else { return [:] }

        return regex.matches(in: body, range: fullRange).reduce(into: [:]) { partialResult, match in
            guard let numberRange = Range(match.range(at: 1), in: body),
                  let answerRange = Range(match.range(at: 2), in: body),
                  let number = Int(body[numberRange]) else {
                return
            }

            partialResult[number] = String(body[answerRange]).uppercased()
        }
    }

    static func readingPageNumber(from title: String) -> Int? {
        let pattern = #"Page[_ ](\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else {
            return nil
        }

        return Int(title[range])
    }

    static func readingSlug(from title: String) -> String {
        let lowered = title.lowercased()
        let replaced = lowered.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }
        let collapsed = String(replaced)
            .split(separator: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return collapsed.isEmpty ? UUID().uuidString.lowercased() : collapsed
    }
}

enum PETPDFWordParser {
    static func parse(text: String) throws -> [ImportedWordEntry] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var entries: [ImportedWordEntry] = []
        var pendingEnglish = ""

        for line in lines {
            guard !line.isEmpty else { continue }
            if isSkipLine(line) {
                continue
            }

            if containsChinese(line) {
                if !pendingEnglish.isEmpty || startsWithASCIIEntry(line) {
                    let merged = pendingEnglish + line
                    pendingEnglish = ""
                    let entry = try makeEntry(from: merged)
                    entries.append(entry)
                } else if let last = entries.popLast() {
                    entries.append(
                        ImportedWordEntry(
                            english: last.english,
                            primaryChinese: last.primaryChinese + line,
                            topic: last.topic
                        )
                    )
                }
            } else if line.allSatisfy({ character in
                character.unicodeScalars.allSatisfy { punctuationContinuationCharacters.contains($0) }
            }) {
                guard let last = entries.popLast() else { continue }
                entries.append(
                    ImportedWordEntry(
                        english: last.english,
                        primaryChinese: last.primaryChinese + line,
                        topic: last.topic
                    )
                )
            } else if isASCIIFragment(line) {
                pendingEnglish += line
            }
        }

        return entries
    }

    private static let punctuationContinuationCharacters = CharacterSet(charactersIn: ",，;；、…·.")

    private static func isSkipLine(_ line: String) -> Bool {
        if line == "学习日期:" || line == "学生姓名:" {
            return true
        }
        if line.hasPrefix("剑桥五级-PET词汇-2020更新版词库") {
            return true
        }
        if line.hasPrefix("打印时间:") {
            return true
        }
        if line.allSatisfy({ $0 == "_" }) {
            return true
        }
        if line.count == 1, let scalar = line.unicodeScalars.first, (0x2460...0x2468).contains(Int(scalar.value)) {
            return true
        }
        if line.hasPrefix("第"), line.hasSuffix("关") {
            let digits = line.dropFirst().dropLast()
            if !digits.isEmpty, digits.allSatisfy(\.isNumber) {
                return true
            }
        }
        return false
    }

    private static func containsChinese(_ line: String) -> Bool {
        line.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }

    private static func startsWithASCIIEntry(_ line: String) -> Bool {
        guard let scalar = line.unicodeScalars.first else {
            return false
        }

        return scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)
    }

    private static func isASCIIFragment(_ line: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,'’()-/&+")
        return line.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func makeEntry(from line: String) throws -> ImportedWordEntry {
        guard let chineseIndex = line.firstIndex(where: { character in
            character.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(Int(scalar.value))
            }
        }) else {
            throw VocabularyImportError.noWordsFound
        }

        var boundary = chineseIndex
        while boundary > line.startIndex {
            let previous = line[line.index(before: boundary)]
            if previous == " " || previous == "(" || previous == "[" || previous == "{" {
                boundary = line.index(before: boundary)
            } else {
                break
            }
        }

        var english = line[..<boundary]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "([{"))
        let chinese = line[boundary...].trimmingCharacters(in: .whitespacesAndNewlines)

        if english == "l" && chinese == "我" {
            english = "I"
        }

        return ImportedWordEntry(english: english, primaryChinese: chinese, topic: nil)
    }
}

private enum JSONVocabularyParser {
    private struct RawImportWord: Decodable {
        let id: String?
        let english: String
        let primaryChinese: String
        let topic: WordTopic?
    }

    static func parse(data: Data) throws -> [ImportedWordEntry] {
        let decoder = JSONDecoder()

        if let words = try? decoder.decode([VocabularyWord].self, from: data) {
            return words.map { ImportedWordEntry(english: $0.english, primaryChinese: $0.primaryChinese, topic: $0.topic) }
        }

        guard let rawWords = try? decoder.decode([RawImportWord].self, from: data) else {
            throw VocabularyImportError.invalidJSON
        }

        return rawWords.map { ImportedWordEntry(english: $0.english, primaryChinese: $0.primaryChinese, topic: $0.topic) }
    }
}

private enum DelimitedVocabularyParser {
    static func parse(text: String) throws -> [ImportedWordEntry] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let parsed = lines.compactMap(parseLine)
        guard !parsed.isEmpty else {
            throw VocabularyImportError.invalidTextFormat
        }
        return parsed
    }

    private static func parseLine(_ line: String) -> ImportedWordEntry? {
        for separator in ["\t", ",", "|", " - ", "：", ":"] {
            let parts = line.components(separatedBy: separator)
            guard parts.count >= 2 else { continue }
            let english = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let chinese = parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !english.isEmpty, !chinese.isEmpty else { continue }
            return ImportedWordEntry(english: english, primaryChinese: chinese, topic: nil)
        }

        return nil
    }
}

private enum ImportedWordTopicClassifier {
    private static let englishKeywords: [WordTopic: [String]] = [
        .school: ["school", "class", "teacher", "student", "lesson", "exam", "study", "homework", "university", "college", "dictionary", "pencil", "quiz"],
        .travel: ["travel", "trip", "flight", "airport", "hotel", "passport", "tour", "holiday", "luggage", "journey", "beach", "map", "resort", "camp"],
        .home: ["home", "house", "room", "kitchen", "bathroom", "bedroom", "garden", "sofa", "cushion", "refrigerator", "window", "door", "chair"],
        .food: ["food", "bread", "apple", "banana", "pizza", "tea", "coffee", "milk", "egg", "lunch", "dinner", "restaurant", "cook", "dish", "burger"],
        .health: ["health", "doctor", "nurse", "hospital", "disease", "headache", "toothache", "sick", "medicine", "ambulance", "injure", "cough"],
        .shopping: ["shop", "store", "price", "cost", "sale", "market", "supermarket", "money", "pay", "wallet", "cash", "customer", "half-price"],
        .transport: ["bus", "train", "taxi", "bike", "bicycle", "road", "pavement", "station", "ticket", "car", "van", "plane", "aeroplane", "airport"],
        .work: ["work", "office", "manager", "job", "salary", "company", "employ", "career", "business", "interview", "printer", "secretary"],
        .people: ["man", "woman", "boy", "girl", "child", "family", "father", "mother", "wife", "husband", "grandfather", "friend", "mate", "lady"],
        .feelings: ["happy", "sad", "angry", "nervous", "excited", "worried", "confident", "afraid", "glad", "amazed", "terrific", "terrible"],
        .places: ["city", "town", "country", "park", "lake", "mountain", "desert", "stadium", "cinema", "nightclub", "prison", "cafeteria", "mall"],
        .actions: ["run", "walk", "jump", "think", "select", "choose", "bring", "carry", "leave", "search", "convince", "approve", "fetch"],
        .time: ["monday", "tuesday", "friday", "saturday", "sunday", "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december", "time", "week", "month", "year", "today", "tomorrow", "yesterday", "first", "second", "third", "fourteenth", "twelfth"],
        .communication: ["comment", "talk", "speak", "ask", "answer", "question", "phone", "message", "report", "letter", "word", "language", "say", "apologise"]
    ]

    private static let chineseKeywords: [WordTopic: [String]] = [
        .school: ["学校", "老师", "学生", "课程", "考试", "作业", "教室", "词典", "课堂", "大学", "学习"],
        .travel: ["旅行", "旅游", "机场", "酒店", "护照", "行李", "旅程", "度假", "营地", "海滩", "胜地"],
        .home: ["家庭", "家", "房", "卧室", "厨房", "浴室", "花园", "冰箱", "门", "窗"],
        .food: ["食物", "面包", "苹果", "香蕉", "汉堡", "餐", "晚餐", "午餐", "早餐", "菜", "饮料", "咖啡", "牛奶"],
        .health: ["健康", "医生", "医院", "疾病", "头痛", "牙痛", "生病", "救护车", "受伤", "卫生"],
        .shopping: ["购物", "商店", "价格", "商品", "超市", "半价", "现金", "钱包", "顾客", "买"],
        .transport: ["公交", "火车", "出租车", "自行车", "车站", "票", "飞机", "人行道", "道路", "车轮"],
        .work: ["工作", "办公室", "工资", "雇用", "公司", "职业", "打印机", "秘书", "老板"],
        .people: ["男人", "女人", "男孩", "女孩", "孩子", "家庭", "父", "母", "妻子", "朋友", "祖父", "女士"],
        .feelings: ["高兴", "难过", "紧张", "惊讶", "自信", "害怕", "焦虑", "生气", "快乐"],
        .places: ["城市", "城镇", "公园", "湖", "沙漠", "体育场", "电影院", "夜总会", "监狱", "商场"],
        .actions: ["选择", "带来", "离开", "搜索", "说服", "批准", "取来", "思考", "跑", "走"],
        .time: ["星期", "时间", "年", "月", "日", "今天", "明天", "昨天", "第一", "第二", "第三", "十"],
        .communication: ["评论", "说", "问", "回答", "问题", "信", "语言", "词", "报告", "道歉"]
    ]

    static func classify(english: String, chinese: String, seedTopicByEnglishKey: [String: WordTopic]) -> WordTopic {
        let normalizedEnglish = english.lowercased()
        let seedKey = normalizedEnglish.replacingOccurrences(of: " ", with: "")
        if let topic = seedTopicByEnglishKey[seedKey] {
            return topic
        }

        var bestTopic: WordTopic?
        var bestScore = Int.min

        for topic in WordTopic.allCases {
            let englishScore = englishKeywords[topic, default: []].reduce(into: 0) { score, keyword in
                if normalizedEnglish.contains(keyword) {
                    score += 2
                }
            }
            let chineseScore = chineseKeywords[topic, default: []].reduce(into: 0) { score, keyword in
                if chinese.contains(keyword) {
                    score += 1
                }
            }
            let total = englishScore + chineseScore
            if total > bestScore {
                bestScore = total
                bestTopic = topic
            }
        }

        if let bestTopic, bestScore > 0 {
            return bestTopic
        }

        let hash = normalizedEnglish.unicodeScalars.reduce(into: UInt64(0)) { partialResult, scalar in
            partialResult = (partialResult &* 31) &+ UInt64(scalar.value)
        }
        return WordTopic.allCases[Int(hash % UInt64(WordTopic.allCases.count))]
    }
}
