# Pigeon 🕊️

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmesqueeb%2FPigeon%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mesqueeb/Pigeon)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmesqueeb%2FPigeon%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mesqueeb/Pigeon)

A tiny Swift command-line app for sending email from your Mac. Plain-text messages, your own SMTP provider, and 0 Swift dependencies!

Runs on macOS 13 or later on Apple silicon and Intel Macs. Uses macOS’s built-in curl for SMTP with verified STARTTLS.

## Install

### Homebrew

```sh
brew install mesqueeb/tap/pigeon
```

Homebrew installs a prebuilt executable and the example configuration files.

### Build from source

Use Swift 6 or later and run this from the repository directory.

```sh
swift build -c release
```

Use `.build/release/pigeon` in place of `pigeon` in the examples below.

## Setup

Choose a working directory for your SMTP configuration and credentials. If you built from source, run this from the repository directory and set `pigeon_examples=.` in the first line.

```sh
pigeon_examples="$(brew --prefix mesqueeb/tap/pigeon)/share/pigeon"
mkdir -p .local
cp -i "$pigeon_examples/config.example.json" .local/config.json
if [ ! -e .env ]; then
  install -m 600 "$pigeon_examples/.env.example" .env
fi
```

Add your SMTP and sender details to `.local/config.json` and your password to `.env`.

```dotenv
PIGEON_SMTP_PASSWORD=your-app-specific-password
```

Pigeon’s source repository ignores both files. Keep `.env` private because it stores the password as plain text.

Using iCloud? Log in with your primary iCloud email and an [app-specific password](https://support.apple.com/en-us/102654). Your `from` address can be a custom address configured for that account.

## Usage

Write your email in `.local/message.txt`, then preview it:

```sh
pigeon send --config .local/config.json --to friend@example.com --subject "Hello!" --body-file .local/message.txt --dry-run
```

Remove `--dry-run` to send. Repeat `--to`, `--cc`, or `--bcc` to add more recipients of each type. At least one `--to` address is required. BCC addresses are used for SMTP delivery and omitted from the message headers.

To reply in an existing thread, pass the Message-ID of the message you’re replying to with `--in-reply-to '<id@example.com>'` and use its subject with a `Re:` prefix. If that message has a `References` header, pass each ID in order with `--reference '<id@example.com>'`. If it has no `References` and a single `In-Reply-To` ID, pass that ID with `--reference`.

Pigeon reads `PIGEON_SMTP_PASSWORD` from the environment first, then `.env` in the current directory. Use `--env-file FILE` to choose another file.

After sending, Pigeon saves the same message to your IMAP Sent folder. Configure `imap.host`, `imap.port`, and `imap.sentMailbox` in your JSON. The iCloud example uses `imap.mail.me.com:993` and `Sent Messages`, shared by the account’s aliases. Other providers may already save SMTP submissions automatically; appending a copy there can create duplicates.

Pigeon checks access to the folder before sending. If SMTP accepts the email but saving fails, it exits with code `2` and keeps a private `.eml` recovery file. **Do not resend.** After checking Sent for an existing copy, save only the missing copy:

```sh
pigeon save-sent --config .local/config.json --message-file "/path/from/the/error.eml"
```

Messages and copies are never retried automatically. If submission fails, check the destination before retrying.

## Documentation

Run `pigeon --help` for the command reference. See the [source](Sources/Pigeon) for implementation details.
