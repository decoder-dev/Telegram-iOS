load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "UrlWhitelist",
    module_name = "UrlWhitelist",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
        # Xcode 27: keep new diagnostic groups as warnings (SE-0443 last-wins)
        "-Wwarning", "ImplicitStrongCapture",
        "-Wwarning", "DeprecatedDeclaration",
    ],
    visibility = [
        "//visibility:public",
    ],
)
