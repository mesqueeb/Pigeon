import Foundation

enum Credential {
  static func read(envFile: String, explicitlySelected: Bool) throws -> String {
    if let password = ProcessInfo.processInfo.environment["PIGEON_SMTP_PASSWORD"] {
      return try validate(password)
    }
    guard FileManager.default.fileExists(atPath: envFile) else {
      throw PigeonError(
        explicitlySelected
          ? "The selected env file does not exist."
          : "Set PIGEON_SMTP_PASSWORD in the environment or in .env, or select a file with --env-file."
      )
    }
    let contents = try String(contentsOfFile: envFile, encoding: .utf8)
    var password: String?
    for line in contents.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
      let assignment = trimmed.hasPrefix("export ") ? String(trimmed.dropFirst(7)) : trimmed
      let parts = assignment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts[0].trimmingCharacters(in: .whitespaces) == "PIGEON_SMTP_PASSWORD" else {
        continue
      }
      guard parts.count == 2, password == nil else {
        throw PigeonError("Use a single PIGEON_SMTP_PASSWORD=value assignment in the env file.")
      }
      var value = parts[1].trimmingCharacters(in: .whitespaces)
      if let quote = value.first, quote == "\"" || quote == "'" {
        guard value.count >= 2, value.last == quote else {
          throw PigeonError("The password in the env file has unmatched quotes.")
        }
        value = String(value.dropFirst().dropLast())
      }
      password = value
    }
    guard let password else { throw PigeonError("The env file is missing PIGEON_SMTP_PASSWORD.") }
    return try validate(password)
  }

  private static func validate(_ password: String) throws -> String {
    let controls = CharacterSet.controlCharacters
    guard !password.isEmpty, !password.unicodeScalars.contains(where: { controls.contains($0) })
    else {
      throw PigeonError("PIGEON_SMTP_PASSWORD must be nonempty and contain no control characters.")
    }
    return password
  }
}
