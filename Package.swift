// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Pigeon",
  platforms: [.macOS(.v13)],
  products: [.executable(name: "pigeon", targets: ["Pigeon"])],
  targets: [.executableTarget(name: "Pigeon")]
)
