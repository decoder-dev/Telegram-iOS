#import <Foundation/Foundation.h>
#import <MtProtoKit/MTInputStream.h>
#import <MtProtoKit/MTIncomingMessage.h>
#import "MTMessage.h"
#import "MTMsgContainerMessage.h"

static void require(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "%s\n", message); exit(1); }
}
// Test the production post-authentication envelope checks, not cryptography.
static NSData *validate(NSData *decryptedData) {
/* ENVELOPE_VALIDATION */
}
@interface Session : NSObject
@property (nonatomic) int64_t sessionId;
@end
@implementation Session
@end
@interface MTProto : NSObject {
@public BOOL _useUnauthorizedMode;
@public Session *_sessionInfo;
}
@property (nonatomic, strong) NSData *parsedBody;
- (id)parseMessage:(NSData *)data;
- (NSArray *)_parseIncomingMessages:(NSData *)data dataMessageId:(out int64_t *)messageId embeddedAuthKeyId:(int64_t)authKeyId parseError:(out bool *)parseError;
@end
@implementation MTProto
- (id)parseMessage:(NSData *)data { self.parsedBody = data; return [NSObject new]; }
/* PRODUCTION_METHODS */
@end
static NSMutableData *packet(NSUInteger header, int32_t declared, NSUInteger actual, NSUInteger padding) {
    NSMutableData *data = [NSMutableData dataWithLength:header + actual + padding];
    [data replaceBytesInRange:NSMakeRange(header - 4, 4) withBytes:&declared];
    return data;
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        BOOL parserOnly = argc > 1 && strcmp(argv[1], "parser") == 0;
        if (!parserOnly) {
            require(validate(packet(32, 16, 16, 1024)) != nil, "Valid maximum padding rejected");
            require(validate(packet(32, 4, 4, 12)) != nil, "Valid minimum padding rejected");
            require(validate(packet(32, 16, 16, 0)) == nil, "Missing padding accepted");
            require(validate(packet(32, 4, 4, 1028)) == nil, "Oversized padding accepted");
            require(validate(packet(32, INT32_MIN, 16, 16)) == nil, "Negative body length accepted");
            require(validate(packet(32, INT32_MAX, 16, 16)) == nil, "Oversized body length accepted");
            require(validate(packet(32, 0, 0, 16)) == nil, "Empty body accepted");
            require(validate(packet(32, 5, 5, 27)) == nil, "Unaligned body accepted");
            for (NSUInteger length = 4; length <= 128; length += 4) {
                for (NSUInteger padding = 0; padding <= 1056; padding++) {
                    if ((32 + length + padding) % 16 != 0) continue;
                    require((validate(packet(32, (int32_t)length, length, padding)) != nil) == (padding >= 12 && padding <= 1024), "Padding boundary matrix mismatch");
                }
            }
            puts("Authenticated envelope length and padding boundaries: passed");
        }
        MTProto *proto = [MTProto new];
        proto->_sessionInfo = [Session new];
        for (NSUInteger header = 20; header <= 32; header += 12) {
            proto->_useUnauthorizedMode = header == 20;
            bool error = false;
            NSArray *messages = [proto _parseIncomingMessages:packet(header, 4, 4, 12) dataMessageId:NULL embeddedAuthKeyId:0 parseError:&error];
            require(!error && messages.count == 1 && proto.parsedBody.length == 4, "Parser included padding beyond declared body");
            require(((MTIncomingMessage *)messages[0]).size == 4, "Parsed message lost its declared size");
            proto.parsedBody = nil;
            error = false;
            messages = [proto _parseIncomingMessages:packet(header, 32, 4, 0) dataMessageId:NULL embeddedAuthKeyId:0 parseError:&error];
            require(error && messages == nil && proto.parsedBody == nil, "Truncated body reached the parser");
        }
        puts("Incoming body boundaries and truncation: passed");
    }
    return 0;
}
