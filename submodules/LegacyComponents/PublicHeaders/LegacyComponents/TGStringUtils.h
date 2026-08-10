#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
    
int32_t legacy_murMurHash32(NSString *string);
    
bool TGIsRTL();
bool TGIsArabic();
    
#ifdef __cplusplus
}
#endif

@interface TGStringUtils : NSObject

+ (NSString *)stringByEscapingForURL:(NSString *)string;

+ (NSString *)stringWithLocalizedNumber:(NSInteger)number;
+ (NSString *)stringWithLocalizedNumberCharacters:(NSString *)string;

+ (NSString *)md5:(NSString *)string;
+ (NSString *)md5ForData:(NSData *)data;

+ (NSArray *)stringComponentsForMessageTimerSeconds:(NSUInteger)seconds;
+ (NSString *)stringForFileSize:(int64_t)size precision:(NSInteger)precision;

+ (NSString *)integerValueFormat:(NSString *)prefix value:(NSInteger)value;

@end

@interface NSData (Telegraph)

+ (NSData *)dataWithHexString:(NSString *)hex;
- (NSString *)stringByEncodingInHex;

@end
