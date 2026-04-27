import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DemoLog.resetForNewRun()
        DemoLog.log("didFinishLaunching start")
        DemoLog.log("bundle=\(Bundle.main.bundleURL.path)")
        DemoLog.log("activationPolicy(before)=\(NSApp.activationPolicy().rawValue)")

        // 强制 aqua(亮)主题，不跟随系统——避免亮/暗切换时视觉失衡。
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = Self.buildMainMenu()
        DemoLog.log("policy set to regular, menu installed")

        let controller = MainWindowController()
        windowController = controller
        DemoLog.log("controller created; window=\(String(describing: controller.window))")

        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let w = controller.window
        DemoLog.log(
            "end — isVisible=\(w?.isVisible ?? false) isKey=\(w?.isKeyWindow ?? false) "
            + "frame=\(w.map { NSStringFromRect($0.frame) } ?? "nil") "
            + "screen=\(w?.screen?.localizedName ?? "nil") "
            + "activation=\(NSApp.activationPolicy().rawValue) "
            + "windowCount=\(NSApp.windows.count)")
    }

    private static func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "退出 FgVadDemo",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appItem.submenu = appMenu
        return mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
