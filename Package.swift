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
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PETVocabularyTrainerTests",
            dependencies: ["PETVocabularyTrainer"]
        )
    ]
)
