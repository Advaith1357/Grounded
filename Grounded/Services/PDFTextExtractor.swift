//
//  PDFTextExtractor.swift
//  Grounded
//
//  Pulls plain text out of a PDF using PDFKit. Used before sending a PDF proof
//  to Gemini as text (cheaper and more reliable than sending the raw file).
//

import Foundation
import PDFKit

enum PDFTextExtractor {

    /// Concatenates the text of the first `maxPages` pages. Returns "" if the
    /// data is not a readable PDF. A near-empty result usually means the PDF is
    /// a scan (images only) with no embedded text.
    static func extractText(from data: Data, maxPages: Int = 10) -> String {
        guard let document = PDFDocument(data: data) else { return "" }

        let pageCount = min(document.pageCount, maxPages)
        var pieces: [String] = []
        pieces.reserveCapacity(pageCount)

        for index in 0..<pageCount {
            if let page = document.page(at: index), let text = page.string {
                pieces.append(text)
            }
        }

        return pieces.joined(separator: "\n")
    }
}
