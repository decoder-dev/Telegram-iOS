#import <Foundation/Foundation.h>

@interface MTInternalMessageParser : NSObject

+ (id)parseMessage:(NSData *)data;
+ (NSData *)unwrapMessage:(NSData *)data;

@end
