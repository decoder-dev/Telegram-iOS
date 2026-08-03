load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ProfileLevelRatingBarComponent",
    module_name = "ProfileLevelRatingBarComponent",
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
        "//submodules/AccountContext",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/MultiAnimationRenderer",
        "//submodules/TelegramUI/Components/AnimationCache",
        "//submodules/Components/ComponentDisplayAdapters",
        "//submodules/Components/HierarchyTrackingLayer",
        "//submodules/Components/MultilineTextComponent",
        "//submodules/Components/BundleIconComponent",
        "//submodules/TelegramUI/Components/AnimatedTextComponent",
        "//submodules/TelegramUI/Components/LottieComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
