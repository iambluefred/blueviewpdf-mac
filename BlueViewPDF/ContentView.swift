import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: ViewerModel
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("showInspector") private var showInspector = false
    @AppStorage("sidebarWidth") private var sidebarWidth = 200.0
    @AppStorage("inspectorWidth") private var inspectorWidth = 260.0
    @State private var windowWidth: CGFloat = 1100
    @FocusState private var searchFocused: Bool

    /// 中間 PDF 區至少要留的寬度；視窗太窄時自動收起兩側（不改使用者設定）
    private let minContent = 320.0
    private var sidebarVisible: Bool { showSidebar && model.isReady && Double(windowWidth) >= sidebarWidth + minContent + 8 }
    private var inspectorVisible: Bool {
        showInspector && model.document != nil
            && Double(windowWidth) >= (sidebarVisible ? sidebarWidth : 0) + inspectorWidth + minContent + 16
    }
    private var sidebarMax: Double { max(140, min(420, Double(windowWidth) - (inspectorVisible ? inspectorWidth : 0) - minContent - 16)) }
    private var inspectorMax: Double { max(220, min(520, Double(windowWidth) - (sidebarVisible ? sidebarWidth : 0) - minContent - 16)) }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView(model: model, width: sidebarWidth).frame(width: sidebarWidth)
                ResizeHandle(width: $sidebarWidth, range: 140...sidebarMax, defaultWidth: 200, growsToRight: true)
            }
            Group {
                if model.document == nil {
                    WelcomeView(model: model)
                } else if model.isLocked {
                    LockedView(model: model)
                } else {
                    PDFKitView(model: model)
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            if inspectorVisible {
                ResizeHandle(width: $inspectorWidth, range: 220...inspectorMax, defaultWidth: 260, growsToRight: false)
                InspectorView(model: model).frame(width: inspectorWidth)
            }
        }
        .background(GeometryReader { g in
            Color.clear
                .onAppear { windowWidth = g.size.width }
                .onChange(of: g.size.width) { windowWidth = g.size.width }
        })
        .safeAreaInset(edge: .bottom, spacing: 0) { if model.isReady { StatusBar(model: model) } }
        .frame(minWidth: 640, minHeight: 420)
        .navigationTitle(model.title)
        .navigationSubtitle(model.isReady ? tr("\(model.pageCount) pages", "共 \(model.pageCount) 頁") : "")
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: PDFFile.isPDF) else { return false }
            model.open(url)
            return true
        }
        .alert(tr("Can't Open", "無法開啟"), isPresented: Binding(get: { model.errorMessage != nil },
                                                               set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onChange(of: model.focusSearchRequest) {
            if !showSidebar { showSidebar = true }
            searchFocused = true
        }
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { showSidebar.toggle() } label: { Label(tr("Sidebar", "側邊欄"), systemImage: "sidebar.left") }
                .help(tr("Show or hide the sidebar", "顯示或隱藏側邊欄"))
                .disabled(!model.isReady)
        }
        ToolbarItemGroup {
            Button(action: model.previousPage) { Label(tr("Previous Page", "上一頁"), systemImage: "chevron.up") }
                .help(tr("Previous page", "上一頁")).disabled(!model.isReady || model.pageIndex == 0)
            Button(action: model.nextPage) { Label(tr("Next Page", "下一頁"), systemImage: "chevron.down") }
                .help(tr("Next page", "下一頁")).disabled(!model.isReady || model.pageIndex >= model.pageCount - 1)
            Button(action: model.zoomOut) { Label(tr("Zoom Out", "縮小"), systemImage: "minus.magnifyingglass") }
                .help(tr("Zoom out", "縮小")).disabled(!model.isReady)
            Button(action: model.zoomIn) { Label(tr("Zoom In", "放大"), systemImage: "plus.magnifyingglass") }
                .help(tr("Zoom in", "放大")).disabled(!model.isReady)
            Menu {
                Picker(tr("Page Layout", "頁面排列"), selection: $model.layout) {
                    ForEach(PageLayout.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                }
                .pickerStyle(.inline)
                Toggle(tr("Book Mode", "書本模式"), isOn: $model.displaysAsBook)
            } label: { Label(tr("Page Layout", "頁面排列"), systemImage: model.layout.systemImage) }
                .help(tr("Page layout", "頁面排列")).disabled(!model.isReady)
            TextField(tr("Search", "搜尋"), text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .focused($searchFocused)
                .onSubmit(model.submitSearch)
                .onExitCommand(perform: model.clearSearch)
                .disabled(!model.isReady)
                .help(tr("Find text (⌘F) · Return for next result · Esc to clear", "尋找文字（⌘F）・Return 下一個・Esc 清除"))
            Button { showInspector.toggle() } label: { Label(tr("Info", "資訊"), systemImage: "info.circle") }
                .help(tr("Show or hide document info", "顯示或隱藏文件資訊")).disabled(model.document == nil)
        }
    }
}

// MARK: - 尚未開檔

private struct WelcomeView: View {
    let model: ViewerModel

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("BlueViewPDF").font(.title.bold())
            Text(tr("Drop a PDF here, or open one", "把 PDF 拖進來，或按開啟")).foregroundStyle(.secondary)
            Button(tr("Open PDF…", "開啟 PDF…"), action: model.chooseFile)
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            if !model.recent.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Recent", "最近開啟")).font(.headline).padding(.bottom, 2)
                    ForEach(model.recent, id: \.self) { url in
                        Button { model.open(url) } label: {
                            HStack(spacing: 6) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .buttonStyle(.link)
                        .help(url.path)
                    }
                }
                .frame(maxWidth: 360, alignment: .leading)
                .padding(.top, 12)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 有密碼的 PDF

private struct LockedView: View {
    let model: ViewerModel
    @State private var password = ""
    @State private var wrong = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.doc").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(tr("“\(model.title)” is password protected", "「\(model.title)」有密碼保護")).font(.headline)
            SecureField(tr("Password", "密碼"), text: $password)
                .textFieldStyle(.roundedBorder).frame(width: 240)
                .focused($focused)
                .onSubmit(unlock)
            if wrong { Text(tr("Incorrect password", "密碼不正確")).foregroundStyle(.red).font(.callout) }
            Button(tr("Unlock", "解鎖"), action: unlock).keyboardShortcut(.defaultAction).disabled(password.isEmpty)
        }
        .padding(40)
        .onAppear { focused = true }
    }

    private func unlock() {
        wrong = !model.unlock(password)
        if wrong { password = "" }
    }
}

// MARK: - 下方狀態列

private struct StatusBar: View {
    let model: ViewerModel
    @State private var pageText = ""
    @FocusState private var pageFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(tr("Page", "頁"))
            TextField("", text: $pageText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)
                .multilineTextAlignment(.center)
                .focused($pageFocused)
                .onSubmit {
                    if let number = Int(pageText.trimmingCharacters(in: .whitespaces)) { model.goTo(page: number - 1) }
                    syncPage()
                }
            Text("/ \(model.pageCount)").monospacedDigit()
            if let label = model.pageLabel { Text("(\(label))").lineLimit(1) }
            if !model.hits.isEmpty {
                Divider().frame(height: 14)
                Text(tr("Result \((model.hitIndex ?? -1) + 1) of \(model.hits.count)",
                        "第 \((model.hitIndex ?? -1) + 1) 筆，共 \(model.hits.count) 筆")).monospacedDigit()
                Button(action: model.previousHit) { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                Button(action: model.nextHit) { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
            }
            Spacer()
            Button(action: model.zoomOut) { Image(systemName: "minus") }.buttonStyle(.borderless).help(tr("Zoom out", "縮小"))
            Text("\(Int((model.scale * 100).rounded()))%").monospacedDigit().frame(minWidth: 44)
            Button(action: model.zoomIn) { Image(systemName: "plus") }.buttonStyle(.borderless).help(tr("Zoom in", "放大"))
            Button(tr("Fit", "符合"), action: model.zoomToFit).controlSize(.small).disabled(model.autoScales)
            Button("100%", action: model.actualSize).controlSize(.small)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .onAppear(perform: syncPage)
        .onChange(of: model.pageIndex) { if !pageFocused { syncPage() } }
        .onChange(of: model.focusPageRequest) { pageFocused = true }
    }

    private func syncPage() { pageText = "\(model.pageIndex + 1)" }
}

// MARK: - 可拖曳的分隔線

/// 拖曳調整旁邊欄位的寬度；滑鼠移上去顯示左右箭頭；雙擊恢復預設寬度
private struct ResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    let defaultWidth: Double
    /// true：欄位在分隔線左邊（往右拖變寬）；false：欄位在右邊（往左拖變寬）
    let growsToRight: Bool
    @State private var startWidth: Double?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering || startWidth != nil ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor))
            .frame(width: hovering || startWidth != nil ? 3 : 1)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 3)          // 加寬可以點到的範圍
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startWidth ?? width
                        startWidth = start
                        let delta = Double(value.translation.width) * (growsToRight ? 1 : -1)
                        width = min(max(start + delta, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .onTapGesture(count: 2) { withAnimation { width = defaultWidth } }
            .help(tr("Drag to resize · double-click to reset", "拖曳調整寬度・雙擊恢復預設"))
    }
}
