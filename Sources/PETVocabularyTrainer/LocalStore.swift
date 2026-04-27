import Foundation

enum SeedWordLoader {
    static func loadWords() throws -> [VocabularyWord] {
        let appResourceURL = Bundle.main.resourceURL?.appendingPathComponent("pet_words.json")
        let fallbackResourceURL = Bundle.module.url(forResource: "pet_words", withExtension: "json")
        let candidateURLs = [appResourceURL, fallbackResourceURL].compactMap { $0 }

        guard let url = candidateURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([VocabularyWord].self, from: data)
    }
}

struct LocalStore {
    private let fileManager: FileManager
    let url: URL

    init(fileManager: FileManager = .default, url: URL? = nil) {
        self.fileManager = fileManager
        self.url = url ?? Self.defaultURL(fileManager: fileManager)
    }

    func load() throws -> AppStoreData {
        guard fileManager.fileExists(atPath: url.path) else {
            return AppStoreData()
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppStoreData.self, from: data)
    }

    func installBundledInitialDataIfNeeded(
        from initialDataURL: URL? = Bundle.main.resourceURL?.appendingPathComponent("InitialData")
    ) throws {
        guard let initialDataURL,
              fileManager.fileExists(atPath: initialDataURL.path) else {
            return
        }

        let bundledStoreURL = initialDataURL.appendingPathComponent("store.json")
        let bundledImportedWordsURL = initialDataURL.appendingPathComponent("imported_words.json")
        guard fileManager.fileExists(atPath: bundledStoreURL.path) else {
            return
        }

        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let hasLocalStore = fileManager.fileExists(atPath: url.path)
        let hasLocalImportedWords = fileManager.fileExists(atPath: importedWordsURL.path)

        if !hasLocalStore && !hasLocalImportedWords {
            try fileManager.copyItem(at: bundledStoreURL, to: url)

            if fileManager.fileExists(atPath: bundledImportedWordsURL.path) {
                try fileManager.copyItem(at: bundledImportedWordsURL, to: importedWordsURL)
            }
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundledData = try decoder.decode(AppStoreData.self, from: Data(contentsOf: bundledStoreURL))
        var localData = hasLocalStore ? try load() : AppStoreData()
        var didMergeBundledData = false

        if localData.importedLibrary == nil, bundledData.importedLibrary != nil {
            localData.activeWordBankMode = bundledData.activeWordBankMode
            localData.importedLibrary = bundledData.importedLibrary
            localData.wordPages = bundledData.wordPages
            localData.questPages = bundledData.questPages
            localData.currentQuestPageNumber = localData.currentQuestPageNumber ?? bundledData.currentQuestPageNumber
            didMergeBundledData = true
        } else if localData.questPages.isEmpty, !bundledData.questPages.isEmpty {
            localData.questPages = bundledData.questPages
            localData.currentQuestPageNumber = localData.currentQuestPageNumber ?? bundledData.currentQuestPageNumber
            didMergeBundledData = true
        }

        if localData.readingLibrary == nil, bundledData.readingLibrary != nil {
            localData.readingLibrary = bundledData.readingLibrary
            localData.readingQuests = bundledData.readingQuests
            didMergeBundledData = true
        }

        if !hasLocalImportedWords, fileManager.fileExists(atPath: bundledImportedWordsURL.path) {
            try fileManager.copyItem(at: bundledImportedWordsURL, to: importedWordsURL)
        }

        if didMergeBundledData {
            _ = try backupExistingData(reason: "initial-data-merge")
            try save(localData)
        }
    }

    @discardableResult
    func backupExistingData(reason: String, now: Date = .now) throws -> URL? {
        let filesToBackUp = [url, importedWordsURL].filter { fileManager.fileExists(atPath: $0.path) }
        guard !filesToBackUp.isEmpty else {
            return nil
        }

        let backupRootURL = url.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: backupRootURL, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: now)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "Z", with: "")
        let sanitizedReason = reason
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^A-Za-z0-9_-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        let backupName = [timestamp, sanitizedReason.isEmpty ? "data-safety" : sanitizedReason]
            .joined(separator: "-")

        var backupURL = backupRootURL.appendingPathComponent(backupName, isDirectory: true)
        if fileManager.fileExists(atPath: backupURL.path) {
            backupURL = backupRootURL.appendingPathComponent("\(backupName)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        }

        try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)
        for fileURL in filesToBackUp {
            try fileManager.copyItem(
                at: fileURL,
                to: backupURL.appendingPathComponent(fileURL.lastPathComponent)
            )
        }

        return backupURL
    }

    func save(_ storeData: AppStoreData) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(storeData)
        try data.write(to: url, options: .atomic)
    }

    func loadImportedWords() throws -> [VocabularyWord]? {
        let importURL = importedWordsURL
        guard fileManager.fileExists(atPath: importURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: importURL)
        return try JSONDecoder().decode([VocabularyWord].self, from: data)
    }

    func saveImportedWords(_ words: [VocabularyWord]) throws {
        try fileManager.createDirectory(at: importedWordsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(words)
        try data.write(to: importedWordsURL, options: .atomic)
    }

    func deleteImportedWords() throws {
        guard fileManager.fileExists(atPath: importedWordsURL.path) else {
            return
        }

        try fileManager.removeItem(at: importedWordsURL)
    }

    private var importedWordsURL: URL {
        url.deletingLastPathComponent().appendingPathComponent("imported_words.json")
    }

    private static func defaultURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("PETVocabularyTrainer", isDirectory: true)
            .appendingPathComponent("store.json")
    }
}
