import Foundation
import HanMojiCore

// hanmoji-datagen <Data/raw 디렉터리> <출력 emoji.json> [--max-emoji-version 17.0] [--include-skin-tones]
//
// 입력:
//   emoji-test.txt              (Unicode) 마스터 목록. fully-qualified 시퀀스, 그룹, 순서, 영어 이름
//   annotations-ko.xml          (CLDR) 한국어 키워드/tts
//   annotationsDerived-ko.xml   (CLDR) ZWJ 시퀀스 등 파생 한국어 키워드/tts
//   annotations-en.xml, annotationsDerived-en.xml  영어 키워드
//
// CLDR의 cp 속성은 보통 VS16(U+FE0F)이 빠져 있어서, 양쪽 모두 FE0F를 제거한 문자열을 조인 키로 쓴다.

struct Args {
    var rawDir: URL
    var output: URL
    var maxEmojiVersion: Double? = nil
    var includeSkinTones = false
}

func parseArgs() -> Args {
    var argv = Array(CommandLine.arguments.dropFirst())
    var maxVersion: Double? = nil
    var skin = false
    if let i = argv.firstIndex(of: "--max-emoji-version"), i + 1 < argv.count {
        maxVersion = Double(argv[i + 1])
        argv.removeSubrange(i...(i + 1))
    }
    if let i = argv.firstIndex(of: "--include-skin-tones") {
        skin = true
        argv.remove(at: i)
    }
    guard argv.count == 2 else {
        FileHandle.standardError.write("usage: hanmoji-datagen <rawDir> <out.json> [--max-emoji-version 17.0] [--include-skin-tones]\n".data(using: .utf8)!)
        exit(2)
    }
    return Args(rawDir: URL(fileURLWithPath: argv[0]), output: URL(fileURLWithPath: argv[1]),
                maxEmojiVersion: maxVersion, includeSkinTones: skin)
}

func stripVariationSelectors(_ s: String) -> String {
    var view = String.UnicodeScalarView()
    for u in s.unicodeScalars where u.value != 0xFE0F && u.value != 0xFE0E { view.append(u) }
    return String(view)
}

// MARK: emoji-test.txt

struct TestEntry {
    let string: String
    let scalars: [UInt32]
    let group: String
    let subgroup: String
    let version: Double
    let name: String
}

func parseEmojiTest(_ url: URL) throws -> [TestEntry] {
    let text = try String(contentsOf: url, encoding: .utf8)
    var group = "", subgroup = ""
    var out = [TestEntry]()
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine)
        if line.hasPrefix("# group:") {
            group = line.dropFirst("# group:".count).trimmingCharacters(in: .whitespaces); continue
        }
        if line.hasPrefix("# subgroup:") {
            subgroup = line.dropFirst("# subgroup:".count).trimmingCharacters(in: .whitespaces); continue
        }
        guard !line.hasPrefix("#"), !line.isEmpty else { continue }
        // 1F600 ; fully-qualified # 😀 E1.0 grinning face
        guard let semi = line.firstIndex(of: ";"), let hash = line.firstIndex(of: "#") else { continue }
        let status = line[line.index(after: semi)..<hash].trimmingCharacters(in: .whitespaces)
        guard status == "fully-qualified" else { continue }
        let codes = line[..<semi].split(separator: " ").compactMap { UInt32($0, radix: 16) }
        guard !codes.isEmpty else { continue }
        let comment = line[line.index(after: hash)...].trimmingCharacters(in: .whitespaces)
        // "😀 E1.0 grinning face"
        let parts = comment.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3, parts[1].hasPrefix("E"), let ver = Double(parts[1].dropFirst()) else { continue }
        var view = String.UnicodeScalarView()
        for c in codes { if let u = Unicode.Scalar(c) { view.append(u) } }
        out.append(TestEntry(string: String(view), scalars: codes, group: group, subgroup: subgroup,
                             version: ver, name: String(parts[2])))
    }
    return out
}

// MARK: CLDR annotations

final class AnnotationParser: NSObject, XMLParserDelegate {
    var keywords: [String: [String]] = [:]
    var names: [String: String] = [:]
    private var currentCP: String?
    private var currentType: String?
    private var buffer = ""

    func parse(_ url: URL) throws {
        guard let parser = XMLParser(contentsOf: url) else { throw NSError(domain: "datagen", code: 1) }
        parser.delegate = self
        guard parser.parse() else { throw parser.parserError ?? NSError(domain: "datagen", code: 2) }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        guard elementName == "annotation" else { return }
        currentCP = attributes["cp"]
        currentType = attributes["type"]
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentCP != nil { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "annotation", let cp = currentCP else { return }
        let key = stripVariationSelectors(cp)
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentType == "tts" {
            if names[key] == nil { names[key] = text }
        } else {
            let list = text.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if keywords[key] == nil { keywords[key] = list }
        }
        currentCP = nil
        currentType = nil
    }
}

// MARK: main

let args = parseArgs()
let raw = args.rawDir

let testEntries = try parseEmojiTest(raw.appendingPathComponent("emoji-test.txt"))

let ko = AnnotationParser()
try ko.parse(raw.appendingPathComponent("annotations-ko.xml"))          // 기본이 먼저 (우선)
try ko.parse(raw.appendingPathComponent("annotationsDerived-ko.xml"))
let en = AnnotationParser()
try en.parse(raw.appendingPathComponent("annotations-en.xml"))
try en.parse(raw.appendingPathComponent("annotationsDerived-en.xml"))

let skinTones: ClosedRange<UInt32> = 0x1F3FB...0x1F3FF
var groups = [String]()
var groupIndex = [String: Int]()
var entries = [EmojiEntry]()
var skippedSkin = 0, skippedVersion = 0, missingKo = 0
var missingSamples = [String]()

for t in testEntries {
    if !args.includeSkinTones, t.scalars.contains(where: { skinTones.contains($0) }) { skippedSkin += 1; continue }
    if let maxV = args.maxEmojiVersion, t.version > maxV { skippedVersion += 1; continue }
    let key = stripVariationSelectors(t.string)
    let koKeywords = ko.keywords[key] ?? []
    let koName = ko.names[key]
    if koKeywords.isEmpty && koName == nil {
        missingKo += 1
        if missingSamples.count < 10 { missingSamples.append("\(t.string) \(t.name)") }
    }
    var enKeywords = en.keywords[key] ?? []
    if let enName = en.names[key], !enKeywords.contains(enName), enName.lowercased() != t.name.lowercased() {
        enKeywords.append(enName)
    }
    let gi: Int
    if let existing = groupIndex[t.group] { gi = existing } else {
        gi = groups.count; groups.append(t.group); groupIndex[t.group] = gi
    }
    entries.append(EmojiEntry(emoji: t.string, koreanKeywords: koKeywords, koreanName: koName,
                              englishKeywords: enKeywords, englishName: t.name, group: gi))
}

let versionNote = (try? String(contentsOf: raw.appendingPathComponent("VERSION"), encoding: .utf8))?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

// 한 항목당 한 줄로 써서 git diff가 읽히게 한다.
let encoder = JSONEncoder()
encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
var out = "{\n"
out += "\"version\": \(String(data: try encoder.encode(versionNote), encoding: .utf8)!),\n"
out += "\"groups\": \(String(data: try encoder.encode(groups), encoding: .utf8)!),\n"
out += "\"entries\": [\n"
for (i, e) in entries.enumerated() {
    out += String(data: try encoder.encode(e), encoding: .utf8)!
    out += i == entries.count - 1 ? "\n" : ",\n"
}
out += "]\n}\n"
try out.write(to: args.output, atomically: true, encoding: .utf8)

// 검증: 다시 읽어본다
let reloaded = try EmojiDatabase.load(from: args.output)
print("emoji-test entries (fully-qualified): \(testEntries.count)")
print("written: \(reloaded.entries.count) entries, \(reloaded.groups.count) groups → \(args.output.path)")
print("skipped skin-tone variants: \(skippedSkin), skipped by version: \(skippedVersion)")
print("missing Korean annotation: \(missingKo)")
for s in missingSamples { print("  - \(s)") }
print("source: \(versionNote)")
