#import <LegacyComponents/TGPhotoToolbarViewProtocol.h>
#import <LegacyComponents/TGPhotoPaintStickersContext.h>

NS_ASSUME_NONNULL_BEGIN

typedef UIView<TGPhotoToolbarViewProtocol> * _Nullable (^TGPhotoToolbarViewFactoryBlock)(TGPhotoEditorBackButton backButton, TGPhotoEditorDoneButton doneButton, bool solidBackground, bool hasSendStarsButton);

/// Registers the Swift `MediaPickerPhotoToolbarView` factory. Called once from LegacyMediaPickerUI.
FOUNDATION_EXPORT void TGPhotoToolbarViewRegisterFactory(TGPhotoToolbarViewFactoryBlock factory);

/// Creates a toolbar via stickersContext.photoToolbarView when set, otherwise the registered Swift factory.
FOUNDATION_EXPORT UIView<TGPhotoToolbarViewProtocol> *TGPhotoToolbarViewMake(id<TGPhotoPaintStickersContext> _Nullable stickersContext, TGPhotoEditorBackButton backButton, TGPhotoEditorDoneButton doneButton, bool solidBackground, bool hasSendStarsButton);

NS_ASSUME_NONNULL_END
