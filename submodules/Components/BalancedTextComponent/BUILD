load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "BalancedTextComponent",
    module_name = "BalancedTextComponent",
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
        "//submodules/Display:Display",
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/Markdown:Markdown",
    ],
    visibility = [
        "//visibility:public",
    ],
)
