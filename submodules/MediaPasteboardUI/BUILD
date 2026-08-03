load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "MediaPasteboardUI",
    module_name = "MediaPasteboardUI",
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
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/AccountContext:AccountContext",
        "//submodules/AttachmentUI:AttachmentUI",
        "//submodules/MediaPickerUI:MediaPickerUI",
        "//submodules/AttachmentTextInputPanelNode",
    ],
    visibility = [
        "//visibility:public",
    ],
)
