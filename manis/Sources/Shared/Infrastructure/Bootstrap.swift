import AppKit
import OSLog
import ServiceManagement
import SwiftUI

public enum Bootstrap {
    private static let logger = Logger(subsystem: "com.manis.Bootstrap", category: "main")

    public static var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                    try SMAppService.mainApp.register()
                    if SMAppService.mainApp.status == .requiresApproval {
                        openSystemSettings()
                    }
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                logger.error("Login configuration failed. Verify write permissions. \(error.localizedDescription)")
            }
        }
    }

    public static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    public static var wasLaunchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    public static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

extension Bootstrap {
    @MainActor
    final class Observable: ObservableObject {
        init() {}

        var isEnabled: Bool {
            get { Bootstrap.isEnabled }
            set {
                objectWillChange.send()
                Bootstrap.isEnabled = newValue
            }
        }

        var requiresApproval: Bool {
            Bootstrap.requiresApproval
        }
    }
}

public extension Bootstrap {
    struct Toggle<Label: View>: View {
        @ObservedObject private var observable = Observable()
        private let label: Label

        public init(@ViewBuilder label: () -> Label) {
            self.label = label()
        }

        public var body: some View {
            SwiftUI.Toggle(isOn: $observable.isEnabled) { label }
                .disabled(observable.requiresApproval)
        }
    }
}

public extension Bootstrap.Toggle<Text> {
    init(_ titleKey: LocalizedStringKey) {
        self.init { Text(titleKey) }
    }

    init(_ title: some StringProtocol) {
        self.init { Text(title) }
    }

    init() {
        self.init("Launch at login")
    }
}
