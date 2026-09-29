import AppKit

/// 우리 앱을 제외한 최근 활성 앱을 추적한다.
final class FrontmostAppTracker {
    private(set) var current: NSRunningApplication?
    var onChange: ((NSRunningApplication) -> Void)?
    private var observer: NSObjectProtocol?

    init() {
        let me = ProcessInfo.processInfo.processIdentifier
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != me {
            current = app
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != me else { return }
            self.current = app
            self.onChange?(app)
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
