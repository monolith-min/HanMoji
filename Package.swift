// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HanMoji",
    platforms: [.macOS(.v14)],
    targets: [
        // 순수 Foundation 로직: 한글 분해/조합, 패턴 매칭, 검색 엔진. AppKit 의존 없음 → 유닛 테스트 대상.
        .target(name: "HanMojiCore"),

        // 메뉴바 앱 본체 (AppKit + SwiftUI).
        .executableTarget(
            name: "HanMoji",
            dependencies: ["HanMojiCore"],
            resources: [.copy("Resources/emoji.json")],
            linkerSettings: [.linkedFramework("Carbon")]
        ),

        // CLDR annotations + emoji-test.txt → emoji.json 생성기.
        .executableTarget(name: "hanmoji-datagen", dependencies: ["HanMojiCore"]),

        .testTarget(name: "HanMojiCoreTests", dependencies: ["HanMojiCore"]),
    ]
)
