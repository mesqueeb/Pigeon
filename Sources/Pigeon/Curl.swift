import Foundation

enum Curl {
  static func run(arguments: [String], username: String, password: String) throws {
    let input = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "PIGEON_SMTP_PASSWORD")
    process.environment = environment
    process.arguments =
      [
        "--disable", "--silent", "--globoff", "--ssl-reqd", "--tlsv1.2", "--noproxy", "*",
        "--connect-timeout", "20", "--max-time", "120", "--config", "-",
      ] + arguments
    process.standardInput = input
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()

    // Pass credentials through a private pipe so process arguments and files never contain them.
    let credential = username + ":" + password
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
      throw PigeonError("Could not pass credentials to the mail transport.")
    }
    process.waitUntilExit()
    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      throw PigeonError("Mail transport exited with status \(process.terminationStatus).")
    }
  }
}
