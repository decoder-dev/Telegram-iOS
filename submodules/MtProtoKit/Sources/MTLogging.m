#import <MtProtoKit/MTLogging.h>

static void (*loggingFunction)(NSString *) = NULL;
static void (*shortLoggingFunction)(NSString *) = NULL;
static bool MTLogEnabledValue = true;

bool MTLogEnabled() {
    return loggingFunction != NULL && MTLogEnabledValue;
}

NSString *MTLogTruncatedDescription(id value) {
    NSString *description = [NSString stringWithFormat:@"%@", value];
    static const NSUInteger limit = 1024;
    if (description.length <= limit) {
        return description;
    }
    // Expanded to whole character sequences, so the cut cannot land inside a surrogate pair.
    NSRange range = [description rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, limit)];
    return [NSString stringWithFormat:@"%@… (truncated, %lu characters total)", [description substringWithRange:range], (unsigned long)description.length];
}

void MTLog(NSString *format, ...) {
    va_list L;
    va_start(L, format);
    if (loggingFunction != NULL && MTLogEnabledValue) {
        NSString *string = [[NSString alloc] initWithFormat:format arguments:L];
        loggingFunction(string);
    }
    va_end(L);
}

void MTLogWithPrefix(NSString *(^getLogPrefix)(), NSString *format, ...) {
    va_list L;
    va_start(L, format);
    if (loggingFunction != NULL && MTLogEnabledValue) {
        NSString *string = [[NSString alloc] initWithFormat:format arguments:L];
        if (getLogPrefix) {
            NSString *prefix = getLogPrefix();
            if (prefix) {
                string = [prefix stringByAppendingString:string];
            }
        }
        loggingFunction(string);
    }
    va_end(L);
}

void MTShortLog(NSString *format, ...) {
    va_list L;
    va_start(L, format);
    if (shortLoggingFunction != NULL && MTLogEnabledValue) {
        NSString *string = [[NSString alloc] initWithFormat:format arguments:L];
        shortLoggingFunction(string);
    }
    va_end(L);
}

void MTLogSetLoggingFunction(void (*function)(NSString *)) {
    loggingFunction = function;
}

void MTLogSetShortLoggingFunction(void (*function)(NSString *)) {
    shortLoggingFunction = function;
}

void MTLogSetEnabled(bool enabled) {
    MTLogEnabledValue = enabled;
}
