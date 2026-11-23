import Foundation

enum MailClient {
  static func submit(
    configuration: Configuration,
    message: Message,
    rendered: String,
    password: String
  ) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "pigeon-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    var preserveMessage = false
    defer { if !preserveMessage { try? FileManager.default.removeItem(at: directory) } }
    let messageURL = directory.appendingPathComponent("message.eml")
    guard
      FileManager.default.createFile(
        atPath: messageURL.path,
        contents: Data(rendered.utf8),
        attributes: [.posixPermissions: 0o600]
      )
    else { throw PigeonError("Could not create the private temporary message file.") }

    try IMAP.checkMailbox(configuration: configuration, password: password)
    do {
      try Curl.run(
        arguments: smtpArguments(
          configuration: configuration,
          message: message,
          messageURL: messageURL
        ),
        username: configuration.username,
        password: password
      )
    } catch {
      throw PigeonError(
        "SMTP submission failed: \(error) Delivery may be uncertain; check the destination before retrying."
      )
    }
    do {
      try IMAP.saveSent(configuration: configuration, messageURL: messageURL, password: password)
    } catch {
      let recoveryURL: URL
      do {
        let recoveryDirectory = try FileManager.default
          .url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
          )
          .appendingPathComponent("Pigeon/PendingSent", isDirectory: true)
        try FileManager.default.createDirectory(
          at: recoveryDirectory,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700]
        )
        recoveryURL = recoveryDirectory.appendingPathComponent("\(UUID().uuidString).eml")
        try FileManager.default.copyItem(at: messageURL, to: recoveryURL)
      } catch {
        // Keep the original message if durable recovery storage is unavailable.
        preserveMessage = true
        throw SentCopyError(
          "SMTP accepted the email, but the Sent copy and recovery save failed. Do not resend. Original message retained at \(messageURL.path)."
        )
      }
      throw SentCopyError(
        "SMTP accepted the email, but saving the Sent copy failed: \(error) Do not resend. Message saved at \(recoveryURL.path). Use save-sent --message-file with that file after checking Sent for an existing copy."
      )
    }
  }

  static func smtpArguments(
    configuration: Configuration,
    message: Message,
    messageURL: URL
  ) -> [String] {
    [
      "--proto", "=smtp", "--url", "smtp://\(configuration.host):\(configuration.port)",
      "--mail-from", configuration.from, "--upload-file", messageURL.path,
    ] + message.envelopeRecipients.flatMap { ["--mail-rcpt", $0] }
  }
}

struct SentCopyError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
