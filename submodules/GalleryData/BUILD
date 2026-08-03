load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "GalleryData",
    module_name = "GalleryData",
    srcs = glob([
		"Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
        # Xcode 27: keep new diagnostic groups as warnings (SE-0443 last-wins)
        "-Wwarning", "ImplicitStrongCapture",
        "-Wwarning", "DeprecatedDeclaration",
        "-Wwarning", "NoUseUnstructuredThrowingTask",
    ],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/Display:Display",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/AccountContext:AccountContext",
        "//submodules/AppBundle:AppBundle",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/InstantPageUI:InstantPageUI",
        "//submodules/GalleryUI:GalleryUI",
        "//submodules/PeerAvatarGalleryUI:PeerAvatarGalleryUI",
        "//submodules/MediaResources:MediaResources",
        "//submodules/WebsiteType:WebsiteType",
        "//submodules/TelegramUI/Components/Stories/StoryContainerScreen",
    ],
    visibility = [
        "//visibility:public",
    ],
)
