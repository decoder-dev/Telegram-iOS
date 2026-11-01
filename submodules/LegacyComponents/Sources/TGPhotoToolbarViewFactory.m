#import <LegacyComponents/TGPhotoToolbarViewFactory.h>

static TGPhotoToolbarViewFactoryBlock TGPhotoToolbarViewFactoryBlockStorage = nil;

void TGPhotoToolbarViewRegisterFactory(TGPhotoToolbarViewFactoryBlock factory)
{
    TGPhotoToolbarViewFactoryBlockStorage = [factory copy];
}

UIView<TGPhotoToolbarViewProtocol> *TGPhotoToolbarViewMake(id<TGPhotoPaintStickersContext> stickersContext, TGPhotoEditorBackButton backButton, TGPhotoEditorDoneButton doneButton, bool solidBackground, bool hasSendStarsButton)
{
    if (stickersContext.photoToolbarView != nil)
    {
        UIView<TGPhotoToolbarViewProtocol> *toolbarView = stickersContext.photoToolbarView(backButton, doneButton, solidBackground, hasSendStarsButton);
        if (toolbarView != nil)
            return toolbarView;
    }

    NSCAssert(TGPhotoToolbarViewFactoryBlockStorage != nil, @"TGPhotoToolbarViewRegisterFactory must run before creating a photo toolbar (import LegacyMediaPickerUI)");
    UIView<TGPhotoToolbarViewProtocol> *toolbarView = TGPhotoToolbarViewFactoryBlockStorage(backButton, doneButton, solidBackground, hasSendStarsButton);
    NSCAssert(toolbarView != nil, @"TGPhotoToolbarViewFactory returned nil");
    return toolbarView;
}
