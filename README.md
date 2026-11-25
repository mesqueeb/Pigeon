# Pigeon 🕊️

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmesqueeb%2FPigeon%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mesqueeb/Pigeon)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmesqueeb%2FPigeon%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mesqueeb/Pigeon)

A tiny Swift command-line app for sending email from your Mac. Plain-text messages, your own SMTP provider, and 0 Swift dependencies!

Runs on Apple silicon Macs with macOS 13 or later. Uses macOS’s built-in curl for SMTP with verified STARTTLS.

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

Run this once to create your user configuration files.

```sh
pigeon init
```

Edit `~/.config/pigeon/config.json` with your SMTP settings, sender address, and IMAP Sent mailbox. Set your password in `~/.config/pigeon/.env`.

```dotenv
PIGEON_SMTP_PASSWORD=your-app-specific-password
```

Pigeon creates both files with permissions that restrict access to your user. Keep `.env` private because it stores the password as plain text. Running `pigeon init` again preserves existing files.

Using iCloud? Log in with your primary iCloud email and an [app-specific password](https://support.apple.com/en-us/102654). Your `from` address can be a custom address configured for that account.

Run `pigeon credential` to check that Pigeon can read the password before you send.

## Agent skill

After installing Pigeon with Homebrew and configuring your account, install the [Pigeon skill](.agents/skills/pigeon/SKILL.md) for your coding agent.

```sh
npx skills add mesqueeb/Pigeon --skill pigeon --global
```

The skill helps agents choose Pigeon when you ask to send or reply from a configured alias that their mail connector cannot select. Sending requires a macOS session with access to your configured Pigeon CLI.

## Usage

Write your email in `message.txt`, then preview it.

```sh
pigeon send --to friend@example.com --subject "Hello!" --body-file message.txt --dry-run
```

Remove `--dry-run` to send. Repeat `--to`, `--cc`, or `--bcc` to add more recipients of each type. At least one `--to` address is required. BCC addresses are used for SMTP delivery and omitted from the message headers.

To reply in an existing thread, pass the Message-ID of the message you’re replying to with `--in-reply-to '<id@example.com>'` and use its subject with a `Re:` prefix. If that message has a `References` header, pass each ID in order with `--reference '<id@example.com>'`. If it has no `References` and a single `In-Reply-To` ID, pass that ID with `--reference`.

Use `--attach FILE` with a new message or reply. Repeat it for each local file and quote paths with spaces. The dry-run preview lists the filenames.

```sh
pigeon send --to friend@example.com --subject "Documents" --body-file message.txt --attach "資料 1.pdf" --attach notes.txt --dry-run
```

Pigeon reads `PIGEON_SMTP_PASSWORD` from the environment first, then from `~/.config/pigeon/.env`. Pass `--config FILE` to use a different account config. With an explicit config, the fallback credential file is `.env` in the current directory. Use `--env-file FILE` to choose the fallback file for either setup.

After sending, Pigeon saves the same message to your IMAP Sent folder. Configure `imap.host`, `imap.port`, and `imap.sentMailbox` in your JSON. The iCloud example uses `imap.mail.me.com:993` and `Sent Messages`, shared by the account’s aliases. Other providers may already save SMTP submissions automatically; appending a copy there can create duplicates.

Pigeon checks access to the folder before sending. If SMTP accepts the email but saving fails, it exits with code `2` and keeps a private `.eml` recovery file. **Do not resend.** After checking Sent for an existing copy, save only the missing copy:

```sh
pigeon save-sent --message-file "/path/from/the/error.eml"
```

Messages and copies are never retried automatically. If submission fails, check the destination before retrying.

## Documentation

Run `pigeon --help` for the command reference. See the [source](Sources/Pigeon) for implementation details.
