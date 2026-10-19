import AppKit
import PDFKit
import XCTest
@testable import BlueViewPDF

/// 測試用的 PDF 產生器
enum Fixture {
    /// 每頁寫一行文字的 PDF（預設 A4）
    static func pdf(pages: [String], size: CGSize = CGSize(width: 595, height: 842)) -> PDFDocument {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for text in pages {
            ctx.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18)]))
            ctx.textPosition = CGPoint(x: 72, y: size.height - 100)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return PDFDocument(data: data as Data)!
    }

    static func write(_ document: PDFDocument, name: String = "test.pdf", options: [PDFDocumentWriteOption: Any] = [:]) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
        XCTAssertTrue(document.write(to: url, withOptions: options))
        return url
    }

    static func defaults() -> UserDefaults {
        let name = "BlueViewPDFTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

final class PDFInfoTests: XCTestCase {
    func testPaperNames() {
        XCTAssertEqual(PDFInfo.paperName(for: CGSize(width: 595.28, height: 841.89)), "A4")
        XCTAssertEqual(PDFInfo.paperName(for: CGSize(width: 612, height: 792)), "Letter")
        XCTAssertTrue(PDFInfo.paperName(for: CGSize(width: 842, height: 595))?.hasPrefix("A4") == true)
        XCTAssertNotEqual(PDFInfo.paperName(for: CGSize(width: 842, height: 595)), "A4")   // 橫式要標示出來
        XCTAssertNil(PDFInfo.paperName(for: CGSize(width: 300, height: 300)))
    }

    func testDimensionsInMillimetres() {
        XCTAssertEqual(PDFInfo.dimensions(CGSize(width: 595.28, height: 841.89)), "210 × 297 mm")
    }

    func testRotatedPageSizeSwaps() {
        let page = Fixture.pdf(pages: ["x"]).page(at: 0)!
        page.rotation = 90
        XCTAssertEqual(PDFInfo.pageSize(page), CGSize(width: 842, height: 595))
    }

    func testNormalizeKangxiRadicals() {
        XCTAssertEqual(PDFTextSearch.normalizeRadicals("第 3 \u{2FB4}的第 1 \u{2F8F}\u{2F42}字"), "第 3 頁的第 1 行文字")
        XCTAssertEqual(PDFTextSearch.normalizeRadicals("abc 中文"), "abc 中文")
    }

    func testCollapseWhitespace() {
        XCTAssertEqual(PDFInfo.collapseWhitespace("  a\n\n b\t c  "), "a b c")
    }

    func testInfoRows() {
        let doc = Fixture.pdf(pages: ["one", "two", "three"])
        doc.documentAttributes = [PDFDocumentAttribute.titleAttribute: "報告", PDFDocumentAttribute.authorAttribute: "Fred"]
        let url = Fixture.write(doc)
        defer { try? FileManager.default.removeItem(at: url) }
        let rows = PDFInfo.rows(for: PDFDocument(url: url)!, url: url, pageIndex: 0)
        let values = Set(rows.map(\.value))
        XCTAssertTrue(values.contains("報告"))
        XCTAssertTrue(values.contains("Fred"))
        XCTAssertTrue(values.contains("3"))
        XCTAssertTrue(values.contains { $0.hasPrefix("210 × 297 mm") })
    }

    func testIsPDF() {
        XCTAssertTrue(PDFFile.isPDF(URL(fileURLWithPath: "/tmp/a.PDF")))
        XCTAssertFalse(PDFFile.isPDF(URL(fileURLWithPath: "/tmp/a.jpg")))
    }
}

final class OutlineTests: XCTestCase {
    func testOutlineTree() {
        let doc = Fixture.pdf(pages: ["intro", "chapter", "section"])
        let root = PDFOutline()
        let chapter = PDFOutline()
        chapter.label = "Chapter\n 1"
        chapter.destination = PDFDestination(page: doc.page(at: 1)!, at: .zero)
        let section = PDFOutline()
        section.label = "Section 1.1"
        section.action = PDFActionGoTo(destination: PDFDestination(page: doc.page(at: 2)!, at: .zero))
        chapter.insertChild(section, at: 0)
        root.insertChild(chapter, at: 0)
        doc.outlineRoot = root

        let tree = OutlineItem.tree(from: doc)
        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree[0].title, "Chapter 1")
        XCTAssertEqual(tree[0].pageIndex, 1)
        XCTAssertEqual(tree[0].children?.first?.title, "Section 1.1")
        XCTAssertEqual(tree[0].children?.first?.pageIndex, 2)   // 寫在動作裡的目的地也要認得
        XCTAssertNil(tree[0].children?.first?.children)
    }

    func testNoOutline() {
        XCTAssertTrue(OutlineItem.tree(from: Fixture.pdf(pages: ["a"])).isEmpty)
    }
}

final class StoreTests: XCTestCase {
    func testPositionStoreRemembersAndEvicts() {
        let store = PositionStore(defaults: Fixture.defaults(), limit: 2)
        let a = URL(fileURLWithPath: "/tmp/a.pdf"), b = URL(fileURLWithPath: "/tmp/b.pdf"), c = URL(fileURLWithPath: "/tmp/c.pdf")
        store.set(5, for: a)
        XCTAssertEqual(store.page(for: a), 5)
        store.set(1, for: b)
        Thread.sleep(forTimeInterval: 0.01)
        store.set(2, for: c)
        XCTAssertNil(store.page(for: a))   // 最舊的被忘掉
        XCTAssertEqual(store.page(for: c), 2)
    }

    func testRecentFilesOrderAndMissingFiles() {
        let recent = RecentFiles(defaults: Fixture.defaults(), limit: 2)
        let doc = Fixture.pdf(pages: ["x"])
        let one = Fixture.write(doc, name: "one.pdf"), two = Fixture.write(doc, name: "two.pdf"), three = Fixture.write(doc, name: "three.pdf")
        defer { [one, two, three].forEach { try? FileManager.default.removeItem(at: $0) } }
        recent.add(one); recent.add(two); recent.add(one)
        XCTAssertEqual(recent.urls.map(\.lastPathComponent), [one.lastPathComponent, two.lastPathComponent])
        recent.add(three)
        XCTAssertEqual(recent.urls.count, 2)
        try? FileManager.default.removeItem(at: three)
        XCTAssertEqual(recent.urls.map(\.lastPathComponent), [one.lastPathComponent])   // 不存在的不列
    }
}

@MainActor
final class ViewerModelTests: XCTestCase {
    func testOpenSearchAndNavigate() {
        let url = Fixture.write(Fixture.pdf(pages: ["apple banana", "cherry", "Banana split", "date"]))
        defer { try? FileManager.default.removeItem(at: url) }
        let model = ViewerModel()
        model.open(url)
        XCTAssertTrue(model.isReady)
        XCTAssertEqual(model.pageCount, 4)

        model.searchText = "banana"
        model.submitSearch()
        XCTAssertEqual(model.hits.map(\.pageIndex), [0, 2])   // 不分大小寫
        XCTAssertEqual(model.sidebarTab, .search)
        let first = model.hitIndex
        model.submitSearch()                                  // 再按一次 Return = 下一個
        XCTAssertNotEqual(model.hitIndex, first)
        model.nextHit()
        XCTAssertEqual(model.hitIndex, first)                 // 繞回來

        model.searchText = "nothing-here"
        model.submitSearch()
        XCTAssertTrue(model.hits.isEmpty)
        model.clearSearch()
        XCTAssertEqual(model.searchedText, "")

        model.goTo(page: 99)                                  // 超出範圍時停在最後一頁
        XCTAssertEqual(model.pdfView.currentPage, model.document?.page(at: 3))
    }

    func testSearchIgnoresSpacesInChinese() {
        let url = Fixture.write(Fixture.pdf(pages: ["封面", "這是第9頁的內容"]))
        defer { try? FileManager.default.removeItem(at: url) }
        let model = ViewerModel()
        model.open(url)
        model.searchText = "第 9 頁"
        model.submitSearch()
        XCTAssertEqual(model.hits.map(\.pageIndex), [1])
    }

    func testLockedPDF() {
        let url = Fixture.write(Fixture.pdf(pages: ["secret"]), name: "locked.pdf",
                                options: [.userPasswordOption: "open-me", .ownerPasswordOption: "owner1"])
        defer { try? FileManager.default.removeItem(at: url) }
        let model = ViewerModel()
        model.open(url)
        XCTAssertTrue(model.isLocked)
        XCTAssertFalse(model.isReady)
        XCTAssertFalse(model.unlock("wrong"))
        XCTAssertTrue(model.unlock("open-me"))
        XCTAssertTrue(model.isReady)
    }

    func testOpenGarbageShowsError() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try? Data("not a pdf".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = ViewerModel()
        model.open(url)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.document)
    }
}
