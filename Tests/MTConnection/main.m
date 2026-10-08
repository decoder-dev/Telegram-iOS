#import <Foundation/Foundation.h>
#import <MtProtoKit/MTTimer.h>
#import <MtProtoKit/MTQueue.h>
#import "MTTcpConnectionBehaviour.h"

static void require(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "%s\n", message.UTF8String);
        exit(1);
    }
}

@interface ReconnectObserver : NSObject <MTTcpConnectionBehaviourDelegate>
@property (nonatomic) NSUInteger attempts;
@end
@implementation ReconnectObserver
- (void)tcpConnectionBehaviourRequestsReconnection:(MTTcpConnectionBehaviour *)behaviour error:(bool)error {
    self.attempts++;
}
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        require(argc == 2, @"Supply a test name");
        NSString *test = @(argv[1]);
        MTQueue *queue = [[MTQueue alloc] initWithName:"mt.connection.tests"];
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(queue.nativeQueue, ^{
            if ([test isEqualToString:@"rearm"] || [test isEqualToString:@"manual-rearm"]) {
                __block MTTimer *timer;
                __block NSUInteger count = 0;
                timer = [[MTTimer alloc] initWithTimeout:0.02 repeat:false completion:^{
                    if (++count == 1) {
                        [timer resetTimeout:0.02];
                    } else {
                        [timer invalidate];
                        timer = nil;
                        dispatch_semaphore_signal(done);
                    }
                } queue:queue.nativeQueue];
                if ([test isEqualToString:@"manual-rearm"]) {
                    [timer fireAndInvalidate];
                } else {
                    [timer start];
                }
            } else if ([test isEqualToString:@"restart-deadline"]) {
                __block MTTimer *timer;
                __block NSTimeInterval restartedAt;
                timer = [[MTTimer alloc] initWithTimeout:0.2 repeat:false completion:^{
                    require([NSProcessInfo processInfo].systemUptime - restartedAt >= 0.18, @"Old timer fired before the replacement deadline");
                    [timer invalidate];
                    timer = nil;
                    dispatch_semaphore_signal(done);
                } queue:queue.nativeQueue];
                [timer start];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), queue.nativeQueue, ^{
                    restartedAt = [NSProcessInfo processInfo].systemUptime;
                    [timer start];
                });
            } else {
                ReconnectObserver *observer = [[ReconnectObserver alloc] init];
                MTTcpConnectionBehaviour *behaviour = [[MTTcpConnectionBehaviour alloc] initWithQueue:queue];
                behaviour.delegate = observer;
                if ([test isEqualToString:@"disabled"]) {
                    behaviour.needsReconnection = false;
                    [behaviour requestConnection];
                    require(observer.attempts == 0, @"Disabled transport requested a connection");
                    dispatch_semaphore_signal(done);
                } else if ([test isEqualToString:@"cancel-retry"]) {
                    [behaviour requestConnection];
                    [behaviour connectionClosed];
                    behaviour.needsReconnection = false;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1200 * NSEC_PER_MSEC), queue.nativeQueue, ^{
                        require(observer.attempts == 1, @"A retry survived disabling reconnection");
                        behaviour.delegate = nil;
                        dispatch_semaphore_signal(done);
                    });
                } else if ([test isEqualToString:@"retry-floor"]) {
                    for (NSUInteger i = 0; i < 100; i++) [behaviour requestConnection];
                    require(observer.attempts == 1, @"A burst bypassed the minimum retry interval");
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1200 * NSEC_PER_MSEC), queue.nativeQueue, ^{
                        require(observer.attempts == 2, @"Pending retry did not run exactly once");
                        behaviour.needsReconnection = false;
                        dispatch_semaphore_signal(done);
                    });
                } else {
                    require(NO, @"Unknown test");
                }
            }
        });
        require(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0, @"Timed out: callback/retry was lost");
        printf("%s: passed\n", argv[1]);
    }
    return 0;
}
