import AppKit

// 显式入口：NSApp + AppDelegate 手动绑定。
// 不用 @main / @NSApplicationMain——那俩依赖 main nib/storyboard 的 File's Owner
// 来注入 delegate，而我们是纯代码工程，没有 nib。
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
