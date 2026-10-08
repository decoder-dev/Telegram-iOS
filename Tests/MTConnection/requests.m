#import <Foundation/Foundation.h>
#import <MtProtoKit/MTQueue.h>
#import <MtProtoKit/MTTimer.h>

static NSUInteger idReads;
static void require(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "%s\n", message); exit(1); }
}
static double MTAbsoluteSystemTime(void) { return NSProcessInfo.processInfo.systemUptime; }
@interface ErrorContext : NSObject
@property (nonatomic, strong) id waitingForRequestToComplete;
@property (nonatomic) double minimalExecuteTime;
@end
@implementation ErrorContext
@end
@interface MTRequest : NSObject
@property (nonatomic, strong) id internalId;
@property (nonatomic, strong) ErrorContext *errorContext;
@property (nonatomic, strong) id requestContext;
@property (nonatomic) BOOL needsTimeoutTimer;
@end
@implementation MTRequest
@synthesize internalId = _internalId;
- (id)internalId { idReads++; return _internalId; }
@end
@interface MTProto : NSObject
@property (nonatomic) NSUInteger transactions;
- (void)requestTransportTransaction;
@end
@implementation MTProto
- (void)requestTransportTransaction { self.transactions++; }
@end
@interface MTRequestMessageService : NSObject {
@public
    MTQueue *_queue;
    NSArray<MTRequest *> *_requests;
    MTTimer *_requestsServiceTimer;
    MTTimer *_requestsTimeoutTimer;
    MTProto *_mtProto;
}
- (void)updateRequestsTimer;
- (void)updateRequestsTimeoutTimerWithReset:(bool)reset;
- (void)requestTimerEvent;
- (void)requestTimerTimeoutEvent;
@end
@implementation MTRequestMessageService
// The runner inserts these two methods verbatim from the production source.
/* PRODUCTION_METHODS */
- (void)requestTimerEvent { [_mtProto requestTransportTransaction]; }
- (void)requestTimerTimeoutEvent { [_mtProto requestTransportTransaction]; }
@end

int main(void) {
    @autoreleasepool {
        MTQueue *queue = [[MTQueue alloc] initWithName:"mt.requests.tests"];
        dispatch_sync(queue.nativeQueue, ^{
            MTRequestMessageService *service = [MTRequestMessageService new];
            service->_queue = queue;
            service->_mtProto = [MTProto new];
            NSMutableArray *requests = [NSMutableArray new];
            // Equal values, distinct identities: the dependency must use pointer identity.
            NSMutableString *lastId = [NSMutableString stringWithString:@"id"];
            for (NSUInteger i = 0; i < 2000; i++) {
                MTRequest *request = [MTRequest new];
                request.internalId = i == 1999 ? lastId : [NSObject new];
                request.errorContext = [ErrorContext new];
                request.errorContext.waitingForRequestToComplete = lastId;
                request.requestContext = [NSObject new];
                request.needsTimeoutTimer = YES;
                [requests addObject:request];
            }
            service->_requests = requests;
            idReads = 0;
            [service updateRequestsTimer];
            [service updateRequestsTimeoutTimerWithReset:false];
            require(service->_mtProto.transactions == 0, "A pending dependency was treated as complete");
            require(service->_requestsTimeoutTimer == nil, "A dependency-blocked request armed a timeout");
            printf("2000 dependent requests, two passes: %lu ID reads\n", (unsigned long)idReads);
            require(idReads <= 4000, "Dependency scans are not linear");

            MTRequest *first = requests[0];
            first.errorContext.waitingForRequestToComplete = [NSMutableString stringWithString:@"id"];
            [service updateRequestsTimer];
            [service updateRequestsTimeoutTimerWithReset:false];
            require(service->_mtProto.transactions == 1, "An equal-valued but absent dependency was not released");
            require(service->_requestsTimeoutTimer.isScheduled, "An eligible request did not arm its timeout");
            [service->_requestsTimeoutTimer invalidate];
            service->_requestsTimeoutTimer = nil;

            first.errorContext.waitingForRequestToComplete = lastId;
            first.requestContext = nil;
            first.errorContext.minimalExecuteTime = MTAbsoluteSystemTime() + 60;
            [service updateRequestsTimer];
            [service updateRequestsTimeoutTimerWithReset:false];
            require(service->_requestsServiceTimer.isScheduled, "Delayed request did not arm a wakeup");
            require(service->_requestsTimeoutTimer == nil, "Delayed request started a timeout early");
            first.errorContext.minimalExecuteTime = MTAbsoluteSystemTime() - 1;
            [service updateRequestsTimer];
            [service updateRequestsTimeoutTimerWithReset:false];
            require(service->_requestsServiceTimer == nil, "Expired delay retained its wakeup");
            require(service->_mtProto.transactions == 2, "Expired delay did not resume the request");
            require(service->_requestsTimeoutTimer.isScheduled, "Expired delay did not start timeout tracking");
            [service->_requestsTimeoutTimer invalidate];

            for (MTRequest *request in requests) request.errorContext = nil;
            idReads = 0;
            [service updateRequestsTimer];
            require(idReads == 0, "Dependency-free requests unnecessarily built the index");
            puts("Request dependency identity, delays and linear scan: passed");
        });
    }
    return 0;
}
