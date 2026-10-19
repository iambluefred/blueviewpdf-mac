import AppKit
import Observation
import PDFKit

enum PageLayout: String, CaseIterable, Identifiable {
    case single, continuous, twoUp, twoUpContinuous

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: tr("Single Page", "單頁")
        case .continuous: tr("Continuous Scroll", "連續捲動")
        case .twoUp: tr("Two Pages", "雙頁")
        case .twoUpContinuous: tr("Two Pages Continuous", "雙頁連續捲動")
        }
    }

    var systemImage: String {
        switch self {
        case .single: "doc"
        case .continuous: "doc.text"
        case .twoUp: "book"
        case .twoUpContinuous: "book.pages"
        }
    }

    var displayMode: PDFDisplayMode {
        switch self {
        case .single: .singlePage
        case .continuous: .singlePageContinuous
        case .twoUp: .twoUp
        case .twoUpContinuous: .twoUpContinuous
        }
    }
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case thumbnails, outline, search

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thumbnails: tr("Thumbnails", "縮圖")
        case .outline: tr("Contents", "目錄")
        case .search: tr("Search", "搜尋")
        }
    }

    var systemImage: String {
        switch self {
        case .thumbnails: "square.grid.2x2"
        case .outline: "list.bullet.indent"
        case .search: "magnifyingglass"
        }
    }
}

struct SearchHit: Identifiable {
    let id: Int
    let selection: PDFSelection
    let pageIndex: Int
}

/// 目前開啟的 PDF 與檢視狀態。只看不改：不會寫回任何檔案。
@MainActor
@Observable
final class ViewerModel {
    static let shared = ViewerModel()

    /// 整個 App 共用一個 PDFView，縮圖欄、選單指令都直接操作它
    @ObservationIgnored let pdfView = PDFView()
    @ObservationIgnored private let positions = PositionStore()
    @ObservationIgnored private let recentStore = RecentFiles()

    private(set) var url: URL?
    private(set) var document: PDFDocument?
    private(set) var isLocked = false
    private(set) var pageIndex = 0
    private(set) var scale: CGFloat = 1
    private(set) var autoScales = true
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var outline: [OutlineItem] = []
    private(set) var recent: [URL] = []
    var errorMessage: String?

    var sidebarTab: SidebarTab = .thumbnails
    var layout: PageLayout {
        didSet { applyLayout(); UserDefaults.standard.set(layout.rawValue, forKey: "PageLayout") }
    }
    /// 雙頁時第一頁單獨放右邊（像書本封面）
    var displaysAsBook: Bool {
        didSet { applyLayout(); UserDefaults.standard.set(displaysAsBook, forKey: "DisplaysAsBook") }
    }

    var searchText = ""
    private(set) var searchedText = ""
    private(set) var hits: [SearchHit] = []
    private(set) var hitIndex: Int?
    /// 搜尋結果太多時只列前面這些
    let maxHits = 2000

    /// 遞增時讓搜尋框／頁碼框取得焦點
    private(set) var focusSearchRequest = 0
    private(set) var focusPageRequest = 0

    var pageCount: Int { document?.pageCount ?? 0 }
    var isReady: Bool { document != nil && !isLocked }
    var title: String { url?.lastPathComponent ?? "BlueViewPDF" }

    var pageLabel: String? {
        guard let label = document?.page(at: pageIndex)?.label, label != "\(pageIndex + 1)" else { return nil }
        return label
    }

    init() {
        layout = PageLayout(rawValue: UserDefaults.standard.string(forKey: "PageLayout") ?? "") ?? .continuous
        displaysAsBook = UserDefaults.standard.bool(forKey: "DisplaysAsBook")
        recent = recentStore.urls
        pdfView.autoScales = true
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .underPageBackgroundColor
        applyLayout()
        let center = NotificationCenter.default
        center.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pageChanged() }
        }
        center.addObserver(forName: .PDFViewScaleChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scaleChanged() }
        }
    }

    // MARK: - 開檔

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = tr("Choose a PDF to view", "選擇要看的 PDF")
        if let url = url { panel.directoryURL = url.deletingLastPathComponent() }
        if panel.runModal() == .OK, let picked = panel.url { open(picked) }
    }

    func open(_ url: URL) {
        guard let doc = PDFDocument(url: url) else {
            errorMessage = tr("“\(url.lastPathComponent)” can't be opened. It may be damaged or not a PDF.",
                              "無法開啟「\(url.lastPathComponent)」，檔案可能已損毀或不是 PDF。")
            return
        }
        clearSearch()
        self.url = url
        document = doc
        isLocked = doc.isLocked
        recentStore.add(url)
        recent = recentStore.urls
        if isLocked {
            pdfView.document = nil
            outline = []
        } else {
            show(doc)
        }
    }

    /// 輸入密碼解鎖；密碼錯回傳 false
    func unlock(_ password: String) -> Bool {
        guard let document, document.unlock(withPassword: password) else { return false }
        isLocked = false
        show(document)
        return true
    }

    func close() {
        clearSearch()
        pdfView.document = nil
        document = nil
        url = nil
        isLocked = false
        outline = []
        pageIndex = 0
    }

    func clearRecent() {
        recentStore.clear()
        recent = []
    }

    func revealInFinder() {
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func print() {
        guard isReady else { return }
        pdfView.print(with: NSPrintInfo.shared, autoRotate: true)
    }

    private func show(_ doc: PDFDocument) {
        pdfView.document = doc
        outline = OutlineItem.tree(from: doc)
        if outline.isEmpty && sidebarTab == .outline { sidebarTab = .thumbnails }
        if let url, let saved = positions.page(for: url), saved > 0, let page = doc.page(at: saved) {
            pdfView.go(to: page)
        }
        pageChanged()
        scaleChanged()
    }

    // MARK: - 翻頁

    func goTo(page index: Int) {
        guard let page = document?.page(at: min(max(index, 0), pageCount - 1)) else { return }
        pdfView.go(to: page)
    }

    func go(to item: OutlineItem) {
        if let destination = item.destination { pdfView.go(to: destination) }
        else if let index = item.pageIndex { goTo(page: index) }
    }

    func nextPage() { pdfView.goToNextPage(nil) }
    func previousPage() { pdfView.goToPreviousPage(nil) }
    func firstPage() { pdfView.goToFirstPage(nil) }
    func lastPage() { pdfView.goToLastPage(nil) }
    func goBack() { pdfView.goBack(nil); pageChanged() }
    func goForward() { pdfView.goForward(nil); pageChanged() }
    func focusPageField() { focusPageRequest += 1 }

    private func pageChanged() {
        guard let doc = pdfView.document, let page = pdfView.currentPage else { return }
        pageIndex = doc.index(for: page)
        canGoBack = pdfView.canGoBack
        canGoForward = pdfView.canGoForward
        if let url { positions.set(pageIndex, for: url) }
    }

    // MARK: - 縮放

    func zoomToFit() { pdfView.autoScales = true; scaleChanged() }
    func actualSize() { pdfView.scaleFactor = 1; scaleChanged() }
    func zoomIn() { pdfView.zoomIn(nil) }
    func zoomOut() { pdfView.zoomOut(nil) }

    private func scaleChanged() {
        scale = pdfView.scaleFactor
        autoScales = pdfView.autoScales
    }

    private func applyLayout() {
        pdfView.displayMode = layout.displayMode
        pdfView.displaysAsBook = displaysAsBook
        if pdfView.autoScales { pdfView.autoScales = true }   // 換排列方式後重新符合視窗
    }

    // MARK: - 搜尋

    func focusSearch() { focusSearchRequest += 1 }

    /// 按 Return：字串沒變就跳到下一個，變了就重新搜尋
    func submitSearch() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { clearSearch(); return }
        if text == searchedText, !hits.isEmpty { nextHit(); return }
        search(text)
    }

    func search(_ text: String) {
        guard let document, isReady else { return }
        document.cancelFindString()
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var found = document.findString(text, withOptions: options)
        // 找不到時改用自己的比對：康熙部首字（macOS 產生的 PDF 常把「頁」存成「⾴」）視為一般中文字，也不管空白
        if found.isEmpty { found = PDFTextSearch.find(text, in: document, limit: maxHits) }
        hits = found.prefix(maxHits).enumerated().map { i, selection in
            selection.color = .systemYellow
            let index = selection.pages.first.map { document.index(for: $0) } ?? 0
            return SearchHit(id: i, selection: selection, pageIndex: index)
        }
        searchedText = text
        pdfView.highlightedSelections = hits.map(\.selection)
        sidebarTab = .search
        hitIndex = nil
        if hits.isEmpty { NSSound.beep() } else { select(hit: firstHitFromCurrentPage()) }
    }

    func clearSearch() {
        searchText = ""
        searchedText = ""
        hits = []
        hitIndex = nil
        pdfView.highlightedSelections = nil
        pdfView.setCurrentSelection(nil, animate: false)
        if sidebarTab == .search { sidebarTab = .thumbnails }
    }

    func nextHit() { step(by: 1) }
    func previousHit() { step(by: -1) }

    func select(hit index: Int) {
        guard hits.indices.contains(index) else { return }
        hitIndex = index
        let selection = hits[index].selection
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.go(to: selection)
    }

    private func step(by delta: Int) {
        guard !hits.isEmpty else {
            if !searchText.isEmpty { submitSearch() }
            return
        }
        let current = hitIndex ?? (delta > 0 ? -1 : 0)
        select(hit: (current + delta + hits.count) % hits.count)
    }

    /// 從目前這頁開始找第一個結果，不用每次都跳回第一頁
    private func firstHitFromCurrentPage() -> Int {
        hits.firstIndex { $0.pageIndex >= pageIndex } ?? 0
    }
}
