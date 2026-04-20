import Foundation
import PDFKit

struct ImportedWordLibrary: Hashable {
    let words: [VocabularyWord]
    let metadata: WordLibraryMetadata
}

struct ImportedWordEntry: Hashable {
    let english: String
    let primaryChinese: String
    let topic: WordTopic?
}

enum VocabularyImportError: LocalizedError {
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

enum VocabularyImportService {
    static func importWordLibrary(from url: URL, seedWords: [VocabularyWord]) throws -> ImportedWordLibrary {
        let source = importedSource(for: url)
        let importedEntries: [ImportedWordEntry]

        switch source {
        case .pdf:
            let text = try PDFVocabularyTextExtractor.extractText(from: url)
            importedEntries = try PETPDFWordParser.parse(text: text)
        case .json:
            importedEntries = try JSONVocabularyParser.parse(data: Data(contentsOf: url))
        case .csv:
            let text = try String(contentsOf: url, encoding: .utf8)
            importedEntries = try DelimitedVocabularyParser.parse(text: text)
        case .plainText:
            let text = try String(contentsOf: url, encoding: .utf8)
            importedEntries = try DelimitedVocabularyParser.parse(text: text)
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
            )
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
        let topicMap = Dictionary(uniqueKeysWithValues: seedWords.map { (normalizeEnglishKey($0.english), $0.topic) })
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

        let hash = normalizedEnglish.unicodeScalars.reduce(0) { partialResult, scalar in
            (partialResult * 31) &+ Int(scalar.value)
        }
        return WordTopic.allCases[abs(hash) % WordTopic.allCases.count]
    }
}
