load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "OwnershipTransferController",
    module_name = "OwnershipTransferController",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
        # Xcode 27: keep new diagnostic groups as warnings (SE-0443 last-wins)
        "-Wwarning", "ImplicitStrongCapture",
        "-Wwarning", "DeprecatedDeclaration",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/Display",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/PresentationDataUtils",
        "//submodules/AccountContext",
        "//submodules/TextFormat",
        "//submodules/PasswordSetupUI",
        "//submodules/Markdown",
        "//submodules/ActivityIndicator",
        "//submodules/TelegramUI/Components/PeerManagement/OldChannelsController",
        "//submodules/TelegramUI/Components/AlertComponent",
        "//submodules/TelegramUI/Components/AlertComponent/AlertInputFieldComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
