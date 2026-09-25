import SwiftUI
import PDFKit

struct PDFPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        // Match the crop box the card sizes against, and separate stacked pages so a white page
        // doesn't blend into a light card surface.
        view.displayBox = .cropBox
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}
