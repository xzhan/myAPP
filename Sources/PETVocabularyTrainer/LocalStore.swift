import Foundation

enum SeedWordLoader {
    static func loadWords() throws -> [VocabularyWord] {
        let url = Bundle.module.url(forResource: "pet_words", withExtension: "json")!
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

    func save(_ storeData: AppStoreData) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(storeData)
        try data.write(to: url, options: .atomic)
    }

    private static func defaultURL(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("PETVocabularyTrainer", isDirectory: true)
            .appendingPathComponent("store.json")
    }
}
