// swift-tools-version: 6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "StudyQuest",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StudyQuest", targets: ["StudyQuest"]),
        .executable(name: "studyquest-mcp", targets: ["studyquest-mcp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.8.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.10.1"),
    ],
    targets: [
        .target(
            name: "StudyCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: v5),
        .target(
            name: "StudyMCP",
            dependencies: ["StudyCore", .product(name: "MCP", package: "swift-sdk")],
            swiftSettings: v5),
        .executableTarget(
            name: "StudyQuest",
            dependencies: ["StudyCore"],
            swiftSettings: v5),
        .executableTarget(
            name: "studyquest-mcp",
            dependencies: ["StudyMCP"],
            swiftSettings: v5),
        .testTarget(
            name: "StudyCoreTests",
            dependencies: ["StudyCore"],
            swiftSettings: v5),
        .testTarget(
            name: "StudyMCPTests",
            dependencies: ["StudyMCP"],
            swiftSettings: v5),
    ]
)
