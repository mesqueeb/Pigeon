import Foundation

struct Configuration: Decodable {
  let host: String
  let port: Int
  let username: String
  let from: String
  let senderName: String

  func validate() throws {
    let hostnameCharacters = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"
    )
    let controlCharacters = CharacterSet.controlCharacters
    guard !host.isEmpty, host.unicodeScalars.allSatisfy(hostnameCharacters.contains),
      (1 ... 65535).contains(port)
    else { throw PigeonError("Use a DNS hostname and a port between 1 and 65535.") }
    try validateAddress(from)
    guard !username.isEmpty, !username.contains(":"),
      !username.unicodeScalars.contains(where: { controlCharacters.contains($0) }),
      !senderName.unicodeScalars.contains(where: { controlCharacters.contains($0) })
    else {
      throw PigeonError(
        "The username and sender name must not contain control characters; the username must not contain a colon."
      )
    }
  }
}

struct PigeonError: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) { self.description = description }
}

func validateAddress(_ address: String) throws {
  let parts = address.split(separator: "@", omittingEmptySubsequences: false)
  let allowed = CharacterSet(
    charactersIn:
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!#$%&'*+-/=?^_`{|}~@"
  )
  guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }),
    address.unicodeScalars.allSatisfy(allowed.contains), !address.hasPrefix("-")
  else { throw PigeonError("Use a bare ASCII email address, for example person@example.com.") }
}
