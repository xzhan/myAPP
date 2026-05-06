// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "PETVocabularyTrainer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PETVocabularyTrainer", targets: ["PETVocabularyTrainer"])
    ],
    targets: [
        .executableTarget(
            name: "PETVocabularyTrainer",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/PETVocabularyTrainer/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "PETVocabularyTrainerTests",
            dependencies: ["PETVocabularyTrainer"]
        )
    ]
)
