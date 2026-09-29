import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permissions: PermissionManager
    let dataVersion: String
    let onClearRecents: () -> Void

    var body: some View {
        Form {
            Section("자동 팝업") {
                Toggle("한글 단어를 입력하면 이모지 후보 표시", isOn: $settings.autoPopupEnabled)
                Picker("최소 글자 수", selection: $settings.minWordLength) {
                    Text("1글자").tag(1)
                    Text("2글자").tag(2)
                    Text("3글자").tag(3)
                }
                Toggle("조사가 붙은 단어도 인식 (사랑해 → 사랑)", isOn: $settings.matchKeywordPrefix)
                Toggle("영어 입력 중에도 표시", isOn: $settings.englishTrigger)
                Picker("후보 개수", selection: $settings.maxSuggestions) {
                    ForEach([5, 6, 8, 10], id: \.self) { Text("\($0)개").tag($0) }
                }
            }

            Section("후보가 떠 있을 때 키") {
                LabeledContent("삽입", value: "Tab")
                LabeledContent("후보 이동", value: "←  →")
                LabeledContent("이 단어에서 닫기", value: "Esc")
                Toggle("Enter 키로도 삽입", isOn: $settings.enterSelects)
                Text("채팅 앱에서는 Enter가 전송과 겹치므로 기본은 꺼져 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("삽입 방식") {
                Picker("방식", selection: $settings.insertMethod) {
                    Text("클립보드 붙여넣기 (⌘V)").tag(InsertMethod.paste)
                    Text("유니코드 직접 입력").tag(InsertMethod.typeUnicode)
                }
                .pickerStyle(.radioGroup)
                Text("붙여넣기는 대부분의 앱에서 안정적이며 기존 클립보드는 삽입 후 복원됩니다. 직접 입력은 클립보드를 건드리지 않지만 일부 앱에서 결합 이모지가 깨질 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("검색 패널 (단축키)") {
                ShortcutRecorderView(combo: $settings.hotKey)
                Picker("패널 위치", selection: $settings.panelPlacement) {
                    Text("마우스 커서 근처").tag(PanelPlacement.nearMouse)
                    Text("화면 중앙").tag(PanelPlacement.screenCenter)
                }
            }

            Section("자동 팝업 제외 앱") {
                if settings.excludedBundleIDs.isEmpty {
                    Text("없음. 메뉴바 아이콘 메뉴에서 현재 앱을 제외할 수 있습니다.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.excludedBundleIDs, id: \.self) { bid in
                    HStack {
                        Text(Self.appName(for: bid))
                        Text(bid).font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                        Button("제거") { settings.excludedBundleIDs.removeAll { $0 == bid } }
                    }
                }
            }

            Section("권한") {
                HStack {
                    Image(systemName: permissions.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(permissions.isTrusted ? Color.green : Color.orange)
                    Text(permissions.isTrusted ? "손쉬운 사용(접근성) 권한 있음" : "손쉬운 사용(접근성) 권한 없음")
                    Spacer()
                    if !permissions.isTrusted {
                        Button("시스템 설정 열기") { permissions.requestAccess() }
                    }
                }
                Text("키 입력은 단어 단위로 메모리에서만 처리되며 저장·전송되지 않습니다. 비밀번호 입력란은 macOS 보안 입력 모드로 자동 제외됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button("최근 사용 기록 지우기", action: onClearRecents)
                LabeledContent("이모지 데이터", value: dataVersion)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 700)
    }

    static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
