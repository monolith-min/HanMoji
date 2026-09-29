import XCTest
@testable import HanMojiCore

/// 실제 번들 데이터로 검색 지연을 확인한다. emoji.json이 플레이스홀더면 건너뛴다.
final class PerformanceTests: XCTestCase {
    static let dataURL: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() } // Tests/HanMojiCoreTests/File.swift → 패키지 루트
        return url.appendingPathComponent("Sources/HanMoji/Resources/emoji.json")
    }()

    private func loadEngine() throws -> SearchEngine? {
        let db = try EmojiDatabase.load(from: Self.dataURL)
        guard db.entries.count > 100 else { return nil }
        return SearchEngine(database: db)
    }

    func testRealDataSanity() throws {
        guard let engine = try loadEngine() else { throw XCTSkip("emoji.json 미생성") }
        XCTAssertFalse(engine.search("웃음").isEmpty)
        XCTAssertFalse(engine.search("하트").isEmpty)
        XCTAssertFalse(engine.search("ㅎㅌ").isEmpty)
        XCTAssertFalse(engine.search("cat").isEmpty)
        XCTAssertFalse(engine.suggestions(forTypedWord: "사랑해").isEmpty)
        print("entries: \(engine.entries.count), tokens: \(engine.tokenCount)")
    }

    func testSearchLatencyUnder10ms() throws {
        guard let engine = try loadEngine() else { throw XCTSkip("emoji.json 미생성") }
        let queries = ["기", "기쁨", "ㄱㅃ", "웃", "웃는 얼굴", "하트", "ㅎ", "사랑해", "고양이", "cat", "sm", "smile", "불", "ㅂ", "음식"]
        // 워밍업
        for q in queries { _ = engine.search(q) }

        var worst: Double = 0
        var total: Double = 0
        let rounds = 20
        for _ in 0..<rounds {
            for q in queries {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = engine.search(q)
                let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
                worst = max(worst, ms)
                total += ms
            }
        }
        let avg = total / Double(rounds * queries.count)
        print(String(format: "search avg %.3f ms, worst %.3f ms", avg, worst))
        #if DEBUG
        // 디버그 빌드는 최적화가 없어 느리다. 릴리스 기준 목표는 10ms.
        XCTAssertLessThan(avg, 40, "debug avg")
        #else
        XCTAssertLessThan(avg, 10, "release avg")
        XCTAssertLessThan(worst, 10, "release worst")
        #endif
    }
}
