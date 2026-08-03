load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "DCTAnimationCacheImpl",
    module_name = "DCTAnimationCacheImpl",
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
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/CryptoUtils:CryptoUtils",
        "//submodules/ManagedFile:ManagedFile",
        "//submodules/TelegramUI/Components/AnimationCache:AnimationCache",
        "//submodules/TelegramUI/Components/AnimationCache/ImageDCT:ImageDCT",
        "//third-party/subcodec:SubcodecObjC",
    ],
    visibility = [
        "//visibility:public",
    ],
)
