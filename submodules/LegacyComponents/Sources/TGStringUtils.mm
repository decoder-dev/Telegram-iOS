#import <LegacyComponents/TGStringUtils.h>

#import "LegacyComponentsInternal.h"

#import <CommonCrypto/CommonDigest.h>

#import <LegacyComponents/TGLocalization.h>
#import <LegacyComponents/TGPluralization.h>

@implementation TGStringUtils

+ (NSString *)stringByEscapingForURL:(NSString *)string
{
    static NSString * const kAFLegalCharactersToBeEscaped = @"?!@#$^&%*+=,.:;'\"`<>()[]{}/\\|~ ";

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSString *unescapedString = [string stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (unescapedString == nil)
        unescapedString = string;
    
    return (__bridge_transfer NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, (__bridge CFStringRef)unescapedString, NULL, (CFStringRef)kAFLegalCharactersToBeEscaped, CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
#pragma clang diagnostic pop
}

+ (NSString *)stringWithLocalizedNumber:(NSInteger)number
{
    return [self stringWithLocalizedNumberCharacters:[[NSString alloc] initWithFormat:@"%d", (int)number]];
}

+ (NSString *)stringWithLocalizedNumberCharacters:(NSString *)string
{
    NSString *resultString = string;
    
    if (TGIsArabic())
    {
        static NSString *arabicNumbers = @"٠١٢٣٤٥٦٧٨٩";
        NSMutableString *mutableString = [[NSMutableString alloc] init];
        for (int i = 0; i < (int)string.length; i++)
        {
            unichar c = [string characterAtIndex:i];
            if (c >= '0' && c <= '9')
                [mutableString replaceCharactersInRange:NSMakeRange(mutableString.length, 0) withString:[arabicNumbers substringWithRange:NSMakeRange(c - '0', 1)]];
            else
                [mutableString replaceCharactersInRange:NSMakeRange(mutableString.length, 0) withString:[string substringWithRange:NSMakeRange(i, 1)]];
        }
        resultString = mutableString;
    }
    
    return resultString;
}

+ (NSString *)md5:(NSString *)string
{
    /*static const char *md5PropertyKey = "MD5Key";
    NSString *result = objc_getAssociatedObject(string, md5PropertyKey);
    if (result != nil)
        return result;*/

    const char *ptr = [string UTF8String];
    unsigned char md5Buffer[16];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5(ptr, (CC_LONG)[string lengthOfBytesUsingEncoding:NSUTF8StringEncoding], md5Buffer);
#pragma clang diagnostic pop
    NSString *output = [[NSString alloc] initWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x", md5Buffer[0], md5Buffer[1], md5Buffer[2], md5Buffer[3], md5Buffer[4], md5Buffer[5], md5Buffer[6], md5Buffer[7], md5Buffer[8], md5Buffer[9], md5Buffer[10], md5Buffer[11], md5Buffer[12], md5Buffer[13], md5Buffer[14], md5Buffer[15]];
    //objc_setAssociatedObject(string, md5PropertyKey, output, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return output;
}

+ (NSString *)md5ForData:(NSData *)data {
    unsigned char md5Buffer[16];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5(data.bytes, (CC_LONG)data.length, md5Buffer);
#pragma clang diagnostic pop
    NSString *output = [[NSString alloc] initWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x", md5Buffer[0], md5Buffer[1], md5Buffer[2], md5Buffer[3], md5Buffer[4], md5Buffer[5], md5Buffer[6], md5Buffer[7], md5Buffer[8], md5Buffer[9], md5Buffer[10], md5Buffer[11], md5Buffer[12], md5Buffer[13], md5Buffer[14], md5Buffer[15]];
    return output;
}

+ (NSArray *)stringComponentsForMessageTimerSeconds:(NSUInteger)seconds
{
    NSString *first = @"";
    NSString *second = @"";
    
    if (seconds < 60)
    {
        int number = (int)seconds;
        
        NSString *format = TGLocalized([self integerValueFormat:@"MessageTimer.Seconds_" value:number]);
        
        NSRange range = [format rangeOfString:@"%@"];
        if (range.location != NSNotFound)
        {
            first = [[NSString alloc] initWithFormat:@"%d", number];
            second = [[format substringFromIndex:range.location + range.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else {
            first = format;
        }
    }
    else if (seconds < 60 * 60)
    {
        int number = (int)seconds / 60;

        NSString *format = TGLocalized([self integerValueFormat:@"MessageTimer.Minutes_" value:number]);
        
        NSRange range = [format rangeOfString:@"%@"];
        if (range.location != NSNotFound)
        {
            first = [[NSString alloc] initWithFormat:@"%d", number];
            second = [[format substringFromIndex:range.location + range.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else {
            first = format;
        }
    }
    else if (seconds < 60 * 60 * 24)
    {
        int number = (int)seconds / (60 * 60);

        NSString *format = TGLocalized([self integerValueFormat:@"MessageTimer.Hours_" value:number]);
        
        NSRange range = [format rangeOfString:@"%@"];
        if (range.location != NSNotFound)
        {
            first = [[NSString alloc] initWithFormat:@"%d", number];
            second = [[format substringFromIndex:range.location + range.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else {
            first = format;
        }
    }
    else if (seconds < 60 * 60 * 24 * 7)
    {
        int number = (int)seconds / (60 * 60 * 24);

        NSString *format = TGLocalized([self integerValueFormat:@"MessageTimer.Days_" value:number]);
        
        NSRange range = [format rangeOfString:@"%@"];
        if (range.location != NSNotFound)
        {
            first = [[NSString alloc] initWithFormat:@"%d", number];
            second = [[format substringFromIndex:range.location + range.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else {
            first = format;
        }
    }
    else if (seconds < 60 * 60 * 24 * 30)
    {
        int number = (int)seconds / (60 * 60 * 24 * 7);
        
        NSString *format = TGLocalized([self integerValueFormat:@"MessageTimer.Weeks_" value:number]);
        
        NSRange range = [format rangeOfString:@"%@"];
        if (range.location != NSNotFound)
        {
            first = [[NSString alloc] initWithFormat:@"%d", number];
            second = [[format substringFromIndex:range.location + range.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else {
            first = format;
        }
    }
    else
    {
        int number = (int)ceilf((seconds / (60 * 60 * 24 * 30.5f)));
        
        NSString *format = TGLocalized([self integerValueFormat:@"MessageTimer.Months_" value:number]);
        
        NSRange range = [format rangeOfString:@"%@"];
        if (range.location != NSNotFound)
        {
            first = [[NSString alloc] initWithFormat:@"%d", number];
            second = [[format substringFromIndex:range.location + range.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else {
            first = format;
        }
    }
    
    return @[first, second];
}

+ (NSString *)stringForFileSize:(int64_t)size precision:(NSInteger)precision
{
    NSString *string = @"";
    if (size < 1024)
    {
        string = [[NSString alloc] initWithFormat:TGLocalized(@"FileSize.B"), [[NSString alloc] initWithFormat:@"%d", (int)size]];}
    else if (size < 1024 * 1024)
    {
        string = [[NSString alloc] initWithFormat:TGLocalized(@"FileSize.KB"), [[NSString alloc] initWithFormat:@"%d", (int)(size / 1024)]];
    }
    else
    {
        NSString *format = [NSString stringWithFormat:@"%%0.%df", (int)precision];
        string = [[NSString alloc] initWithFormat:TGLocalized(@"FileSize.MB"), [[NSString alloc] initWithFormat:format, (CGFloat)(size / 1024.0f / 1024.0f)]];
    }
    
    return string;
}

+ (NSString *)integerValueFormat:(NSString *)prefix value:(NSInteger)value
{
    TGLocalization *localization = legacyEffectiveLocalization();
    NSString *form = @"any";
    switch (TGPluralForm(localization.languageCodeHash, (int)value)) {
        case TGPluralFormZero:
            form = @"0";
            break;
        case TGPluralFormOne:
            form = @"1";
            break;
        case TGPluralFormTwo:
            form = @"2";
            break;
        case TGPluralFormFew:
            form = @"3_10";
            break;
        case TGPluralFormMany:
            form = @"many";
            break;
        case TGPluralFormOther:
            form = @"any";
            break;
        default:
            break;
    }
    
    NSString *result = [prefix stringByAppendingString:form];
    if ([localization contains:result]) {
        return result;
    } else {
        return [prefix stringByAppendingString:@"any"];
    }
}

@end

#if defined(_MSC_VER)

#define FORCE_INLINE    __forceinline

#include <stdlib.h>

#define ROTL32(x,y)     _rotl(x,y)
#define ROTL64(x,y)     _rotl64(x,y)

#define BIG_CONSTANT(x) (x)

// Other compilers

#else   // defined(_MSC_VER)

#define FORCE_INLINE __attribute__((always_inline))

static inline uint32_t rotl32 ( uint32_t x, int8_t r )
{
    return (x << r) | (x >> (32 - r));
}

#define ROTL32(x,y)     rotl32(x,y)
#define ROTL64(x,y)     rotl64(x,y)

#define BIG_CONSTANT(x) (x##LLU)

#endif // !defined(_MSC_VER)

//-----------------------------------------------------------------------------
// Block read - if your platform needs to do endian-swapping or can only
// handle aligned reads, do the conversion here

static FORCE_INLINE uint32_t getblock ( const uint32_t * p, int i )
{
    return p[i];
}

//-----------------------------------------------------------------------------
// Finalization mix - force all bits of a hash block to avalanche

static FORCE_INLINE uint32_t fmix ( uint32_t h )
{
    h ^= h >> 16;
    h *= 0x85ebca6b;
    h ^= h >> 13;
    h *= 0xc2b2ae35;
    h ^= h >> 16;
    
    return h;
}

//----------

//-----------------------------------------------------------------------------

static void MurmurHash3_x86_32 ( const void * key, int len,
                         uint32_t seed, void * out )
{
    const uint8_t * data = (const uint8_t*)key;
    const int nblocks = len / 4;
    
    uint32_t h1 = seed;
    
    const uint32_t c1 = 0xcc9e2d51;
    const uint32_t c2 = 0x1b873593;
    
    //----------
    // body
    
    const uint32_t * blocks = (const uint32_t *)(data + nblocks*4);
    
    for(int i = -nblocks; i; i++)
    {
        uint32_t k1 = getblock(blocks,i);
        
        k1 *= c1;
        k1 = ROTL32(k1,15);
        k1 *= c2;
        
        h1 ^= k1;
        h1 = ROTL32(h1,13);
        h1 = h1*5+0xe6546b64;
    }
    
    //----------
    // tail
    
    const uint8_t * tail = (const uint8_t*)(data + nblocks*4);
    
    uint32_t k1 = 0;
    
    switch(len & 3)
    {
        case 3: k1 ^= tail[2] << 16;
        case 2: k1 ^= tail[1] << 8;
        case 1: k1 ^= tail[0];
            k1 *= c1; k1 = ROTL32(k1,15); k1 *= c2; h1 ^= k1;
    };
    
    //----------
    // finalization
    
    h1 ^= len;
    
    h1 = fmix(h1);
    
    *(uint32_t*)out = h1;
}

int32_t legacy_murMurHash32(NSString *string)
{
    const char *utf8 = string.UTF8String;
    
    int32_t result = 0;
    MurmurHash3_x86_32((uint8_t *)utf8, (int)strlen(utf8), -137723950, &result);
    
    return result;
}

bool TGIsRTL()
{
    static bool value = false;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        value = ([NSLocale characterDirectionForLanguage:[[NSLocale preferredLanguages] objectAtIndex:0]] == NSLocaleLanguageDirectionRightToLeft);
    });
    
    if (!value && iosMajorVersion() >= 9)
        value = [UIView appearance].semanticContentAttribute == UISemanticContentAttributeForceRightToLeft;
    
    return value;
}

bool TGIsArabic()
{
    static bool value = false;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        NSString *language = [[NSLocale preferredLanguages] objectAtIndex:0];
        value = [language isEqualToString:@"ar"] || [language hasPrefix:@"ar-"];
    });
    return value;
}

@implementation NSData (Telegraph)

+ (NSData *)dataWithHexString:(NSString *)hex
{
    char buf[3];
    buf[2] = '\0';
    NSAssert(0 == [hex length] % 2, @"Hex strings should have an even number of digits (%@)", hex);
    uint8_t *bytes = (uint8_t *)malloc(hex.length / 2);
    uint8_t *bp = bytes;
    for (CFIndex i = 0; i < [hex length]; i += 2) {
        buf[0] = [hex characterAtIndex:i];
        buf[1] = [hex characterAtIndex:i+1];
        char *b2 = NULL;
        *bp++ = strtol(buf, &b2, 16);
        NSAssert(b2 == buf + 2, @"String should be all hex digits: %@ (bad digit around %d)", hex, (int)i);
    }
    
    return [NSData dataWithBytesNoCopy:bytes length:[hex length]/2 freeWhenDone:YES];
}

- (NSString *)stringByEncodingInHex
{
    const unsigned char *dataBuffer = (const unsigned char *)[self bytes];
    if (dataBuffer == NULL)
        return [NSString string];
    
    NSUInteger dataLength  = [self length];
    NSMutableString *hexString  = [NSMutableString stringWithCapacity:(dataLength * 2)];
    
    for (int i = 0; i < (int)dataLength; ++i)
        [hexString appendString:[NSString stringWithFormat:@"%02lx", (unsigned long)dataBuffer[i]]];
    
    return hexString;
}

@end
