import Foundation

private let maximumHeaderLineLength = 998

struct Message {
  let to: [String]
  let cc: [String]
  let bcc: [String]
  let subject: String
  let body: String
  let reply: ReplyHeaders?
  let attachments: [Attachment]

  var envelopeRecipients: [String] { to + cc + bcc }

  func render(configuration: Configuration) throws -> String {
    guard !to.isEmpty else { throw PigeonError("Provide at least one --to address.") }
    for address in envelopeRecipients { try validateAddress(address) }
    let controlCharacters = CharacterSet.controlCharacters
    guard !subject.isEmpty,
      !subject.unicodeScalars.contains(where: { controlCharacters.contains($0) })
    else { throw PigeonError("The subject must be nonempty and contain no control characters.") }
    let date = DateFormatter()
    date.locale = Locale(identifier: "en_US_POSIX")
    date.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    let sender =
      configuration.senderName.isEmpty
      ? configuration.from : "\(encodedHeader(configuration.senderName)) <\(configuration.from)>"
    let domain = configuration.from.split(separator: "@").last!
    let normalizedBody = body.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
    let textPart = [
      "Content-Type: text/plain; charset=UTF-8", "Content-Transfer-Encoding: base64", "",
      mimeBase64(Data(normalizedBody.utf8)),
    ]
    var headers = ["From: \(sender)", try addressHeader(named: "To", addresses: to)]
    if !cc.isEmpty { try headers.append(addressHeader(named: "Cc", addresses: cc)) }
    if let reply { headers.append(contentsOf: reply.lines) }
    headers += [
      "Subject: \(encodedHeader(subject))", "Date: \(date.string(from: Date()))",
      "Message-ID: <\(UUID().uuidString.lowercased())@\(domain)>", "MIME-Version: 1.0",
    ]
    guard !attachments.isEmpty else { return (headers + textPart + [""]).joined(separator: "\r\n") }

    let boundary = "pigeon-\(UUID().uuidString.lowercased())"
    headers += ["Content-Type: multipart/mixed; boundary=\"\(boundary)\"", "", "--\(boundary)"]
    var lines = headers + textPart
    for attachment in attachments {
      lines += [
        "--\(boundary)", "Content-Type: \(attachment.mediaType)",
        "Content-Transfer-Encoding: base64", attachment.disposition, "",
        mimeBase64(attachment.data),
      ]
    }
    lines += ["--\(boundary)--", ""]
    return lines.joined(separator: "\r\n")
  }

  private func mimeBase64(_ data: Data) -> String {
    data.base64EncodedString(options: [
      .lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed,
    ])
  }

  private func addressHeader(named field: String, addresses: [String]) throws -> String {
    let preferredLineLength = 78
    var lines: [String] = []
    var line = "\(field):"
    for (index, address) in addresses.enumerated() {
      let entry = index == addresses.count - 1 ? address : "\(address),"
      let entryLength = 1 + entry.utf8.count
      guard entryLength <= maximumHeaderLineLength else {
        throw PigeonError("A recipient address is too long for the \(field) header.")
      }
      if line.utf8.count + entryLength > preferredLineLength {
        lines.append(line)
        line = " \(entry)"
      } else {
        line += " \(entry)"
      }
    }
    lines.append(line)
    return lines.joined(separator: "\r\n")
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

struct ReplyHeaders {
  private let parent: String
  private let references: [String]

  init(parent: String, references: [String]) throws {
    self.parent = try Self.messageID(value: parent, option: "--in-reply-to")
    self.references = try references.enumerated()
      .map { index, id in try Self.messageID(value: id, option: "--reference #\(index + 1)") }
  }

  var lines: [String] {
    let chain = references.filter { $0 != parent } + [parent]
    return Self.firstLines(named: "In-Reply-To", id: parent)
      + Self.firstLines(named: "References", id: chain[0]) + chain.dropFirst().map { " \($0)" }
  }

  private static func firstLines(named field: String, id: String) -> [String] {
    let firstLine = "\(field): \(id)"
    if firstLine.utf8.count <= maximumHeaderLineLength { return [firstLine] }
    return ["\(field):", " \(id)"]
  }

  private static func messageID(value: String, option: String) throws -> String {
    let invalidID = PigeonError(
      "\(option) requires a single Message-ID, such as '<id@example.com>'."
    )
    var input = value[...]
    guard value.utf8.allSatisfy({ $0 == 9 || (32 ... 126).contains($0) }),
      consumeCommentsAndWhitespace(&input)
    else { throw invalidID }

    let atom = #"[A-Za-z0-9!#$%&'*+/=?^_\x60{|}~-]+"#
    let dotAtom = #"\#(atom)(?:\.\#(atom))*"#
    let address = #"(?:\#(dotAtom)|"\#(dotAtom)")@(?:\#(dotAtom)|\[[\x21-\x5A\x5E-\x7E]*\])"#
    let hasBrackets = input.hasPrefix("<")
    let pattern = hasBrackets ? #"\A<\#(address)>"# : #"\A\#(address)"#
    guard let match = input.range(of: pattern, options: .regularExpression) else { throw invalidID }
    var suffix = input[match.upperBound...]
    guard consumeCommentsAndWhitespace(&suffix), suffix.isEmpty else { throw invalidID }

    let matched = input[match]
    let id = hasBrackets ? matched.dropFirst().dropLast() : matched
    let bracketedID: String
    if id.hasPrefix("\""), let quote = id.dropFirst().firstIndex(of: "\"") {
      // A quoted dot-atom identifies the same message with or without quotes.
      bracketedID = "<\(id.dropFirst()[..<quote])\(id[id.index(after: quote)...])>"
    } else {
      bracketedID = "<\(id)>"
    }
    guard 1 + bracketedID.utf8.count <= maximumHeaderLineLength else {
      throw PigeonError("The Message-ID for \(option) exceeds the header line limit.")
    }
    return bracketedID
  }

  private static func consumeCommentsAndWhitespace(_ input: inout Substring) -> Bool {
    var depth = 0
    while let character = input.first {
      switch character {
      case " ", "\t": break
      case "(": depth += 1
      case ")" where depth > 0: depth -= 1
      case "\\" where depth > 0:
        input.removeFirst()
        guard !input.isEmpty else { return false }
      default: if depth == 0 { return true }
      }
      input.removeFirst()
    }
    return depth == 0
  }
}
