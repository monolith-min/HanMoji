import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var combo: KeyCombo
    @StateObject private var recorder = Recorder()

    var body: some View {
        HStack {
            Text("패널 열기/닫기")
            Spacer()
            Button(recorder.isRecording ? "키를 누르세요… (esc 취소)" : combo.displayString) {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    recorder.start { combo = $0 }
                }
            }
            .buttonStyle(.bordered)
            .frame(minWidth: 140)
            Button("기본값") { combo = .default }
                .disabled(combo == .default)
        }
        .onDisappear { recorder.stop() }
    }

    final class Recorder: ObservableObject {
        @Published var isRecording = false
        private var monitor: Any?

        func start(_ done: @escaping (KeyCombo) -> Void) {
            isRecording = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if Int(event.keyCode) == kVK_Escape { self.stop(); return nil }
                let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
                // ⇧만으로는 글로벌 단축키로 부적절
                guard !mods.isEmpty, mods != [.shift] else { NSSound.beep(); return nil }
                done(KeyCombo(event: event))
                self.stop()
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            isRecording = false
        }
    }
}
