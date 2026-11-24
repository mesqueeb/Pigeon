import Foundation

struct UserConfigurationFiles {
  private let directory: URL

  var config: URL { directory.appendingPathComponent("config.json") }
  var env: URL { directory.appendingPathComponent(".env") }

  init() {
    let homePath = ProcessInfo.processInfo.environment["HOME"]
    let home =
      homePath.flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil }
      ?? FileManager.default.homeDirectoryForCurrentUser
    directory = home.appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("pigeon", isDirectory: true)
  }

  func initialize() throws {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try installTemplate(Self.configurationExample + "\n", at: config)
    try installTemplate("PIGEON_SMTP_PASSWORD=\n", at: env)
    print("Edit \(config.path) with your SMTP and IMAP settings.")
    print("Set PIGEON_SMTP_PASSWORD in \(env.path).")
  }

  private func installTemplate(_ template: String, at destination: URL) throws {
    let files = FileManager.default
    let temporary = directory.appendingPathComponent(".pigeon-\(UUID().uuidString)")
    defer { try? files.removeItem(at: temporary) }
    guard
      files.createFile(
        atPath: temporary.path,
        contents: Data(template.utf8),
        attributes: [.posixPermissions: 0o600]
      )
    else { throw PigeonError("Could not create a private template in \(directory.path).") }

    // Link the finished file so concurrent setup cannot replace an existing config.
    do {
      try files.linkItem(at: temporary, to: destination)
      print("Created \(destination.path).")
    } catch let error as CocoaError where error.code == .fileWriteFileExists {
      print("Kept \(destination.path).")
    }
  }

  private static let configurationExample = """
    {
      "host": "smtp.mail.me.com",
      "port": 587,
      "username": "you@icloud.com",
      "from": "you@example.com",
      "senderName": "Your Name",
      "imap": {
        "host": "imap.mail.me.com",
        "port": 993,
        "sentMailbox": "Sent Messages"
      }
    }
    """
}
