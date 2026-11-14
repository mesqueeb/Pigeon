# Pigeon

A small Swift command-line mail client for macOS. Pigeon reads an SMTP password from the environment or a local `.env` file and submits a plain-text email through your provider's SMTP server. It runs once and exits.

Swift owns configuration, message formatting, and credential loading. macOS's bundled `/usr/bin/curl` handles SMTP authentication and certificate-verified STARTTLS. There are no Swift package dependencies, inbox interface, or background service.

## Build

Requires macOS 13 or later and Swift 6 or later.

```sh
swift build -c release
.build/release/pigeon --help
```

## Configure

Copy `config.example.json` into `.local/config.json` and replace its values. `.local/` is ignored by Git. The JSON configuration contains connection and sender settings, never the password.

The SMTP login `username` is separate from the visible `from` address. For iCloud, authenticate using the primary iCloud Mail address and an app-specific password. Use a custom From address only when configured for that account. Apple's server is `smtp.mail.me.com` on port `587`; Pigeon requires STARTTLS and certificate verification.

`senderName` is required; use an empty string to omit the display name.

Copy `.env.example` to `.env`, restrict permissions, then replace the placeholder with your app-specific password in a local editor:

```sh
cp .env.example .env
chmod 600 .env
```

Pigeon checks `PIGEON_SMTP_PASSWORD` in the process environment first, then `.env` in the current working directory. Use `--env-file FILE` to select another file. An empty environment value is an error and does not fall back to the file. Env files support blank lines, comments starting with `#`, an optional `export` prefix, and a single `PIGEON_SMTP_PASSWORD=value` assignment. Matching single or double quotes are removed; values otherwise remain literal, with no shell expansion, escape processing, or inline comments.

`.env` and `.env.*` are ignored by Git, except `.env.example`. The password is stored in plaintext: anyone who can read the file can read it. It does not sync through iCloud Keychain. Keep real passwords out of example files and command arguments.

## Preview and send

Create a UTF-8 text file containing the email body, then preview without loading credentials or accessing the network:

```sh
.build/release/pigeon send --config .local/config.json --to recipient@example.com --subject "Hello" --body-file .local/message.txt --dry-run
```

Run the same command without `--dry-run` to submit the message. Repeat `--to` for additional recipients. Pigeon generates the From, To, Subject, Date, Message-ID, and MIME headers.

Check that a nonempty credential is available without contacting the SMTP server:

```sh
.build/release/pigeon credential --config .local/config.json
```

This command never displays the password and does not verify it with the provider. Dry runs do not load the env file. On submission, the password stays in process memory and passes to curl through a private pipe; Pigeon removes `PIGEON_SMTP_PASSWORD` from curl's inherited environment.

## Submission behaviour

The `send` command makes one submission and does not retry. Success means Apple's or another provider's server accepted the SMTP transaction, not that the recipient received it. If a connection fails late, delivery may be uncertain; inspect the destination before retrying.

Pigeon does not append a copy to an IMAP Sent folder. It creates a temporary message file with restrictive permissions and removes it when the command exits normally. The SMTP password is never written to that file. Abrupt process termination can leave a message file behind in the system temporary directory.

For a new account or sender alias, first send to an inbox you control and inspect the received From, Sender, Reply-To, Return-Path, and authentication results. A custom From address does not promise the primary account is absent from all transport headers.

## Releases

Release tooling follows the pnpm and `bumpp` workflow used by the other Swift packages. Requires Node.js 20 or later, pnpm, and an authenticated GitHub CLI (`gh`).

```sh
pnpm install
pnpm run build
pnpm run release
```

The release command builds the executable, prompts for a version, commits the version change and all working tree changes, creates a Git tag, pushes, and creates a GitHub release with generated notes. Review the working tree before running it. The version lives in `package.json`; the npm package is private. Releases contain source code; build the executable locally using the instructions above.

`.spi.yml` configures the `Pigeon` documentation target for Swift Package Index.

## References

- [Apple's iCloud SMTP settings](https://support.apple.com/en-us/102525)
- [Apple app-specific passwords](https://support.apple.com/en-us/102654)
- [curl SMTP documentation](https://everything.curl.dev/usingcurl/smtp.html)
