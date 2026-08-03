load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ThemeCarouselItem",
    module_name = "ThemeCarouselItem",
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
        "//submodules/MergeLists",
        "//submodules/TelegramUIPreferences",
        "//submodules/ItemListUI",
        "//submodules/PresentationDataUtils",
        "//submodules/WallpaperResources",
        "//submodules/AccountContext",
        "//submodules/AppBundle",
        "//submodules/ContextUI",
        "//submodules/AnimatedStickerNode",
        "//submodules/TelegramAnimatedStickerNode",
        "//submodules/ShimmerEffect",
        "//submodules/StickerResources",
        "//submodules/TelegramUI/Components/ListItemComponentAdaptor",
        "//submodules/HexColor",
    ],
    visibility = [
        "//visibility:public",
    ],
)
