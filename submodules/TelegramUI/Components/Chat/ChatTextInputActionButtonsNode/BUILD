load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatTextInputActionButtonsNode",
    module_name = "ChatTextInputActionButtonsNode",
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
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/ContextUI",
        "//submodules/ChatPresentationInterfaceState",
        "//submodules/ChatMessageBackground",
        "//submodules/TelegramUI/Components/ChatControllerInteraction",
        "//submodules/AccountContext",
        "//submodules/TelegramUI/Components/ChatTextInputMediaRecordingButton",
        "//submodules/TelegramUI/Components/ChatSendButtonRadialStatusNode",
        "//submodules/ChatSendMessageActionUI",
        "//submodules/ComponentFlow",
        "//submodules/AnimatedCountLabelNode",
        "//submodules/TelegramUI/Components/GlassBackgroundComponent",
        "//submodules/TelegramUI/Components/StarsParticleEffect",
    ],
    visibility = [
        "//visibility:public",
    ],
)
