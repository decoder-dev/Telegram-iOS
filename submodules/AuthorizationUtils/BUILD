load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "AuthorizationUtils",
    module_name = "AuthorizationUtils",
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
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Display:Display",
        "//submodules/TextFormat:TextFormat",
        "//submodules/Markdown:Markdown",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
    ],
    visibility = [
        "//visibility:public",
    ],
)
