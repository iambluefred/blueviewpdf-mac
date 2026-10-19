import SwiftUI

/// 右側資訊面板：文件屬性
struct InspectorView: View {
    let model: ViewerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if let url = model.url {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 32, height: 32)
                    }
                    Text(model.title).font(.headline).lineLimit(3).textSelection(.enabled)
                }
                if model.isLocked {
                    Text(tr("Unlock the PDF to see its details", "解鎖後才能看到文件資訊")).foregroundStyle(.secondary)
                } else if let document = model.document {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                        ForEach(PDFInfo.rows(for: document, url: model.url, pageIndex: model.pageIndex)) { row in
                            GridRow {
                                Text(row.label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                Text(row.value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .font(.callout)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background.secondary)
    }
}
