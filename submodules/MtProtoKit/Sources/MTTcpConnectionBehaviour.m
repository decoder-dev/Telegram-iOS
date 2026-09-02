#import <Foundation/Foundation.h>

#import "MTTcpConnectionBehaviour.h"

#import <MtProtoKit/MTTimer.h>
#import <MtProtoKit/MTQueue.h>

/// Shortest gap allowed between two connection attempts.
///
/// The backoff below deliberately makes the first retry after a failure immediate, and
/// `requestConnection` connects at once whenever no backoff timer is armed. Both are right for the
/// case they were written for: a connection that worked for a while and dropped should come back
/// without a visible pause.
///
/// They are wrong for a peer that refuses instantly. A loopback port with nothing listening — which
/// is what MtProto is pointed at while the fork's WEB proxy has no carrier — fails a connect in
/// microseconds, so "immediate retry" becomes as fast as the queue can turn around. A tester's log
/// caught 4,176 connection attempts in twenty-five seconds, ending in a watchdog kill; in-flight
/// never rose above seven, so every one of them was resolving instantly rather than timing out.
///
/// One second is chosen to be longer than any plausible instant refusal and shorter than the 1/4/8
/// second ladder below, so it changes nothing about a normal reconnect: an attempt that got as far
/// as connecting, or that failed after a real network delay, is already past it.
static const NSTimeInterval MTTcpConnectionBehaviourMinimumAttemptInterval = 1.0;

@interface MTTcpConnectionBehaviour ()
{
    MTTimer *_backoffTimer;
    NSInteger _backoffCount;
    /// When the last attempt was handed to the delegate. Zero until the first one.
    CFAbsoluteTime _lastAttemptTimestamp;
}

@end

@implementation MTTcpConnectionBehaviour

- (instancetype)initWithQueue:(MTQueue *)queue
{
    self = [super init];
    if (self != nil)
    {
        _queue = queue;
        
        _needsReconnection = true;
    }
    return self;
}

- (void)dealloc
{
    [self invalidateTimer];
}

- (void)requestConnection
{
    if (_backoffTimer == nil) {
        // Not unconditionally: with no timer armed this is the path that reconnects as fast as it
        // is called, and after a fast failure it is called again immediately.
        NSTimeInterval sinceLastAttempt = [self intervalSinceLastAttempt];
        if (sinceLastAttempt < MTTcpConnectionBehaviourMinimumAttemptInterval) {
            [self startTimer:MTTcpConnectionBehaviourMinimumAttemptInterval - sinceLastAttempt];
            return;
        }
        [self timerEvent:false];
    }
}

- (NSTimeInterval)intervalSinceLastAttempt
{
    if (_lastAttemptTimestamp <= 0.0) {
        return DBL_MAX;
    }
    NSTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - _lastAttemptTimestamp;
    // The clock can step backwards; treat that as "long ago" rather than as a reason to stall.
    return elapsed < 0.0 ? DBL_MAX : elapsed;
}

- (void)connectionOpened
{
    //_backoffCount = 0;
    
    //[self invalidateTimer];
}

- (void)connectionValidDataReceived
{
    _backoffCount = 0;
    
    [self invalidateTimer];
}

- (void)connectionClosed
{
    if (_needsReconnection)
    {
        _backoffCount++;
        
        if (_backoffCount == 1) {
            // The immediate first retry is kept for a connection that actually lived: that is the
            // case it exists for. An attempt that ended within the minimum interval of starting
            // never got going, and retrying it at once just repeats the failure at queue speed.
            NSTimeInterval sinceLastAttempt = [self intervalSinceLastAttempt];
            if (sinceLastAttempt < MTTcpConnectionBehaviourMinimumAttemptInterval) {
                [self startTimer:MTTcpConnectionBehaviourMinimumAttemptInterval - sinceLastAttempt];
            } else {
                [self timerEvent:true];
            }
        }
        else
        {
            NSTimeInterval delay = 1.0;
            
            if (_backoffCount <= 5)
                delay = 1.0;
            else if (_backoffCount <= 20)
                delay = 4.0;
            else
                delay = 8.0;
            
            [self startTimer:delay];
        }
    }
}

- (void)clearBackoff
{
    _backoffCount = 0;
    // The pending wait goes with the count. Leaving an armed timer behind means the next
    // `requestConnection` returns without doing anything, so a transport that had climbed to the
    // eight-second rung keeps waiting it out even though the caller has just said the network is
    // back. The minimum-interval floor above is what keeps that from becoming a retry loop.
    [self invalidateTimer];
}

- (void)invalidateTimer
{
    MTTimer *reconnectionTimer = _backoffTimer;
    _backoffTimer = nil;
    
    [_queue dispatchOnQueue:^
    {
        [reconnectionTimer invalidate];
    }];
}

- (void)startTimer:(NSTimeInterval)timeout
{
    [self invalidateTimer];
    
    [_queue dispatchOnQueue:^
    {
        __weak MTTcpConnectionBehaviour *weakSelf = self;
        _backoffTimer = [[MTTimer alloc] initWithTimeout:timeout repeat:false completion:^
        {
            __strong MTTcpConnectionBehaviour *strongSelf = weakSelf;
            [strongSelf timerEvent:true];
        } queue:[_queue nativeQueue]];
        [_backoffTimer start];
    }];
}

- (void)timerEvent:(bool)error
{
    [self invalidateTimer];
    _lastAttemptTimestamp = CFAbsoluteTimeGetCurrent();
    
    [_queue dispatchOnQueue:^
    {
        id<MTTcpConnectionBehaviourDelegate> delegate = _delegate;
        if ([delegate respondsToSelector:@selector(tcpConnectionBehaviourRequestsReconnection:error:)])
            [delegate tcpConnectionBehaviourRequestsReconnection:self error:error];
    }];
}

@end
