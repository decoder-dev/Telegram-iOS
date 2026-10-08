#import <Foundation/Foundation.h>
#import <MtProtoKit/MTInputStream.h>
#include <assert.h>

static void checkBytes(const uint8_t *bytes, NSUInteger count, BOOL success, NSUInteger expectedLength) {
    bool failed = false;
    MTInputStream *stream = [[MTInputStream alloc] initWithData:[NSData dataWithBytes:bytes length:count]];
    NSData *result = [stream readBytes:&failed];
    assert(failed == !success);
    assert(success ? result != nil && result.length == expectedLength : result == nil);
}

int main(void) {
    @autoreleasepool {
        uint8_t small[] = {1, 'a', 0, 0};
        for (NSUInteger n = 0; n < sizeof(small); n++) checkBytes(small, n, NO, 0);
        checkBytes(small, sizeof(small), YES, 1);
        uint8_t empty[] = {0, 0, 0, 0};
        checkBytes(empty, sizeof(empty), YES, 0);
        uint8_t longValue[260] = {254, 255, 0, 0};
        for (NSUInteger n = 0; n < sizeof(longValue); n++) checkBytes(longValue, n, NO, 0);
        checkBytes(longValue, sizeof(longValue), YES, 255);
        uint8_t invalid[] = {255, 0, 0, 0};
        checkBytes(invalid, sizeof(invalid), NO, 0);
        uint8_t utf8[] = {1, 255, 0, 0};
        bool failed = false;
        MTInputStream *stream = [[MTInputStream alloc] initWithData:[NSData dataWithBytes:utf8 length:sizeof(utf8)]];
        assert([stream readString:&failed] == nil && failed);
        failed = false;
        assert([stream readData:-1 failed:&failed] == nil && failed);
        failed = false;
        assert([stream readData:0 failed:&failed].length == 0 && !failed);
        failed = false;
        assert([stream readMutableData:NSUIntegerMax failed:&failed] == nil && failed);
        puts("MTInputStream: truncation, boundary and invalid UTF-8 checks passed");
    }
    return 0;
}
