import Darwin
import Foundation

@main enum Pigeon {
  static func main() {
    do { try run(arguments: Array(CommandLine.arguments.dropFirst())) } catch let error
      as SentCopyError
    {
      FileHandle.standardError.write(Data("pigeon: \(error)\n".utf8))
      exit(2)
    } catch {
      FileHandle.standardError.write(Data("pigeon: \(error)\n".utf8))
      exit(1)
    }
  }

  private static func run(arguments: [String]) throws {
    if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
      print(help)
      return
    }
    let command = arguments[0]
    guard ["send", "credential", "save-sent"].contains(command) else {
      throw PigeonError("Unknown command. Run pigeon --help.")
    }
    var values: [String: String] = [:]
    var recipients: [String] = []
    var flags: Set<String> = []
    var index = 1
    while index < arguments.count {
      let option = arguments[index]
      if ["--dry-run"].contains(option) {
        guard flags.insert(option).inserted else {
          throw PigeonError("Duplicate option: \(option)")
        }
        index += 1
        continue
      }
      guard
        ["--config", "--to", "--subject", "--body-file", "--env-file", "--message-file"]
          .contains(option), index + 1 < arguments.count
      else { throw PigeonError("Unknown option or missing value: \(option)") }
      let value = arguments[index + 1]
      if option == "--to" {
        recipients.append(value)
      } else {
        guard values[option] == nil else { throw PigeonError("Duplicate option: \(option)") }
        values[option] = value
      }
      index += 2
    }
    guard let configPath = values["--config"] else { throw PigeonError("--config is required.") }
    let configuration = try JSONDecoder()
      .decode(Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
    try configuration.validate()

    if command == "credential" {
      guard values.keys.allSatisfy({ ["--config", "--env-file"].contains($0) }), recipients.isEmpty,
        flags.isEmpty
      else { throw PigeonError("credential accepts --config and --env-file.") }
      _ = try Credential.read(
        envFile: values["--env-file"] ?? ".env",
        explicitlySelected: values["--env-file"] != nil
      )
      print("The selected credential is accessible. Its value was not displayed.")
      return
    }
    if command == "save-sent" {
      guard let path = values["--message-file"],
        values.keys.allSatisfy({ ["--config", "--env-file", "--message-file"].contains($0) }),
        recipients.isEmpty, flags.isEmpty
      else {
        throw PigeonError(
          "save-sent requires --config and --message-file, with optional --env-file."
        )
      }
      let password = try Credential.read(
        envFile: values["--env-file"] ?? ".env",
        explicitlySelected: values["--env-file"] != nil
      )
      try IMAP.saveSent(
        configuration: configuration,
        messageURL: URL(fileURLWithPath: path),
        password: password
      )
      print("Saved a copy to \(configuration.imap.sentMailbox). No email was sent.")
      return
    }
    guard values["--message-file"] == nil else {
      throw PigeonError("--message-file is only for save-sent.")
    }
    guard let subject = values["--subject"], let bodyPath = values["--body-file"] else {
      throw PigeonError("send requires --to, --subject and --body-file.")
    }
    let body = try String(contentsOfFile: bodyPath, encoding: .utf8)
    let message = Message(recipients: recipients, subject: subject, body: body)
    let rendered = try message.render(configuration: configuration)
    if flags.contains("--dry-run") {
      print("From: \(configuration.senderName) <\(configuration.from)>")
      print("To: \(recipients.joined(separator: ", "))")
      print("Subject: \(subject)\n")
      print(body)
      print("\nDry run: no credential was read and no network connection was made.")
      return
    }
    let password = try Credential.read(
      envFile: values["--env-file"] ?? ".env",
      explicitlySelected: values["--env-file"] != nil
    )
    try MailClient.submit(
      configuration: configuration,
      message: message,
      rendered: rendered,
      password: password
    )
    print(
      "Submitted as \(configuration.from) and saved to \(configuration.imap.sentMailbox). Recipient delivery still needs verification."
    )
  }

  private static let help = """
    Pigeon — a small macOS SMTP client

    pigeon send --config FILE --to ADDRESS --subject TEXT --body-file FILE [--dry-run] [--env-file FILE]
    pigeon credential --config FILE [--env-file FILE]
    pigeon save-sent --config FILE --message-file FILE [--env-file FILE]

    Repeat --to for multiple recipients. Messages are UTF-8 plain text.
    --dry-run previews the message without reading credentials or contacting the server.
    Credentials come from PIGEON_SMTP_PASSWORD in the environment, then .env in the current directory.
    --env-file selects a different file. Values are literal; shell expansion is not supported.
    credential checks that a nonempty password is available without displaying it.

    SMTP uses required STARTTLS with certificate verification through /usr/bin/curl.
    After SMTP acceptance, the same message is saved to the configured IMAP Sent mailbox.
    Exit 2 means SMTP accepted the email but saving the copy failed. Do not resend.
    save-sent saves an existing .eml without sending. Check Sent before retrying a save.
    Pigeon does not retry automatically. IMAP uses implicit TLS with certificate verification.
    """
}
