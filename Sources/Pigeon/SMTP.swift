import Foundation

enum SMTP {
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
    defer { try? FileManager.default.removeItem(at: directory) }
    let messageURL = directory.appendingPathComponent("message.eml")
    guard
      FileManager.default.createFile(
        atPath: messageURL.path,
        contents: Data(rendered.utf8),
        attributes: [.posixPermissions: 0o600]
      )
    else { throw PigeonError("Could not create the private temporary message file.") }

    let input = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "PIGEON_SMTP_PASSWORD")
    process.environment = environment
    process.arguments =
      [
        "--disable", "--silent", "--ssl-reqd", "--tlsv1.2", "--proto", "=smtp", "--noproxy", "*",
        "--connect-timeout", "20", "--max-time", "120", "--url",
        "smtp://\(configuration.host):\(configuration.port)", "--mail-from", configuration.from,
        "--upload-file", messageURL.path, "--config", "-",
      ] + message.recipients.flatMap { ["--mail-rcpt", $0] }
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()

    // Pass credentials through a private pipe so process arguments and files never contain them.
    let credential = configuration.username + ":" + password
    let escaped = credential.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\r", with: "\\r")
      .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\t", with: "\\t")
      .replacingOccurrences(of: "\u{000B}", with: "\\v")
    do {
      try input.fileHandleForWriting.write(contentsOf: Data("user = \"\(escaped)\"\n".utf8))
      try input.fileHandleForWriting.close()
    } catch {
      process.terminate()
      process.waitUntilExit()
      throw PigeonError(
        "Could not pass credentials to the SMTP transport. No automatic retry was attempted."
      )
    }
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw PigeonError(
        "SMTP transport exited with status \(process.terminationStatus). Check authentication, TLS, server and recipient settings. Delivery is not confirmed; inspect the destination before retrying."
      )
    }
  }
}
