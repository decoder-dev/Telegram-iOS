load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TabSelectorComponent",
    module_name = "TabSelectorComponent",
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
        "//submodules/AsyncDisplayKit",
        "//submodules/Display",
        "//submodules/ComponentFlow",
        "//submodules/TelegramUI/Components/PlainButtonComponent",
        "//submodules/Components/MultilineTextWithEntitiesComponent",
        "//submodules/TextFormat",
        "//submodules/AccountContext",
        "//submodules/TelegramPresentationData",
    ],
    visibility = [
        "//visibility:public",
    ],
)
