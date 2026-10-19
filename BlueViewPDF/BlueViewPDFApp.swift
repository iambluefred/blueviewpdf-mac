import AppKit
import SwiftUI

@main
struct BlueViewPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = ViewerModel.shared
    @State private var localizer = Localizer.shared
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("showInspector") private var showInspector = false

    var body: some Scene {
        // 用 WindowGroup：App 還沒開時從 Finder 開 PDF 也會建立視窗；已開時交給現有視窗
        WindowGroup("BlueViewPDF", id: "main") {
            ContentView(model: model)
                .onAppear { DispatchQueue.main.async { WindowSizer.keepOnScreen() } }
                .onOpenURL { url in if PDFFile.isPDF(url) { model.open(url) } }
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(tr("Open…", "開啟…"), action: model.chooseFile).keyboardShortcut("o")
                Menu(tr("Open Recent", "最近開啟")) {
                    ForEach(model.recent, id: \.self) { url in
                        Button(url.lastPathComponent) { model.open(url) }
                    }
                    Divider()
                    Button(tr("Clear Menu", "清除選單"), action: model.clearRecent).disabled(model.recent.isEmpty)
                }
                Divider()
                Button(tr("Close PDF", "關閉 PDF"), action: model.close)
                    .keyboardShortcut("w", modifiers: [.command, .shift]).disabled(model.document == nil)
                Button(tr("Show in Finder", "在 Finder 中顯示"), action: model.revealInFinder)
                    .keyboardShortcut("r", modifiers: [.command, .shift]).disabled(model.url == nil)
            }
            CommandGroup(replacing: .printItem) {
                Button(tr("Print…", "列印…"), action: model.print).keyboardShortcut("p").disabled(!model.isReady)
            }
            CommandGroup(after: .textEditing) {
                Divider()
                Button(tr("Find…", "尋找…"), action: model.focusSearch).keyboardShortcut("f").disabled(!model.isReady)
                Button(tr("Find Next", "找下一個"), action: model.nextHit).keyboardShortcut("g").disabled(!model.isReady)
                Button(tr("Find Previous", "找上一個"), action: model.previousHit)
                    .keyboardShortcut("g", modifiers: [.command, .shift]).disabled(!model.isReady)
            }
            CommandGroup(after: .sidebar) {
                Toggle(tr("Sidebar", "側邊欄"), isOn: $showSidebar).keyboardShortcut("s", modifiers: [.command, .control])
                Toggle(tr("Info Panel", "資訊面板"), isOn: $showInspector).keyboardShortcut("i", modifiers: [.command, .option])
                Picker(tr("Sidebar Shows", "側邊欄顯示"), selection: $model.sidebarTab) {
                    ForEach(SidebarTab.allCases) { Text($0.label).tag($0) }
                }
                Divider()
                Picker(tr("Page Layout", "頁面排列"), selection: $model.layout) {
                    ForEach(PageLayout.allCases) { Text($0.label).tag($0) }
                }
                Toggle(tr("Book Mode (cover on its own)", "書本模式（封面單獨一頁）"), isOn: $model.displaysAsBook)
                Divider()
                Button(tr("Zoom to Fit", "符合視窗"), action: model.zoomToFit).keyboardShortcut("0").disabled(!model.isReady)
                Button(tr("Actual Size", "實際大小 100%"), action: model.actualSize).keyboardShortcut("1").disabled(!model.isReady)
                Button(tr("Zoom In", "放大"), action: model.zoomIn).keyboardShortcut("+").disabled(!model.isReady)
                Button(tr("Zoom Out", "縮小"), action: model.zoomOut).keyboardShortcut("-").disabled(!model.isReady)
                Divider()
                Picker(tr("Language", "語言"), selection: $localizer.language) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                Divider()
            }
            CommandMenu(tr("Go", "前往")) {
                Button(tr("Previous Page", "上一頁"), action: model.previousPage)
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option]).disabled(!model.isReady)
                Button(tr("Next Page", "下一頁"), action: model.nextPage)
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option]).disabled(!model.isReady)
                Button(tr("First Page", "第一頁"), action: model.firstPage)
                    .keyboardShortcut(.home, modifiers: []).disabled(!model.isReady)
                Button(tr("Last Page", "最後一頁"), action: model.lastPage)
                    .keyboardShortcut(.end, modifiers: []).disabled(!model.isReady)
                Button(tr("Go to Page…", "跳到頁碼…"), action: model.focusPageField)
                    .keyboardShortcut("g", modifiers: [.command, .option]).disabled(!model.isReady)
                Divider()
                Button(tr("Back", "返回"), action: model.goBack).keyboardShortcut("[").disabled(!model.canGoBack)
                Button(tr("Forward", "向前"), action: model.goForward).keyboardShortcut("]").disabled(!model.canGoForward)
            }
            CommandGroup(after: .windowSize) {
                Divider()
                Button(tr("Fit to Screen", "符合螢幕")) { WindowSizer.fitToScreen() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
            }
        }
    }
}

/// 從 Finder 開 PDF 由上面的 onOpenURL 處理（不要在這裡實作 application(_:open:)，否則 SwiftUI 不會自己建立視窗）
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// 調整視窗大小：一律限制在螢幕可用範圍內，不會超出螢幕
enum WindowSizer {
    @MainActor
    static var window: NSWindow? { NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible } }

    @MainActor
    static func fitToScreen() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        window.setFrame(screen.visibleFrame, display: true, animate: true)
    }

    /// 開啟時若視窗超出螢幕，縮進螢幕範圍內
    @MainActor
    static func keepOnScreen() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, area.width)
        frame.size.height = min(frame.height, area.height)
        frame.origin.x = min(max(frame.minX, area.minX), area.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, area.minY), area.maxY - frame.height)
        if frame != window.frame { window.setFrame(frame, display: true) }
    }
}
