#import <MtProtoKit/MTInputStream.h>

#import <Foundation/Foundation.h>
#import <MtProtoKit/MTLogging.h>

#if TARGET_OS_IPHONE
#   import <endian.h>
#endif

@interface MTInputStream ()
{
    NSInputStream *_wrappedInputStream;
}

@end

@implementation MTInputStream

- (instancetype)initWithData:(NSData *)data
{
    self = [super init];
    if (self != nil)
    {
        _wrappedInputStream = [[NSInputStream alloc] initWithData:data];
        [_wrappedInputStream open];
    }
    return self;
}

- (void)dealloc
{
    [_wrappedInputStream close];
}

- (NSInputStream *)wrappedInputStream
{
    return _wrappedInputStream;
}

- (int32_t)readInt32:(bool *)failed
{
    int32_t value = 0;
    
    if ([_wrappedInputStream read:(uint8_t *)&value maxLength:4] != 4)
    {
        *failed = true;
        return 0;
    }
    
#if __BYTE_ORDER == __LITTLE_ENDIAN
#elif __BYTE_ORDER == __BIG_ENDIAN
#   error "Big endian is not implemented"
#else
#   error "Unknown byte order"
#endif
    
    return value;
}

- (int64_t)readInt64:(bool *)failed
{
    int64_t value = 0;
    
    if ([_wrappedInputStream read:(uint8_t *)&value maxLength:8] != 8)
    {
        *failed = true;
        return 0;
    }
    
#if __BYTE_ORDER == __LITTLE_ENDIAN
#elif __BYTE_ORDER == __BIG_ENDIAN
#   error "Big endian is not implemented"
#else
#   error "Unknown byte order"
#endif
    
    return value;
}

- (double)readDouble:(bool *)failed
{
    double value = 0.0;
    
    if ([_wrappedInputStream read:(uint8_t *)&value maxLength:8] != 8)
    {
        *failed = true;
        return 0.0;
    }
    
#if __BYTE_ORDER == __LITTLE_ENDIAN
#elif __BYTE_ORDER == __BIG_ENDIAN
#   error "Big endian is not implemented"
#else
#   error "Unknown byte order"
#endif
    
    return value;
}

- (NSData *)readData:(int)length failed:(bool *)failed
{
    if (length < 0) {
        *failed = true;
        return nil;
    }
    if (length == 0) {
        return [NSMutableData data];
    }
    uint8_t *bytes = (uint8_t *)malloc(length);
    if (bytes == NULL) {
        *failed = true;
        return nil;
    }
    NSInteger readLen = [_wrappedInputStream read:bytes maxLength:length];
    if (readLen != length)
    {
        free(bytes);
        *failed = true;
        return nil;
    }
    NSData *data = [[NSData alloc] initWithBytesNoCopy:bytes length:length freeWhenDone:true];
    return data;
}

- (NSMutableData *)readMutableData:(NSUInteger)length failed:(bool *)failed
{
    if (length == 0) {
        return [NSMutableData data];
    }
    if (length > NSIntegerMax) {
        *failed = true;
        return nil;
    }
    uint8_t *bytes = (uint8_t *)malloc(length);
    if (bytes == NULL) {
        *failed = true;
        return nil;
    }
    NSInteger readLen = [_wrappedInputStream read:bytes maxLength:length];
    if (readLen != length)
    {
        free(bytes);
        *failed = true;
        return nil;
    }
    NSMutableData *data = [[NSMutableData alloc] initWithBytesNoCopy:bytes length:length freeWhenDone:true];
    return data;
}

- (NSString *)readString:(bool *)failed
{
    NSData *data = [self readBytes:failed];
    if (data == nil) {
        return nil;
    }
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (string == nil) {
        *failed = true;
    }
    return string;
}

- (NSData *)readBytes:(bool *)failed
{
    uint8_t marker = 0;
    if ([_wrappedInputStream read:&marker maxLength:1] != 1 || marker == 255) {
        *failed = true;
        return nil;
    }
    int32_t length = marker;
    int prefixLength = 1;
    if (marker == 254) {
        uint8_t encodedLength[3];
        if ([_wrappedInputStream read:encodedLength maxLength:3] != 3) {
            *failed = true;
            return nil;
        }
        length = (int32_t)encodedLength[0] | ((int32_t)encodedLength[1] << 8) | ((int32_t)encodedLength[2] << 16);
        prefixLength = 4;
    }
    NSData *result = [self readData:length failed:failed];
    if (result == nil) {
        return nil;
    }
    NSUInteger paddingLength = (4 - ((length + prefixLength) % 4)) % 4;
    uint8_t padding[3];
    if (paddingLength != 0 && [_wrappedInputStream read:padding maxLength:paddingLength] != (NSInteger)paddingLength) {
        *failed = true;
        return nil;
    }
    return result;
}

@end
