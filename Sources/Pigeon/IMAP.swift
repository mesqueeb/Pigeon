import Foundation

struct IMAPConfiguration: Decodable {
  let host: String
  let port: Int
  let sentMailbox: String

  func validate() throws {
    let hostnameCharacters = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"
    )
    let controls = CharacterSet.controlCharacters
    guard !host.isEmpty, host.unicodeScalars.allSatisfy(hostnameCharacters.contains),
      (1 ... 65535).contains(port), !sentMailbox.isEmpty,
      !sentMailbox.unicodeScalars.contains(where: { controls.contains($0) })
    else {
      throw PigeonError(
        "IMAP requires a DNS hostname, a port between 1 and 65535, and a nonempty Sent mailbox without control characters."
      )
    }
  }

  var mailboxURL: String {
    let characters = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )
    let path = sentMailbox.addingPercentEncoding(withAllowedCharacters: characters)!
    return "imaps://\(host):\(port)/\(path)"
  }
}

enum IMAP {
  static func checkMailbox(configuration: Configuration, password: String) throws {
    let mailbox = configuration.imap.sentMailbox.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    do {
      try Curl.run(
        arguments: [
          "--proto", "=imaps", "--url",
          "imaps://\(configuration.imap.host):\(configuration.imap.port)/", "--request",
          "EXAMINE \"\(mailbox)\"",
        ],
        username: configuration.username,
        password: password
      )
    } catch {
      throw PigeonError("Cannot access the configured Sent mailbox. No email was sent. \(error)")
    }
  }

  static func saveSent(configuration: Configuration, messageURL: URL, password: String) throws {
    try Curl.run(
      arguments: [
        "--proto", "=imaps", "--url", configuration.imap.mailboxURL, "--upload-file",
        messageURL.path,
      ],
      username: configuration.username,
      password: password
    )
  }
}
