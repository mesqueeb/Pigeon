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
    let defaultFiles = UserConfigurationFiles()
    if arguments.isEmpty || arguments == ["--help"] || arguments == ["help"] {
      print(help)
      if arguments.isEmpty, !FileManager.default.fileExists(atPath: defaultFiles.config.path) {
        print("\nRun pigeon init to set up your mail account.")
      }
      return
    }
    let command = arguments[0]
    if command == "init" {
      guard arguments.count == 1 else { throw PigeonError("pigeon init does not accept options.") }
      try defaultFiles.initialize()
      return
    }
    guard ["send", "credential", "save-sent"].contains(command) else {
      throw PigeonError("Unknown command. Run pigeon --help.")
    }
    var values: [String: String] = [:]
    let repeatableOptions = ["--to", "--cc", "--bcc", "--reference"]
    let singleValueOptions = [
      "--config", "--subject", "--body-file", "--env-file", "--message-file", "--in-reply-to",
    ]
    var repeatedValues: [String: [String]] = [:]
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
      guard repeatableOptions.contains(option) || singleValueOptions.contains(option),
        index + 1 < arguments.count
      else { throw PigeonError("Unknown option or missing value: \(option)") }
      let value = arguments[index + 1]
      if repeatableOptions.contains(option) {
        repeatedValues[option, default: []].append(value)
      } else {
        guard values[option] == nil else { throw PigeonError("Duplicate option: \(option)") }
        values[option] = value
      }
      index += 2
    }
    let explicitConfig = values["--config"]
    let configURL = explicitConfig.map { URL(fileURLWithPath: $0) } ?? defaultFiles.config
    if explicitConfig == nil, !FileManager.default.fileExists(atPath: configURL.path) {
      throw PigeonError("No default config at \(configURL.path). Run pigeon init to set it up.")
    }
    let configuration = try JSONDecoder()
      .decode(Configuration.self, from: Data(contentsOf: configURL))
    try configuration.validate()
    let explicitEnvFile = values["--env-file"]
    let envFile = explicitEnvFile ?? (explicitConfig == nil ? defaultFiles.env.path : ".env")

    if command == "credential" {
      guard values.keys.allSatisfy({ ["--config", "--env-file"].contains($0) }),
        repeatedValues.isEmpty, flags.isEmpty
      else { throw PigeonError("credential accepts --config and --env-file.") }
      _ = try Credential.read(envFile: envFile, explicitlySelected: explicitEnvFile != nil)
      print("The selected credential is accessible. Its value was not displayed.")
      return
    }
    if command == "save-sent" {
      guard let path = values["--message-file"],
        values.keys.allSatisfy({ ["--config", "--env-file", "--message-file"].contains($0) }),
        repeatedValues.isEmpty, flags.isEmpty
      else {
        throw PigeonError(
          "save-sent requires --message-file, with optional --config and --env-file."
        )
      }
      let password = try Credential.read(
        envFile: envFile,
        explicitlySelected: explicitEnvFile != nil
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
    let references = repeatedValues["--reference"] ?? []
    let reply: ReplyHeaders?
    if let parent = values["--in-reply-to"] {
      reply = try ReplyHeaders(parent: parent, references: references)
    } else {
      guard references.isEmpty else { throw PigeonError("--reference requires --in-reply-to.") }
      reply = nil
    }
    let body = try String(contentsOfFile: bodyPath, encoding: .utf8)
    let message = Message(
      to: repeatedValues["--to"] ?? [],
      cc: repeatedValues["--cc"] ?? [],
      bcc: repeatedValues["--bcc"] ?? [],
      subject: subject,
      body: body,
      reply: reply
    )
    let rendered = try message.render(configuration: configuration)
    if flags.contains("--dry-run") {
      print("From: \(configuration.senderName) <\(configuration.from)>")
      print("To: \(message.to.joined(separator: ", "))")
      if !message.cc.isEmpty { print("Cc: \(message.cc.joined(separator: ", "))") }
      if !message.bcc.isEmpty { print("Bcc (SMTP only): \(message.bcc.joined(separator: ", "))") }
      if let reply { print(reply.lines.joined(separator: "\n")) }
      print("Subject: \(subject)\n")
      print(body)
      print("\nDry run: no credential was read and no network connection was made.")
      return
    }
    let password = try Credential.read(envFile: envFile, explicitlySelected: explicitEnvFile != nil)
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

    pigeon init
    pigeon send --to ADDRESS --subject TEXT --body-file FILE [--config FILE]
                [--cc ADDRESS] [--bcc ADDRESS] [--in-reply-to MESSAGE-ID]
                [--reference MESSAGE-ID] [--dry-run] [--env-file FILE]
    pigeon credential [--config FILE] [--env-file FILE]
    pigeon save-sent --message-file FILE [--config FILE] [--env-file FILE]

    pigeon init creates example config.json and .env files in ~/.config/pigeon.
    Commands use that config unless you pass --config FILE.
    Set from in the config to a sender address your SMTP account can use.
    Repeat --to, --cc, or --bcc for multiple recipients. At least one --to is required.
    Reply with --in-reply-to '<id@example.com>', using the Message-ID of the message
    you're replying to.
    Keep that message's subject with a Re: prefix. Repeat --reference for its References IDs
    in order. If there are no References and a single In-Reply-To ID, pass it via --reference.
    Messages are UTF-8 plain text.
    --dry-run previews the sender and message without reading credentials or contacting the server.
    Credentials come from PIGEON_SMTP_PASSWORD in the environment, then ~/.config/pigeon/.env.
    With an explicit --config, the fallback is .env in the current directory.
    --env-file overrides the fallback file. Values are literal; shell expansion is not supported.
    credential checks that a nonempty password is available without displaying it.

    SMTP uses required STARTTLS with certificate verification through /usr/bin/curl.
    After SMTP acceptance, the same message is saved to the configured IMAP Sent mailbox.
    Exit 2 means SMTP accepted the email but saving the copy failed. Do not resend.
    save-sent saves an existing .eml without sending. Check Sent before retrying a save.
    Pigeon does not retry automatically. IMAP uses implicit TLS with certificate verification.
    """
}
