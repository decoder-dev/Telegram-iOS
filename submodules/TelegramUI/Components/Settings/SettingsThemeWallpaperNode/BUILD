load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "SettingsThemeWallpaperNode",
    module_name = "SettingsThemeWallpaperNode",
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
        "//submodules/AsyncDisplayKit",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/GradientBackground",
        "//submodules/WallpaperResources",
        "//submodules/StickerResources",
        "//submodules/AccountContext",
        "//submodules/RadialStatusNode",
        "//submodules/AnimatedStickerNode",
        "//submodules/TelegramAnimatedStickerNode",
    ],
    visibility = [
        "//visibility:public",
    ],
)
