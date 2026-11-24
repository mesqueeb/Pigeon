import { execFileSync } from "node:child_process"
import { createHash } from "node:crypto"
import {
  copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, utimesSync,
} from "node:fs"
import { basename, dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { parseArgs } from "node:util"
import { versionBump } from "bumpp"

const root = fileURLToPath(new URL("../", import.meta.url))
const repository = "mesqueeb/Pigeon"
const tapFormula = "repos/mesqueeb/homebrew-tap/contents/Formula/pigeon.rb"
const releases = join(root, ".build", "releases")
const formulaURL = /^(  url ")https:\/\/github\.com\/mesqueeb\/Pigeon\/releases\/download\/(v\d+\.\d+\.\d+)\/pigeon-\2-macos-universal\.zip"$/m
const formulaChecksum = /^(  sha256 ")[0-9a-f]{64}"$/m
const signingIdentity = process.env.PIGEON_SIGNING_IDENTITY
  ?? "Developer ID Application: Lucas Eugene M. Van Ammel (8ZRM3D7KC6)"
const notaryProfile = process.env.PIGEON_NOTARY_PROFILE ?? "AC_PASSWORD"

function run(command, args, { cwd = root, capture = false, input, env = process.env } = {}) {
  const stdio = capture ? ["ignore", "pipe", "pipe"] : [input ? "pipe" : "inherit", "inherit", "inherit"]
  return execFileSync(command, args, { cwd, encoding: "utf8", stdio, input, env })?.trim()
}

function releaseInfo(tag) {
  try {
    return JSON.parse(run("gh", [
      "release", "view", tag, "--repo", repository, "--json", "isDraft,assets,url",
    ], { capture: true }))
  } catch (error) {
    if (error.stderr?.trim() === "release not found") return undefined
    throw error
  }
}

function readTapFormula() {
  const { content, sha } = JSON.parse(run("gh", ["api", tapFormula + "?ref=main"], { capture: true }))
  const formula = Buffer.from(content, "base64").toString("utf8")
  const url = formula.match(formulaURL)
  if (!url || !formulaChecksum.test(formula)) throw new Error("Unexpected Pigeon formula in the tap.")
  return { formula, sha, tag: url[2] }
}

function updateTap({ tag, archiveName, checksum }) {
  const tap = readTapFormula()
  const url = "https://github.com/" + repository + "/releases/download/" + tag + "/" + archiveName
  const formula = tap.formula
    .replace(formulaURL, (_, prefix) => prefix + url + '"')
    .replace(formulaChecksum, (_, prefix) => prefix + checksum + '"')
  if (formula === tap.formula) return
  if (tag.localeCompare(tap.tag, "en", { numeric: true }) <= 0) {
    throw new Error("The tap already points to " + tap.tag + " with different release details.")
  }
  run("gh", ["api", tapFormula, "--method", "PUT", "--input", "-", "--silent"], {
    input: JSON.stringify({
      branch: "main",
      message: "Update Pigeon to " + tag,
      content: Buffer.from(formula).toString("base64"),
      sha: tap.sha,
    }),
  })
}

function buildArchive({ tag, archive, notarize }) {
  mkdirSync(dirname(archive), { recursive: true })
  const stage = mkdtempSync(join(dirname(archive), "stage-"))
  try {
    const payload = join(stage, "pigeon-" + tag)
    mkdirSync(payload)
    const build = [
      "build", "-c", "release", "--arch", "arm64", "--arch", "x86_64",
      "--scratch-path", join(releases, "swift-build"),
    ]
    run("swift", build)
    const binary = join(run("swift", [...build, "--show-bin-path"], { capture: true }), "pigeon")
    const executable = join(payload, "pigeon")
    copyFileSync(binary, executable)
    const architectures = run("xcrun", ["lipo", "-archs", executable], { capture: true }).split(/\s+/)
    if (!architectures.includes("arm64") || !architectures.includes("x86_64")) {
      throw new Error("The release executable must support arm64 and x86_64.")
    }
    const signing = notarize
      ? ["--timestamp", "--options", "runtime", "--sign", signingIdentity]
      : ["--timestamp=none", "--sign", "-"]
    run("codesign", ["--force", ...signing, executable])
    run("codesign", ["--verify", "--all-architectures", executable])
    run(executable, ["--help"], { capture: true })

    const examples = ["config.example.json", ".env.example", "LICENSE"]
    for (const file of examples) copyFileSync(join(root, file), join(payload, file))
    const files = ["pigeon", ...examples].map(file => join(basename(payload), file))
    const timestamp = Number(run("git", ["show", "-s", "--format=%ct", "HEAD"], { capture: true }))
    for (const file of files) utimesSync(join(stage, file), timestamp, timestamp)
    const zip = join(stage, basename(archive))
    run("/usr/bin/zip", ["-q", "-X", zip, ...files], {
      cwd: stage,
      env: { ...process.env, TZ: "UTC" },
    })
    if (notarize) {
      console.log("Submitting " + basename(zip) + " for Apple notarization.")
      const result = JSON.parse(run("xcrun", [
        "notarytool", "submit", zip, "--keychain-profile", notaryProfile, "--wait", "--output-format", "json",
      ], { capture: true }))
      if (result.status !== "Accepted") {
        throw new Error("Apple notarization returned " + result.status + " for submission " + result.id + ".")
      }
    }
    renameSync(zip, archive)
  } finally {
    rmSync(stage, { recursive: true, force: true })
  }
}

function version() {
  return JSON.parse(readFileSync(join(root, "package.json"), "utf8")).version
}

function publish(tag) {
  const ref = run("git", ["rev-parse", tag + "^{}", "HEAD"], { capture: true }).split("\n")
  if (ref[0] !== ref[1]) throw new Error(tag + " must point to the current release commit.")
  const archiveName = "pigeon-" + tag + "-macos-universal.zip"
  const archive = join(releases, tag, archiveName)
  let release = releaseInfo(tag)
  const findAsset = () => release?.assets.find(asset => asset.name === archiveName)

  if (!existsSync(archive)) {
    if (findAsset()) {
      mkdirSync(dirname(archive), { recursive: true })
      run("gh", ["release", "download", tag, "--repo", repository, "--pattern", archiveName, "--dir", dirname(archive)])
    } else {
      buildArchive({ tag, archive, notarize: true })
    }
  }
  const checksum = createHash("sha256").update(readFileSync(archive)).digest("hex")
  const digest = "sha256:" + checksum
  if (findAsset() && findAsset().digest !== digest) {
    throw new Error("The local archive differs from the GitHub release asset.")
  }

  run("git", ["push", "--atomic", "origin", "HEAD:refs/heads/main", "refs/tags/" + tag])
  if (!release) {
    const previous = run("git", ["describe", "--tags", "--abbrev=0", "--match", "v[0-9]*", tag + "^"], { capture: true })
    const changes = run("git", ["log", "--format=- %s  %h", previous + ".." + tag + "^"], { capture: true })
    const install = "Install on macOS 13 or later with brew install mesqueeb/tap/pigeon.\n\n"
      + "The archive includes a universal executable and configuration examples for Apple silicon and Intel."
    const notes = changes ? install + "\n\n" + changes : install
    run("gh", [
      "release", "create", tag, archive, "--repo", repository, "--verify-tag", "--draft", "--title", tag,
      "--generate-notes", "--notes-start-tag", previous, "--notes", notes,
    ])
  } else if (!findAsset()) {
    run("gh", ["release", "upload", tag, archive, "--repo", repository])
  }
  release = releaseInfo(tag)
  if (findAsset()?.digest !== digest) throw new Error("GitHub did not report the expected archive checksum.")
  if (release.isDraft) {
    run("gh", ["release", "edit", tag, "--repo", repository, "--verify-tag", "--draft=false"])
    release = releaseInfo(tag)
    if (!release || release.isDraft) throw new Error("GitHub did not publish " + tag + ".")
  }
  updateTap({ tag, archiveName, checksum })
  console.log("Released " + tag + " at " + release.url + "\nInstall with brew install mesqueeb/tap/pigeon")
}

async function main() {
  const { values: options } = parseArgs({
    options: {
      release: { type: "string" },
      yes: { type: "boolean", short: "y" },
      "dry-run": { type: "boolean" },
      resume: { type: "boolean" },
      help: { type: "boolean", short: "h" },
    },
  })
  if (options.help) {
    console.log("pnpm release [--release patch|minor|major|X.Y.Z] [--yes]\n"
      + "pnpm release --dry-run  Build and validate a local preview zip\n"
      + "pnpm release --resume   Finish publishing the current tagged version\n\n"
      + "The default bump is patch. Publishing uses SwiftSound's Developer ID and AC_PASSWORD keychain profile.\n"
      + "Set PIGEON_SIGNING_IDENTITY or PIGEON_NOTARY_PROFILE to use different keychain entries.")
    return
  }
  if ((options.resume && options["dry-run"])
    || ((options.resume || options["dry-run"]) && (options.release || options.yes))) {
    throw new Error("Use --dry-run or --resume on its own.")
  }

  const currentVersion = version()
  const currentTag = "v" + currentVersion
  if (options["dry-run"]) {
    mkdirSync(releases, { recursive: true })
    const preview = mkdtempSync(join(releases, "preview-"))
    const archive = join(preview, "pigeon-" + currentTag + "-macos-universal.zip")
    buildArchive({ tag: currentTag, archive, notarize: false })
    console.log("Preview archive at " + archive)
    return
  }

  if (run("git", ["branch", "--show-current"], { capture: true }) !== "main"
    || run("git", ["status", "--porcelain"], { capture: true })) {
    throw new Error("Release from a clean main checkout.")
  }
  const origin = run("git", ["remote", "get-url", "--push", "origin"], { capture: true })
  if (!/^(?:https:\/\/github\.com\/|git@github\.com:|ssh:\/\/git@github\.com\/)mesqueeb\/Pigeon(?:\.git)?\/?$/i.test(origin)) {
    throw new Error("The push URL for origin must point to " + repository + ".")
  }
  if (options.resume) {
    publish(currentTag)
    return
  }

  const release = options.release ?? "patch"
  if (!/^(?:patch|minor|major|\d+\.\d+\.\d+)$/.test(release)) {
    throw new Error("Use patch, minor, major, or an explicit stable version.")
  }
  if (/^\d/.test(release) && release.localeCompare(currentVersion, "en", { numeric: true }) <= 0) {
    throw new Error("The release version must be newer than " + currentVersion + ".")
  }
  const current = releaseInfo(currentTag)
  if (!current || current.isDraft || readTapFormula().tag !== currentTag) {
    throw new Error("Finish publishing " + currentTag + " with pnpm release --resume first.")
  }

  run("pnpm", ["test"])
  await versionBump({ cwd: root, release, commit: true, tag: true, push: false, confirm: !options.yes })
  const tag = "v" + version()
  if (tag === currentTag) throw new Error("The version did not change.")
  try {
    publish(tag)
  } catch (error) {
    console.error("Run pnpm release --resume to finish " + tag + " after resolving the error.")
    throw error
  }
}

try {
  await main()
} catch (error) {
  console.error(error.stderr?.trim() || error.message)
  process.exitCode = 1
}
