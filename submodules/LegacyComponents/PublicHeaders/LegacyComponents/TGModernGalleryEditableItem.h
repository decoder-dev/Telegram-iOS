#import <LegacyComponents/TGModernGalleryItem.h>
#import <LegacyComponents/TGPhotoToolbarViewProtocol.h>

@protocol TGMediaEditableItem;
@class TGMediaEditingContext;
@protocol TGPhotoPaintStickersContext;

@protocol TGModernGalleryEditableItem <TGModernGalleryItem>

@property (nonatomic, strong) TGMediaEditingContext *editingContext;
@property (nonatomic, strong) id<TGPhotoPaintStickersContext> stickersContext;

- (id<TGMediaEditableItem>)editableMediaItem;
- (TGPhotoEditorTab)toolbarTabs;
- (NSString *)uniqueId;

@end
