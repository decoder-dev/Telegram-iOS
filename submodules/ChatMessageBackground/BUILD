load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatMessageBackground",
    module_name = "ChatMessageBackground",
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
    	"//submodules/TelegramPresentationData:TelegramPresentationData",
    	"//submodules/WallpaperBackgroundNode:WallpaperBackgroundNode",
    ],
    visibility = [
        "//visibility:public",
    ],
)
