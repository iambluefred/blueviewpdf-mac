import Foundation
import PDFKit
import UniformTypeIdentifiers

/// 判斷檔案是不是 PDF
enum PDFFile {
    static func isPDF(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "pdf" { return true }
        let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        return type?.conforms(to: .pdf) ?? false
    }
}

/// 目錄（書籤）樹
struct OutlineItem: Identifiable {
    let id: String
    let title: String
    let pageIndex: Int?
    let destination: PDFDestination?
    let children: [OutlineItem]?

    static func tree(from document: PDFDocument) -> [OutlineItem] {
        guard let root = document.outlineRoot else { return [] }
        return items(of: root, in: document, prefix: "")
    }

    private static func items(of node: PDFOutline, in document: PDFDocument, prefix: String) -> [OutlineItem] {
        (0..<node.numberOfChildren).compactMap { i in
            guard let child = node.child(at: i) else { return nil }
            let id = prefix + "\(i)"
            let kids = items(of: child, in: document, prefix: id + ".")
            // 目的地可能寫在 destination，也可能寫在「跳到頁面」動作裡
            let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
            let page = destination?.page.map { document.index(for: $0) }
            let title = PDFInfo.collapseWhitespace(child.label ?? "")
            return OutlineItem(id: id, title: title.isEmpty ? "—" : title, pageIndex: page,
                               destination: destination, children: kids.isEmpty ? nil : kids)
        }
    }
}

/// 文件資訊（資訊面板用）
enum PDFInfo {
    struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    static func rows(for document: PDFDocument, url: URL?, pageIndex: Int) -> [Row] {
        var rows: [Row] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { rows.append(Row(label: label, value: value)) }
        }
        let attrs = document.documentAttributes ?? [:]
        add(tr("Title", "標題"), attrs[PDFDocumentAttribute.titleAttribute] as? String)
        add(tr("Author", "作者"), attrs[PDFDocumentAttribute.authorAttribute] as? String)
        add(tr("Subject", "主旨"), attrs[PDFDocumentAttribute.subjectAttribute] as? String)
        if let keywords = attrs[PDFDocumentAttribute.keywordsAttribute] {
            add(tr("Keywords", "關鍵字"), (keywords as? [String])?.joined(separator: ", ") ?? keywords as? String)
        }
        add(tr("Pages", "頁數"), "\(document.pageCount)")
        if let page = document.page(at: pageIndex) {
            let size = pageSize(page)
            let paper = paperName(for: size).map { " (\($0))" } ?? ""
            add(tr("Page Size", "頁面尺寸"), dimensions(size) + paper)
        }
        if let url, let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            add(tr("File Size", "檔案大小"), ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        add(tr("PDF Version", "PDF 版本"), "\(document.majorVersion).\(document.minorVersion)")
        add(tr("Created", "建立日期"), (attrs[PDFDocumentAttribute.creationDateAttribute] as? Date).map(format))
        add(tr("Modified", "修改日期"), (attrs[PDFDocumentAttribute.modificationDateAttribute] as? Date).map(format))
        add(tr("Creator", "建立程式"), attrs[PDFDocumentAttribute.creatorAttribute] as? String)
        add(tr("Producer", "產生程式"), attrs[PDFDocumentAttribute.producerAttribute] as? String)
        add(tr("Encrypted", "加密"), document.isEncrypted ? tr("Yes", "是") : tr("No", "否"))
        if document.isEncrypted {
            add(tr("Copying", "允許複製"), document.allowsCopying ? tr("Allowed", "允許") : tr("Not allowed", "不允許"))
            add(tr("Printing", "允許列印"), document.allowsPrinting ? tr("Allowed", "允許") : tr("Not allowed", "不允許"))
        }
        if let url { add(tr("Location", "位置"), url.deletingLastPathComponent().path) }
        return rows
    }

    /// 頁面實際看到的尺寸（點，已考慮旋轉）
    static func pageSize(_ page: PDFPage) -> CGSize {
        let box = page.bounds(for: .cropBox).size
        return page.rotation % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
    }

    /// 例如「210 × 297 mm」
    static func dimensions(_ size: CGSize) -> String {
        let mm = { (points: CGFloat) in Int((points / 72 * 25.4).rounded()) }
        return "\(mm(size.width)) × \(mm(size.height)) mm"
    }

    private static let papers: [(String, CGSize)] = [
        ("A3", CGSize(width: 842, height: 1191)), ("A4", CGSize(width: 595, height: 842)),
        ("A5", CGSize(width: 420, height: 595)), ("B5", CGSize(width: 499, height: 709)),
        ("Letter", CGSize(width: 612, height: 792)), ("Legal", CGSize(width: 612, height: 1008)),
        ("Tabloid", CGSize(width: 792, height: 1224)),
    ]

    /// 常見紙張名稱（直式或橫式都認得，誤差 3 點以內）
    static func paperName(for size: CGSize) -> String? {
        let short = min(size.width, size.height), long = max(size.width, size.height)
        guard let paper = papers.first(where: { abs($0.1.width - short) <= 3 && abs($0.1.height - long) <= 3 }) else { return nil }
        return size.width > size.height ? paper.0 + tr(" landscape", " 橫式") : paper.0
    }

    /// 搜尋結果前後的文字
    static func snippet(_ selection: PDFSelection) -> String {
        guard let context = selection.copy() as? PDFSelection else { return selection.string ?? "" }
        context.extend(atStart: 20)
        context.extend(atEnd: 50)
        return collapseWhitespace(context.string ?? "")
    }

    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// 記住每個檔案看到第幾頁（最多 200 個檔案，舊的先忘）
struct PositionStore {
    var defaults: UserDefaults = .standard
    var key = "LastPages"
    var limit = 200

    func page(for url: URL) -> Int? {
        guard let entry = all()[url.standardizedFileURL.path], let page = entry.first else { return nil }
        return Int(page)
    }

    func set(_ page: Int, for url: URL) {
        var entries = all()
        entries[url.standardizedFileURL.path] = [Double(page), Date().timeIntervalSince1970]
        if entries.count > limit {
            let oldest = entries.sorted { ($0.value.last ?? 0) < ($1.value.last ?? 0) }.prefix(entries.count - limit)
            for (path, _) in oldest { entries[path] = nil }
        }
        defaults.set(entries, forKey: key)
    }

    private func all() -> [String: [Double]] {
        defaults.dictionary(forKey: key) as? [String: [Double]] ?? [:]
    }
}

/// 最近開啟的檔案（最多 10 個，已不存在的檔案不顯示）
struct RecentFiles {
    var defaults: UserDefaults = .standard
    var key = "RecentFiles"
    var limit = 10

    var urls: [URL] {
        (defaults.stringArray(forKey: key) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    func add(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = (defaults.stringArray(forKey: key) ?? []).filter { $0 != path }
        paths.insert(path, at: 0)
        defaults.set(Array(paths.prefix(limit)), forKey: key)
    }

    func clear() { defaults.removeObject(forKey: key) }
}

/// PDFKit 找不到時的備用搜尋
enum PDFTextSearch {
    /// 把康熙部首（U+2F00–U+2FDF）與部首補充（U+2E80–U+2EFF）換成一般中文字。
    /// 一個字只換成一個字，所以位置不變，可以直接拿來選取頁面上的文字。
    static func normalizeRadicals(_ text: String) -> String {
        var units = Array(text.utf16)
        for (i, unit) in units.enumerated() where (0x2E80...0x2FDF).contains(unit) {
            guard let scalar = Unicode.Scalar(unit) else { continue }
            let mapped = Array(String(Character(scalar)).precomposedStringWithCompatibilityMapping.utf16)
            if mapped.count == 1 { units[i] = mapped[0] }
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// 先找原字串，找不到再找去掉空白的版本（PDF 抽出的中文常沒有空白）
    static func find(_ query: String, in document: PDFDocument, limit: Int) -> [PDFSelection] {
        let normalized = normalizeRadicals(query)
        let compact = normalized.filter { !$0.isWhitespace }
        for needle in [normalized, compact] where !needle.isEmpty {
            let found = find(exactly: needle, in: document, limit: limit)
            if !found.isEmpty { return found }
            if needle == compact { break }
        }
        return []
    }

    private static func find(exactly needle: String, in document: PDFDocument, limit: Int) -> [PDFSelection] {
        var result: [PDFSelection] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let raw = page.string else { continue }
            let text = normalizeRadicals(raw) as NSString
            var search = NSRange(location: 0, length: text.length)
            while result.count < limit {
                let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: search)
                if range.location == NSNotFound { break }
                if let selection = page.selection(for: range) { result.append(selection) }
                let next = range.location + max(range.length, 1)
                search = NSRange(location: next, length: text.length - next)
            }
            if result.count >= limit { break }
        }
        return result
    }
}
