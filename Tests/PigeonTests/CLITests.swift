import Foundation
import Testing

final class CLITests {
  @Test func dryRunRoutesRepeatableOptionsAndRequiresAReplyParent() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "pigeon-test-\(UUID().uuidString)"
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let config = """
      {
        "host": "smtp.example.com", "port": 587, "senderName": "Sender",
        "username": "sender@example.com", "from": "sender@example.com",
        "imap": {"host": "imap.example.com", "port": 993, "sentMailbox": "Sent"}
      }
      """
    try config.write(
      to: directory.appendingPathComponent("config.json"),
      atomically: true,
      encoding: .utf8
    )
    try "Hello\n"
      .write(to: directory.appendingPathComponent("body.txt"), atomically: true, encoding: .utf8)
    for filename in ["請求 書.pdf", "notes with spaces.txt"] {
      try Data([0x00, 0xff]).write(to: directory.appendingPathComponent(filename))
    }
    let args = [
      "send", "--config", "config.json", "--subject", "Re: Hello", "--body-file", "body.txt",
      "--dry-run", "--to", "first@example.com", "--cc", "copy1@example.com", "--bcc",
      "blind1@example.com", "--to", "second@example.com", "--cc", "copy2@example.com", "--bcc",
      "blind2@example.com", "--reference", "<root@example.com>", "--reference",
      "<middle@example.com>", "--attach", "請求 書.pdf", "--attach", "notes with spaces.txt",
    ]

    let preview = try run(
      arguments: args + ["--in-reply-to", "<parent@example.com>"],
      directory: directory
    )
    #expect(preview.status == 0, "\(preview.output)")
    #expect(!preview.output.contains("\r"))
    #expect(preview.output.contains("\nAttachment: 請求 書.pdf\n"))
    #expect(preview.output.contains("\nAttachment: notes with spaces.txt\n"))
    #expect(preview.output.contains("\nTo: first@example.com, second@example.com\n"))
    #expect(preview.output.contains("\nCc: copy1@example.com, copy2@example.com\n"))
    #expect(preview.output.contains("\nBcc (SMTP only): blind1@example.com, blind2@example.com\n"))
    #expect(preview.output.contains("\nIn-Reply-To: <parent@example.com>\n"))
    let unfolded = preview.output.replacingOccurrences(of: "\n ", with: " ")
    #expect(
      unfolded.contains(
        "\nReferences: <root@example.com> <middle@example.com> <parent@example.com>\n"
      )
    )

    let missingParent = try run(arguments: args, directory: directory)
    #expect(missingParent.status == 1)
    #expect(missingParent.output.contains("--reference requires --in-reply-to."))

    let invalidReference = try run(
      arguments: args + ["--in-reply-to", "<parent@example.com>", "--reference", "invalid"],
      directory: directory
    )
    #expect(invalidReference.status == 1)
    #expect(invalidReference.output.contains("--reference #3 requires a single Message-ID"))
  }

  private func run(arguments: [String], directory: URL) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = Bundle(for: CLITests.self).bundleURL.deletingLastPathComponent()
      .appendingPathComponent("pigeon")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.environment = [:]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output

    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
  }
}
