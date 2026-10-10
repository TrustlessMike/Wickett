// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Wickett",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .iOSApplication(
            name: "Wickett",
            targets: ["Wickett"],
            bundleIdentifier: "org.example.Wickett",
            displayVersion: "1.0",
            bundleVersion: "1",
            supportedDeviceFamilies: [.pad, .phone],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeLeft,
                .landscapeRight,
                .portraitUpsideDown(.pad)
            ],
            infoPlist: .file("Resources/Info.plist")
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.20.0"),
        .package(url: "https://github.com/metaplex-foundation/Solana.Swift.git", from: "2.0.1")
    ],
    targets: [
        .target(
            name: "Wickett",
            dependencies: [
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFunctions", package: "firebase-ios-sdk"),
                .product(name: "Solana", package: "Solana.Swift")
            ],
            path: "Sources/Wickett",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
