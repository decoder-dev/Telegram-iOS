load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "InstantPageCache",
    module_name = "InstantPageCache",
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
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/TelegramUIPreferences:TelegramUIPreferences",
        "//submodules/PersistentStringHash:PersistentStringHash",
        "//submodules/AccountContext:AccountContext",
        "//submodules/UrlHandling:UrlHandling",
    ],
    visibility = [
        "//visibility:public",
    ],
)
