import Foundation

struct Message {
    let recipients: [String]
    let subject: String
    let body: String

    func render(configuration: Configuration) throws -> String {
        guard !recipients.isEmpty else { throw PigeonError("Provide at least one --to address.") }
        for address in recipients { try validateAddress(address) }
        let controlCharacters = CharacterSet.controlCharacters
        guard !subject.isEmpty,
              !subject.unicodeScalars.contains(where: { controlCharacters.contains($0) }) else {
            throw PigeonError("The subject must be nonempty and contain no control characters.")
        }
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let sender = configuration.senderName.isEmpty
            ? configuration.from
            : "\(encodedHeader(configuration.senderName)) <\(configuration.from)>"
        let domain = configuration.from.split(separator: "@").last!
        let normalizedBody = body.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        let encodedBody = Data(normalizedBody.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        return [
            "From: \(sender)",
            "To: \(recipients.joined(separator: ", "))",
            "Subject: \(encodedHeader(subject))",
            "Date: \(date.string(from: Date()))",
            "Message-ID: <\(UUID().uuidString.lowercased())@\(domain)>",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8",
            "Content-Transfer-Encoding: base64",
            "",
            encodedBody,
            "",
        ].joined(separator: "\r\n")
    }

    private func encodedHeader(_ value: String) -> String {
        var chunks: [String] = []
        var chunk = ""
        for character in value {
            if (chunk + String(character)).utf8.count > 42, !chunk.isEmpty {
                chunks.append(chunk)
                chunk = ""
            }
            chunk.append(character)
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        return chunks.map { "=?UTF-8?B?\(Data($0.utf8).base64EncodedString())?=" }
            .joined(separator: "\r\n ")
    }
}
