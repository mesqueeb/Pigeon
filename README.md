# Pigeon 🕊️

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmesqueeb%2FPigeon%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mesqueeb/Pigeon)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmesqueeb%2FPigeon%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mesqueeb/Pigeon)

A tiny Swift command-line app for sending email from your Mac. Plain-text messages, your own SMTP provider, and 0 Swift dependencies!

Requires macOS 13+ and Swift 6+. Uses macOS’s built-in curl for SMTP with verified STARTTLS.

## Setup

From the repository directory:

```sh
swift build -c release
mkdir -p .local
cp config.example.json .local/config.json
cp .env.example .env
chmod 600 .env
```

Add your SMTP and sender details to `.local/config.json`, and your password to `.env`:

```dotenv
PIGEON_SMTP_PASSWORD=your-app-specific-password
```

Both are ignored by Git. Keep `.env` private: it stores the password as plain text.

Using iCloud? Log in with your primary iCloud email and an [app-specific password](https://support.apple.com/en-us/102654). Your `from` address can be a custom address configured for that account.

## Usage

Write your email in `.local/message.txt`, then preview it:

```sh
.build/release/pigeon send --config .local/config.json --to friend@example.com --subject "Hello!" --body-file .local/message.txt --dry-run
```

Remove `--dry-run` to send. Repeat `--to` for more recipients.

Pigeon reads `PIGEON_SMTP_PASSWORD` from the environment first, then `.env` in the current directory. Use `--env-file FILE` to choose another file.

After sending, Pigeon saves the same message to your IMAP Sent folder. Configure `imap.host`, `imap.port`, and `imap.sentMailbox` in your JSON. The iCloud example uses `imap.mail.me.com:993` and `Sent Messages`, shared by the account’s aliases. Other providers may already save SMTP submissions automatically; appending a copy there can create duplicates.

Pigeon checks access to the folder before sending. If SMTP accepts the email but saving fails, it exits with code `2` and keeps a private `.eml` recovery file. **Do not resend.** After checking Sent for an existing copy, save only the missing copy:

```sh
.build/release/pigeon save-sent --config .local/config.json --message-file "/path/from/the/error.eml"
```

Messages and copies are never retried automatically. If submission fails, check the destination before retrying.

## Documentation

Run `.build/release/pigeon --help` for the command reference. See the [source](Sources/Pigeon) for implementation details.
