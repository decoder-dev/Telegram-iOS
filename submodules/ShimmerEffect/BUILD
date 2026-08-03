load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ShimmerEffect",
    module_name = "ShimmerEffect",
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
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/Components/HierarchyTrackingLayer:HierarchyTrackingLayer",
        "//submodules/TelegramUI/Components/Utils/GenerateStickerPlaceholderImage",
    ],
    visibility = [
        "//visibility:public",
    ],
)
