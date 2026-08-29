

#ifndef MTLogging_H
#define MTLogging_H

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

bool MTLogEnabled();

/// A decoded MTProto object, cut down to something a log line can hold.
///
/// `%@` on a parsed rpc result or update prints the entire object. A sticker set or a forum
/// topic list runs to hundreds of kilobytes on a single line, and in one tester's log the
/// responses alone came to 31.3 MB of 44 MB — 71% of everything collected, against a fixed
/// rotation budget. The head of the description identifies the message; the rest is payload.
NSString *MTLogTruncatedDescription(id value);
void MTLog(NSString *format, ...);
void MTLogWithPrefix(NSString *(^getLogPrefix)(), NSString *format, ...);
void MTShortLog(NSString *format, ...);
void MTLogSetLoggingFunction(void (*function)(NSString *));
void MTLogSetShortLoggingFunction(void (*function)(NSString *));
void MTLogSetEnabled(bool);

#ifdef __cplusplus
}
#endif

#endif
