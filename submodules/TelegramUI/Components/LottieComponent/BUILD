load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "LottieComponent",
    module_name = "LottieComponent",
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
        "//submodules/Display",
        "//submodules/ComponentFlow",
        "//submodules/Components/HierarchyTrackingLayer",
        "//submodules/rlottie:RLottieBinding",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/AppBundle",
        "//submodules/GZip",
        "//submodules/TelegramUI/Components/Utils/GenerateStickerPlaceholderImage",
    ],
    visibility = [
        "//visibility:public",
    ],
)
