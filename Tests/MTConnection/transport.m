#import <Foundation/Foundation.h>
#import <MtProtoKit/MTQueue.h>
#import "MTTcpConnectionBehaviour.h"

static MTQueue *testQueue;
static void require(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "%s\n", message); exit(1); }
}
@interface Socket : NSObject
@property (nonatomic) NSUInteger stops;
- (void)stop;
@end
@implementation Socket
- (void)stop { self.stops++; }
@end
@interface MTTcpTransportContext : NSObject
@property (nonatomic) BOOL isNetworkAvailable;
@property (nonatomic) BOOL stopped;
@property (nonatomic) BOOL connectionConnected;
@property (nonatomic, strong) Socket *connection;
@property (nonatomic, strong) MTTcpConnectionBehaviour *connectionBehaviour;
@end
@implementation MTTcpTransportContext
@end
@interface MTTransport : NSObject
- (void)_networkAvailabilityChanged:(bool)available;
@end
@implementation MTTransport
- (void)_networkAvailabilityChanged:(bool)available {}
@end
@interface MTTcpTransport : MTTransport <MTTcpConnectionBehaviourDelegate> {
@public MTTcpTransportContext *_transportContext;
}
@property (nonatomic) NSUInteger attempts;
+ (MTQueue *)tcpTransportQueue;
@end
@implementation MTTcpTransport
+ (MTQueue *)tcpTransportQueue { return testQueue; }
- (void)tcpConnectionBehaviourRequestsReconnection:(MTTcpConnectionBehaviour *)behaviour error:(bool)error { self.attempts++; }
/* PRODUCTION_METHODS */
@end
int main(void) {
    @autoreleasepool {
        testQueue = [[MTQueue alloc] initWithName:"mt.transport.tests"];
        dispatch_sync(testQueue.nativeQueue, ^{
            MTTcpTransport *transport = [MTTcpTransport new];
            MTTcpTransportContext *context = [MTTcpTransportContext new];
            transport->_transportContext = context;
            context.isNetworkAvailable = YES;
            context.connectionBehaviour = [[MTTcpConnectionBehaviour alloc] initWithQueue:testQueue];
            context.connectionBehaviour.delegate = transport;
            [transport _networkAvailabilityChanged:false];
            // The socket has already been cleared when reachability returns.
            [transport _networkAvailabilityChanged:true];
            require(transport.attempts == 1, "Recovery with no socket did not reconnect");

            context.connection = [Socket new];
            context.connectionConnected = YES;
            for (NSUInteger i = 0; i < 100; i++) [transport _networkAvailabilityChanged:true];
            require(context.connection.stops == 0 && transport.attempts == 1, "Repeated reachability disrupted a live connection");
            [transport _networkAvailabilityChanged:false];
            require(context.connection.stops == 1, "Offline socket was not stopped");
            require(!context.connectionBehaviour.needsReconnection, "Offline transport retained retries");
            context.stopped = YES;
            [transport _networkAvailabilityChanged:true];
            require(!context.connectionBehaviour.needsReconnection && transport.attempts == 1, "Stopped transport was revived by reachability");
            puts("Offline recovery, live connection and stopped transport: passed");
        });
    }
    return 0;
}
