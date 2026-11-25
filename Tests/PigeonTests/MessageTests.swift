import Foundation
import Testing

@testable import Pigeon

struct MessageTests {
  private let configuration = Configuration(
    host: "smtp.example.com",
    port: 587,
    username: "sender@example.com",
    from: "sender@example.com",
    imap: IMAPConfiguration(host: "imap.example.com", port: 993, sentMailbox: "Sent"),
    senderName: "Sender"
  )

  @Test(arguments: [false, true]) func attachmentsPreserveContentAndMessageHeaders(
    isReply: Bool
  ) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "pigeon-test-\(UUID().uuidString)"
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pdfBytes = Data(UInt8.min ... UInt8.max)
    let textBytes = Data("Notes\r\n".utf8)
    let pdf = directory.appendingPathComponent("請求 書.pdf")
    let notes = directory.appendingPathComponent("notes with spaces.txt")
    try pdfBytes.write(to: pdf)
    try textBytes.write(to: notes)
    let reply =
      isReply
      ? try ReplyHeaders(parent: "parent@example.com", references: ["root@example.com"]) : nil
    let message = Message(
      to: ["to1@example.com", "to2@example.com"],
      cc: ["cc1@example.com", "cc2@example.com"],
      bcc: ["bcc1@example.com", "bcc2@example.com"],
      subject: isReply ? "Re: Hello" : "Hello",
      body: "Body\nSecond line",
      reply: reply,
      attachments: [try Attachment(path: pdf.path), try Attachment(path: notes.path)]
    )

    let rendered = try message.render(configuration: configuration)
    let multipart = try #require(
      rendered.components(separatedBy: "\r\n")
        .first { $0.hasPrefix("Content-Type: multipart/mixed;") }
    )
    let boundary = try #require(multipart.split(separator: "\"").dropFirst().first)
    let parts = rendered.components(separatedBy: "\r\n--\(boundary)")
    try #require(parts.count == 5)
    #expect(parts.last == "--\r\n")
    #expect(parts[0].contains("\r\nTo: to1@example.com, to2@example.com\r\n"))
    #expect(parts[0].contains("\r\nCc: cc1@example.com, cc2@example.com\r\n"))
    #expect(!parts[0].lowercased().contains("\r\nbcc:"))
    for address in message.bcc { #expect(!parts[0].contains(address)) }
    #expect(
      message.envelopeRecipients == [
        "to1@example.com", "to2@example.com", "cc1@example.com", "cc2@example.com",
        "bcc1@example.com", "bcc2@example.com",
      ]
    )
    #expect(parts[0].contains("\r\nIn-Reply-To: <parent@example.com>\r\n") == isReply)
    #expect(
      parts[0].contains("\r\nReferences: <root@example.com>\r\n <parent@example.com>\r\n")
        == isReply
    )

    let expectedParts = [
      (
        type: "text/plain; charset=UTF-8", filename: nil as String?,
        bytes: Data("Body\r\nSecond line".utf8)
      ),
      (
        type: "application/pdf", filename: "filename*=UTF-8''%E8%AB%8B%E6%B1%82%20%E6%9B%B8.pdf",
        bytes: pdfBytes
      ), (type: "text/plain", filename: #"filename="notes with spaces.txt""#, bytes: textBytes),
    ]
    for (part, expected) in zip(parts.dropFirst().dropLast(), expectedParts) {
      let sections = part.components(separatedBy: "\r\n\r\n")
      try #require(sections.count == 2)
      let headers = sections[0]
      #expect(headers.contains("\r\nContent-Type: \(expected.type)\r\n"))
      #expect(headers.contains("\r\nContent-Transfer-Encoding: base64"))
      if let filename = expected.filename {
        #expect(headers.contains("\r\nContent-Disposition: attachment;"))
        #expect(headers.contains(filename))
      }
      let base64 = sections[1]
      #expect(base64.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 76 })
      #expect(
        Data(base64Encoded: base64.replacingOccurrences(of: "\r\n", with: "")) == expected.bytes
      )
    }
  }

  @Test func blindCopiesAreOnlyEnvelopeRecipients() throws {
    let message = Message(
      to: ["to1@example.com", "to2@example.com"],
      cc: ["cc1@example.com", "cc2@example.com"],
      bcc: ["bcc1@example.com", "bcc2@example.com"],
      subject: "Hello",
      body: "Hello!",
      reply: nil,
      attachments: []
    )

    let arguments = MailClient.smtpArguments(
      configuration: configuration,
      message: message,
      messageURL: URL(fileURLWithPath: "/message.eml")
    )
    let smtpRecipients = zip(arguments, arguments.dropFirst())
      .compactMap { option, value in option == "--mail-rcpt" ? value : nil }
    #expect(
      smtpRecipients == [
        "to1@example.com", "to2@example.com", "cc1@example.com", "cc2@example.com",
        "bcc1@example.com", "bcc2@example.com",
      ]
    )
    let rendered = try message.render(configuration: configuration)
    #expect(rendered.contains("\r\nTo: to1@example.com, to2@example.com\r\n"))
    #expect(rendered.contains("\r\nCc: cc1@example.com, cc2@example.com\r\n"))
    #expect(!rendered.lowercased().contains("\r\nbcc:"))
    for address in message.bcc { #expect(!rendered.contains(address)) }
  }

  @Test func toOnlyMessageOmitsOptionalHeaders() throws {
    let message = Message(
      to: ["to@example.com"],
      cc: [],
      bcc: [],
      subject: "Hello",
      body: "Hello!",
      reply: nil,
      attachments: []
    )

    let rendered = try message.render(configuration: configuration)
    #expect(message.envelopeRecipients == ["to@example.com"])
    #expect(rendered.contains("\r\nContent-Type: text/plain; charset=UTF-8\r\n"))
    #expect(!rendered.contains("multipart/mixed"))
    #expect(!rendered.contains("\r\nCc:"))
    #expect(!rendered.contains("\r\nBcc:"))
    #expect(!rendered.contains("\r\nIn-Reply-To:"))
    #expect(!rendered.contains("\r\nReferences:"))
  }

  @Test func longRecipientHeadersFoldWithoutChangingAddresses() throws {
    let to = (1 ... 60).map { "primary-\($0)@example.com" }
    let cc = (1 ... 60).map { "copy-\($0)@example.com" }
    let message = Message(
      to: to,
      cc: cc,
      bcc: [],
      subject: "Hello",
      body: "Hello!",
      reply: nil,
      attachments: []
    )

    let rendered = try message.render(configuration: configuration)
    let lines = rendered.split(separator: "\r\n")
    let toStart = try #require(lines.firstIndex { $0.hasPrefix("To:") })
    let ccStart = try #require(lines.firstIndex { $0.hasPrefix("Cc:") })
    let subjectStart = try #require(lines.firstIndex { $0.hasPrefix("Subject:") })

    #expect(lines[toStart ..< subjectStart].allSatisfy { $0.utf8.count <= 78 })
    #expect(lines[toStart ..< ccStart].joined() == "To: \(to.joined(separator: ", "))")
    #expect(lines[ccStart ..< subjectStart].joined() == "Cc: \(cc.joined(separator: ", "))")
  }

  @Test func rejectsAddressThatCannotFitOnAHeaderLine() {
    let message = Message(
      to: ["to@example.com"],
      cc: [String(repeating: "a", count: 998) + "@example.com"],
      bcc: [],
      subject: "Hello",
      body: "Hello!",
      reply: nil,
      attachments: []
    )

    #expect(throws: PigeonError.self) { try message.render(configuration: configuration) }
  }

  @Test func copyRecipientsCannotReplaceTo() {
    let message = Message(
      to: [],
      cc: ["cc@example.com"],
      bcc: ["bcc@example.com"],
      subject: "Hello",
      body: "Hello!",
      reply: nil,
      attachments: []
    )

    #expect(throws: PigeonError.self) { try message.render(configuration: configuration) }
  }

  @Test(arguments: ["invalid", "address@example.com\r\nBcc: injected@example.com"])
  func rejectsInvalidCopyAddresses(_ address: String) {
    let invalidCc = Message(
      to: ["to@example.com"],
      cc: [address],
      bcc: [],
      subject: "Hello",
      body: "Hello!",
      reply: nil,
      attachments: []
    )
    let invalidBcc = Message(
      to: ["to@example.com"],
      cc: [],
      bcc: [address],
      subject: "Hello",
      body: "Hello!",
      reply: nil,
      attachments: []
    )

    #expect(throws: PigeonError.self) { try invalidCc.render(configuration: configuration) }
    #expect(throws: PigeonError.self) { try invalidBcc.render(configuration: configuration) }
  }

  @Test func replyRendersParentAndAncestryHeaders() throws {
    let reply = try ReplyHeaders(
      parent: "parent@example.com",
      references: ["<root@example.com>", "middle@example.com", "<parent@example.com>"]
    )
    let message = Message(
      to: ["to@example.com"],
      cc: [],
      bcc: [],
      subject: "Re: Hello",
      body: "Hello!",
      reply: reply,
      attachments: []
    )

    let rendered = try message.render(configuration: configuration)
    #expect(rendered.contains("\r\nIn-Reply-To: <parent@example.com>\r\n"))
    #expect(
      rendered.contains(
        "\r\nReferences: <root@example.com>\r\n <middle@example.com>\r\n <parent@example.com>\r\n"
      )
    )
    #expect(rendered.contains("\r\nMessage-ID: <"))
    #expect(!rendered.contains("\r\nMessage-ID: <parent@example.com>"))
  }

  @Test func replyWithoutAncestryReferencesItsParent() throws {
    let reply = try ReplyHeaders(parent: "<parent@example.com>", references: [])

    #expect(
      reply.lines == ["In-Reply-To: <parent@example.com>", "References: <parent@example.com>"]
    )
  }

  @Test func replyAcceptsCommentsAndNormalizesQuotedDotAtoms() throws {
    let reply = try ReplyHeaders(
      parent: #" (sender (legacy)) <"parent.id"@example.com> (copy \)) "#,
      references: ["<root@example.com> (sender)", #" <"parent.id"@example.com>"#]
    )

    #expect(
      reply.lines == [
        "In-Reply-To: <parent.id@example.com>", "References: <root@example.com>",
        " <parent.id@example.com>",
      ]
    )
  }

  @Test func replyMessageIDRespectsHeaderLineLimit() throws {
    let domain = "@example.com"
    let availableBytes = 998 - " <\(domain)>".utf8.count
    let localPart = String(repeating: "a", count: availableBytes)
    let longID = localPart + domain
    let reply = try ReplyHeaders(parent: longID, references: [])
    let replyWithLongReference = try ReplyHeaders(
      parent: "parent@example.com",
      references: [longID]
    )

    #expect(reply.lines == ["In-Reply-To:", " <\(longID)>", "References:", " <\(longID)>"])
    #expect(
      replyWithLongReference.lines == [
        "In-Reply-To: <parent@example.com>", "References:", " <\(longID)>", " <parent@example.com>",
      ]
    )
    #expect(reply.lines.allSatisfy { $0.utf8.count <= 998 })
    #expect(throws: PigeonError.self) {
      try ReplyHeaders(parent: localPart + "a" + domain, references: [])
    }
  }

  @Test(arguments: [
    "invalid", "<one@example.com> <two@example.com>",
    "<parent@example.com>\r\nBcc: injected@example.com", "<parent@example.com> (unclosed",
  ]) func rejectsMalformedParentOrReference(_ id: String) {
    #expect(throws: PigeonError.self) { try ReplyHeaders(parent: id, references: []) }
    #expect(throws: PigeonError.self) {
      try ReplyHeaders(parent: "<parent@example.com>", references: [id])
    }
  }
}
