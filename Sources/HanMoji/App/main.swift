import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Info.plist의 LSUIElement가 없는 `swift run` 환경에서도 Dock 아이콘 없이 동작하게 한다.
app.setActivationPolicy(.accessory)
app.run()
