load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ButtonComponent",
    module_name = "ButtonComponent",
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
        "//submodules/TelegramUI/Components/AnimatedTextComponent",
        "//submodules/ActivityIndicator",
        "//submodules/ShimmerEffect",
        "//submodules/Components/BundleIconComponent",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent",
        
    ],
    visibility = [
        "//visibility:public",
    ],
)
