# 🕊️ Pigeon

A small Swift command-line mail client for macOS. Send plain-text email through your SMTP provider using a password from `.env` or the environment. No Swift package dependencies; macOS’s bundled curl handles SMTP with verified STARTTLS.

Requires macOS 13 or later and Swift 6 or later.

## Setup

```sh
swift build -c release
mkdir -p .local
cp config.example.json .local/config.json
cp .env.example .env
chmod 600 .env
```

Edit `.local/config.json` with your SMTP and sender details, and set `PIGEON_SMTP_PASSWORD` in `.env`. Both locations are ignored by Git; the password file is plaintext. All JSON fields are required; `senderName` can be empty.

For iCloud, use your primary iCloud email as `username`, an [app-specific password](https://support.apple.com/en-us/102654), and an address configured for your account as `from`. The example uses [Apple’s SMTP settings](https://support.apple.com/en-us/102525).

## Send

Write your message in `.local/message.txt`, then preview it:

```sh
.build/release/pigeon send --config .local/config.json --to recipient@example.com --subject "Hello" --body-file .local/message.txt --dry-run
```

Remove `--dry-run` to send. Repeat `--to` for multiple recipients. Run `.build/release/pigeon --help` for all options.

An environment variable named `PIGEON_SMTP_PASSWORD` takes precedence over `.env` in the current directory. Use `--env-file FILE` for another file. Env values are literal, with optional surrounding quotes; shell expansion and inline comments are unsupported.

Pigeon sends once, without retries or a Sent-folder copy. Success means the SMTP server accepted the message. If a connection fails, check the destination before retrying. For a new sender alias, send to yourself first and inspect the received headers.

## Releases

With Node.js 20+, pnpm, and an authenticated GitHub CLI:

```sh
pnpm install
pnpm run release
```

This builds Pigeon, prompts for a version, commits all working tree changes, tags, pushes, and publishes a GitHub release with generated notes. Review changes first. Releases contain source code; build locally as above.
