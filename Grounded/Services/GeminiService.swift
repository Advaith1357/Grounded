//
//  GeminiService.swift
//  Grounded
//
//  Talks to Google's Generative Language API (Gemini). Two jobs:
//    1. verifyPhoto(task:imageData:) -> judge a photo proof
//    2. verifyPDF(task:pdfData:)     -> judge a PDF proof (sent as extracted text)
//
//  There's no classify step anymore — the app no longer asks Gemini what kind
//  of proof a task needs. The user always has both Photo and PDF available for
//  the active task, and states what they intend to submit ("Proposed proof")
//  themselves at creation time; that text is passed along as grading context.
//
//  MODEL NAME: Google rotates these. If a call 404s, `model` below is the first
//  thing to change. Confirm the current name at https://aistudio.google.com.
//

import Foundation
import UIKit

/// Abstraction so previews (and "Mock AI Mode" in Settings) can skip the network.
protocol GeminiProviding: Sendable {
    func verifyPhoto(task: FocusTask, imageData: Data) async throws -> VerificationResult
    func verifyPDF(task: FocusTask, pdfData: Data) async throws -> VerificationResult
}

actor GeminiService: GeminiProviding {

    // MARK: - Errors

    enum GeminiError: LocalizedError {
        /// No key in the Keychain and Secrets.swift is still the placeholder.
        case missingAPIKey
        /// Could not reach the server at all (offline, DNS, timeout).
        case network
        /// Server replied with a non-2xx status.
        case http(status: Int, body: String)
        /// Server replied 2xx but the payload could not be understood.
        case malformedResponse(detail: String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "No Gemini API key set. Add one in Settings (The Kernel), or paste it into Secrets.swift for local dev."
            case .network:
                return "Couldn't reach Gemini. Check your internet connection and try again."
            case .http(let status, let body):
                switch status {
                case 400, 401, 403:
                    return "Gemini rejected the request (HTTP \(status)). Your API key is probably wrong, disabled, or missing. \(Self.hint(fromBody: body))"
                case 404:
                    return "Gemini returned 404 — the model name is probably out of date. Update `model` in GeminiService.swift (check aistudio.google.com). \(Self.hint(fromBody: body))"
                case 429:
                    return "Gemini quota exceeded (HTTP 429). Wait a bit, or check usage/limits at aistudio.google.com."
                case 500...599:
                    return "Gemini had a server error (HTTP \(status)). Try again in a moment."
                default:
                    return "Gemini returned an unexpected error (HTTP \(status))."
                }
            case .malformedResponse(let detail):
                return "Gemini's response couldn't be read (\(detail)). Try submitting again."
            }
        }

        private static func hint(fromBody body: String) -> String {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            let clipped = trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
            return "Server said: \(clipped)"
        }
    }

    // MARK: - Config

    /// If Google retires this, calls 404. This is the one line to change.
    private let model = "gemini-3.6-flash"

    private let apiKey: String
    private let session: URLSession

    /// Prefers the Keychain-stored key (set via the Kernel settings sheet);
    /// falls back to the compiled `Secrets.geminiAPIKey` placeholder so the
    /// existing local-dev setup keeps working until a key is pasted in Settings.
    init(apiKey: String = KeychainStore.loadGeminiAPIKey() ?? Secrets.geminiAPIKey) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    private var hasUsableKey: Bool {
        !apiKey.isEmpty && apiKey != "PASTE_YOUR_KEY_HERE"
    }

    private var endpoint: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
    }

    // MARK: - Verify photo

    func verifyPhoto(task: FocusTask, imageData: Data) async throws -> VerificationResult {
        guard hasUsableKey else { throw GeminiError.missingAPIKey }

        guard let jpeg = Self.downscaledJPEG(from: imageData, maxEdge: 1024, quality: 0.7) else {
            throw GeminiError.malformedResponse(detail: "the photo could not be read as an image")
        }

        let body = RequestBody(
            contents: [.init(parts: [
                .init(text: Self.verificationPrompt(for: task), inlineData: nil),
                .init(text: nil, inlineData: .init(mimeType: "image/jpeg", data: jpeg.base64EncodedString()))
            ])],
            generationConfig: .init(responseMimeType: "application/json", temperature: 0.2)
        )

        return try await runVerification(body)
    }

    // MARK: - Verify PDF

    func verifyPDF(task: FocusTask, pdfData: Data) async throws -> VerificationResult {
        guard hasUsableKey else { throw GeminiError.missingAPIKey }

        let extracted = PDFTextExtractor.extractText(from: pdfData)
        let trimmed = extracted.trimmingCharacters(in: .whitespacesAndNewlines)

        // Almost no text -> almost certainly a scanned PDF. Don't spend a call.
        guard trimmed.count >= 25 else {
            return VerificationResult(
                passed: false,
                confidence: 0,
                feedback: "This PDF has no readable text, so it's probably a scan. Re-submit it as a photo instead."
            )
        }

        let clipped = String(trimmed.prefix(6000))
        let prompt = """
        \(Self.verificationPrompt(for: task))

        Below is the extracted text of the user's PDF (it may be truncated):
        \"\"\"
        \(clipped)
        \"\"\"
        """

        let body = RequestBody(
            contents: [.init(parts: [.init(text: prompt, inlineData: nil)])],
            generationConfig: .init(responseMimeType: "application/json", temperature: 0.2)
        )

        return try await runVerification(body)
    }

    // MARK: - Shared verification plumbing

    private func runVerification(_ body: RequestBody) async throws -> VerificationResult {
        let text = try await sendRequest(body)

        guard let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(VerifyPayload.self, from: data) else {
            throw GeminiError.malformedResponse(detail: "verification JSON was not in the expected shape")
        }

        let confidence = Double(min(max(payload.confidence, 0), 100))
        let passed = payload.verified && confidence >= VerificationResult.passThreshold

        return VerificationResult(
            passed: passed,
            confidence: confidence,
            feedback: payload.feedback.isEmpty ? "No feedback returned." : payload.feedback
        )
    }

    private static func verificationPrompt(for task: FocusTask) -> String {
        let proposedProofLine = task.proposedProof.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "\nThe user said their proof would be: \"\(task.proposedProof)\""

        return """
        You are Grounded's proof grader. Be fair but skeptical: reward genuine,
        specific evidence that the task below is actually finished, and reject
        blank or near-blank pages, images or documents unrelated to the task,
        screenshots of someone else's work or of web search results, generic
        stock photos, and work that is only partly done.

        Task: "\(task.title)"\(proposedProofLine)

        Your feedback must be one specific, actionable sentence — name what you
        see and, if failing, what is missing.

        Respond with ONLY this JSON and nothing else:
        {"verified": <true|false>, "confidence": <integer 0-100>, "feedback": "<one sentence>"}
        """
    }

    // MARK: - Networking

    private func sendRequest(_ body: RequestBody) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw GeminiError.malformedResponse(detail: "could not encode the request")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GeminiError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.malformedResponse(detail: "no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GeminiError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        let apiResponse: GenerateContentResponse
        do {
            apiResponse = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        } catch {
            throw GeminiError.malformedResponse(detail: "top-level JSON did not decode")
        }

        if let blockReason = apiResponse.promptFeedback?.blockReason {
            throw GeminiError.malformedResponse(detail: "the prompt was blocked (\(blockReason))")
        }

        guard let text = apiResponse.candidates?.first?.content?.parts?
            .compactMap(\.text).joined(), !text.isEmpty else {
            throw GeminiError.malformedResponse(detail: "no text in the first candidate")
        }

        return text
    }

    // MARK: - Image downscaling

    private static func downscaledJPEG(from data: Data, maxEdge: CGFloat, quality: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let longEdge = max(image.size.width, image.size.height)
        let scale = longEdge > maxEdge ? maxEdge / longEdge : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

// MARK: - Wire types (request)

private struct RequestBody: Encodable {
    struct Content: Encodable {
        struct Part: Encodable {
            let text: String?
            let inlineData: InlineData?
        }
        struct InlineData: Encodable {
            let mimeType: String
            let data: String
        }
        let parts: [Part]
    }
    struct GenerationConfig: Encodable {
        let responseMimeType: String
        let temperature: Double
    }
    let contents: [Content]
    let generationConfig: GenerationConfig
}

// MARK: - Wire types (response)

private struct GenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable { let text: String? }
            let parts: [Part]?
        }
        let content: Content?
    }
    struct PromptFeedback: Decodable { let blockReason: String? }
    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
}

// MARK: - Strict-JSON contract returned *inside* the model's text

private struct VerifyPayload: Decodable {
    let verified: Bool
    let confidence: Int
    let feedback: String
}

// MARK: - Mock provider (SwiftUI previews AND "Mock AI Mode" in Settings)

/// Returns a canned result with no network call. Not `#if DEBUG`-gated: this
/// is a real, user-facing feature (the Settings toggle), not just a preview
/// helper, so it must exist in every build configuration.
struct FakeGeminiService: GeminiProviding {
    var verifyResult: VerificationResult = .init(
        passed: true,
        confidence: 92,
        feedback: "Mock AI Mode: automatically approved without a network call."
    )
    /// When set, every call throws this instead of returning.
    var error: GeminiService.GeminiError?

    func verifyPhoto(task: FocusTask, imageData: Data) async throws -> VerificationResult {
        if let error { throw error }
        return verifyResult
    }
    func verifyPDF(task: FocusTask, pdfData: Data) async throws -> VerificationResult {
        if let error { throw error }
        return verifyResult
    }
}
