import PDFKit
import SwiftUI

/// 主要的 PDF 顯示區（App 共用同一個 PDFView）
struct PDFKitView: NSViewRepresentable {
    let model: ViewerModel

    func makeNSView(context: Context) -> PDFView { model.pdfView }
    func updateNSView(_ nsView: PDFView, context: Context) {}
}

/// 左側欄：縮圖／目錄／搜尋結果
struct SidebarView: View {
    @Bindable var model: ViewerModel
    let width: Double

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.sidebarTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Image(systemName: tab.systemImage).help(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            switch model.sidebarTab {
            case .thumbnails: ThumbnailsView(model: model, width: width)
            case .outline: OutlineListView(model: model)
            case .search: SearchResultsView(model: model)
            }
        }
        .background(.background.secondary)
    }
}

private struct ThumbnailsView: NSViewRepresentable {
    let model: ViewerModel
    let width: Double

    func makeNSView(context: Context) -> PDFThumbnailView {
        let view = PDFThumbnailView()
        view.pdfView = model.pdfView
        view.maximumNumberOfColumns = 1
        view.backgroundColor = .clear
        view.labelFont = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return view
    }

    func updateNSView(_ view: PDFThumbnailView, context: Context) {
        // 縮圖跟著側邊欄寬度變大變小（A4 比例）
        let w = max(60, width - 56)
        let size = CGSize(width: w, height: w * 1.42)
        if view.thumbnailSize != size { view.thumbnailSize = size }
    }
}

private struct OutlineListView: View {
    let model: ViewerModel

    var body: some View {
        if model.outline.isEmpty {
            Placeholder(icon: "list.bullet.indent", text: tr("This PDF has no table of contents", "這份 PDF 沒有目錄"))
        } else {
            List(model.outline, children: \.children) { item in
                Button { model.go(to: item) } label: {
                    HStack {
                        Text(item.title).lineLimit(2)
                        Spacer(minLength: 4)
                        if let page = item.pageIndex {
                            Text("\(page + 1)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fontWeight(isCurrent(item) ? .semibold : .regular)
            }
            .listStyle(.sidebar)
        }
    }

    /// 目前所在的章節：頁碼不超過目前頁的最後一個項目
    private func isCurrent(_ item: OutlineItem) -> Bool {
        let top = model.outline.last { ($0.pageIndex ?? .max) <= model.pageIndex }
        return top?.id == item.id
    }
}

private struct SearchResultsView: View {
    let model: ViewerModel

    var body: some View {
        if model.searchedText.isEmpty {
            Placeholder(icon: "magnifyingglass", text: tr("Type in the search field and press Return", "在搜尋框輸入文字後按 Return"))
        } else if model.hits.isEmpty {
            Placeholder(icon: "magnifyingglass", text: tr("No results for “\(model.searchedText)”", "找不到「\(model.searchedText)」"))
        } else {
            ScrollViewReader { proxy in
                List(model.hits) { hit in
                    SearchHitRow(model: model, hit: hit)
                        .id(hit.id)
                        .listRowBackground(hit.id == model.hitIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                }
                .listStyle(.sidebar)
                .onChange(of: model.hitIndex) { _, index in
                    if let index { withAnimation { proxy.scrollTo(index) } }
                }
            }
            if model.hits.count >= model.maxHits {
                Text(tr("Showing the first \(model.maxHits) results", "只列出前 \(model.maxHits) 筆"))
                    .font(.caption).foregroundStyle(.secondary).padding(6)
            }
        }
    }
}

private struct SearchHitRow: View {
    let model: ViewerModel
    let hit: SearchHit
    /// 前後文等列出現時才算（結果很多時不會卡）
    @State private var snippet: String?

    var body: some View {
        Button { model.select(hit: hit.id) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Page \(hit.pageIndex + 1)", "第 \(hit.pageIndex + 1) 頁"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(snippet ?? hit.selection.string ?? "").lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { if snippet == nil { snippet = PDFInfo.snippet(hit.selection) } }
    }
}

struct Placeholder: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title)
            Text(text).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
