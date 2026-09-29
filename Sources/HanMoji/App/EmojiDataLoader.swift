import Foundation
import HanMojiCore

enum EmojiDataLoader {
    enum LoadError: Error, CustomStringConvertible {
        case notFound
        var description: String { "emoji.json을 찾을 수 없습니다. `make data`로 생성하세요." }
    }

    /// 우선순위: HANMOJI_DATA 환경변수 → .app 번들 Resources → SwiftPM 리소스 번들(`swift run`)
    static func load() throws -> EmojiDatabase {
        if let path = ProcessInfo.processInfo.environment["HANMOJI_DATA"] {
            return try EmojiDatabase.load(from: URL(fileURLWithPath: path))
        }
        if let url = Bundle.main.url(forResource: "emoji", withExtension: "json") {
            return try EmojiDatabase.load(from: url)
        }
        if let url = Bundle.module.url(forResource: "emoji", withExtension: "json") {
            return try EmojiDatabase.load(from: url)
        }
        throw LoadError.notFound
    }
}
