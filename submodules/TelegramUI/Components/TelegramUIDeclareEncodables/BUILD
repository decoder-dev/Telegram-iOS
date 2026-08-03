load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "TelegramUIDeclareEncodables",
    module_name = "TelegramUIDeclareEncodables",
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
        "//submodules/TelegramCore",
        "//submodules/TemporaryCachedPeerDataManager",
        "//submodules/TelegramUIPreferences",
        "//submodules/TelegramNotices",
        "//submodules/InstantPageUI",
        "//submodules/AccountContext",
        "//submodules/LocalMediaResources",
        "//submodules/InstantPageCache",
        "//submodules/SettingsUI",
        "//submodules/WallpaperResources",
        "//submodules/MediaResources",
        "//submodules/LocationUI",
        "//submodules/ChatInterfaceState",
        "//submodules/ICloudResources",
    ],
    visibility = [
        "//visibility:public",
    ],
)
