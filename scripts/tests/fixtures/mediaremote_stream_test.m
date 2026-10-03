// Isolated stream regression: no MediaRemote framework or real application lookup.
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import "private/MediaRemote.h"
#import "adapter/globals.h"
#import "adapter/keys.h"

@interface FixtureWorkspace : NSObject
+ (instancetype)sharedWorkspace;
- (NSNotificationCenter *)notificationCenter;
@end
@implementation FixtureWorkspace
+ (instancetype)sharedWorkspace { static id value; if (!value) value = [self new]; return value; }
- (NSNotificationCenter *)notificationCenter { static id value; if (!value) value = [NSNotificationCenter new]; return value; }
@end

// Only substitute the external workspace boundary; all stream state/serialization
// decisions below are the production implementation.
#define NSWorkspace FixtureWorkspace
#import "adapter/stream.m"
#undef NSWorkspace

MediaRemote *g_mediaRemote;
dispatch_queue_t g_serialdispatchQueue;
NSString *kMRMediaRemoteNowPlayingInfoDidChangeNotification = @"fixture.info";
NSString *kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification = @"fixture.playing";
NSString *kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey = @"fixture.pid";
NSString *kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey = @"fixture.isPlaying";
NSString *kMRMediaRemoteNowPlayingInfoServiceIdentifier = @"fixture.service";

static NSMutableArray *pidReplies, *clientReplies, *playingReplies, *infoReplies, *payloads;
static void (^heldApplication)(NSRunningApplication *);
static int failures;
static BOOL raceApplication;
static BOOL refreshSamePlayer;

@interface FixtureApplication : NSObject
@property(nonatomic) pid_t processIdentifier;
@property(nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation FixtureApplication
@end

@interface FixtureClient : NSObject
@property(nonatomic, copy) NSString *parentApplicationBundleIdentifier;
@end
@implementation FixtureClient
@end

static NSRunningApplication *application(int pid) {
    FixtureApplication *app = [FixtureApplication new];
    app.processIdentifier = pid;
    app.bundleIdentifier = [NSString stringWithFormat:@"fixture.player.%d", pid];
    return (NSRunningApplication *)app;
}

bool appForPID(int pid, void (^reply)(NSRunningApplication *)) {
    if (raceApplication && pid == 303) heldApplication = [reply copy];
    else reply(application(pid));
    return true;
}

NSString *getEnvOption(NSString *name) { return [name isEqual:@"no_diff"] ? @"1" : nil; }
NSNumber *getEnvOptionInt(NSString *name) { return nil; }
void makePayloadHumanReadable(NSMutableDictionary *data) {}
NSMutableDictionary *convertNowPlayingInformation(NSDictionary *data, bool micros, bool now, bool noArtwork) {
    return [data mutableCopy];
}
NSString *serializeJsonDictionarySafe(NSDictionary *data, bool pretty) {
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:data options:0 error:NULL]
                                encoding:NSUTF8StringEncoding];
}
void printOutUnique(NSString *text) {
    NSDictionary *envelope = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding]
                                                             options:0 error:NULL];
    [payloads addObject:envelope[@"payload"]];
}

static void require(BOOL condition, NSString *message) {
    if (!condition) { failures++; fprintf(stderr, "%s\n", message.UTF8String); }
}
static void enqueue(dispatch_block_t block) { dispatch_async(g_serialdispatchQueue, block); }
static void notifyPlaying(int pid) {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification
        object:nil userInfo:@{kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey: @(pid),
                            kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey: @YES}];
}
static void finish() {
    dispatch_async(dispatch_get_main_queue(), ^{ _adapter_stream_cancel(); });
}
static void replyMetadata(int pid, NSString *title) {
    FixtureClient *client = [FixtureClient new];
    client.parentApplicationBundleIdentifier = [NSString stringWithFormat:@"fixture.parent.%d", pid];
    MRMediaRemoteGetNowPlayingClientCompletion_t parent = clientReplies.lastObject;
    MRMediaRemoteGetNowPlayingInfoCompletion_t info = infoReplies.lastObject;
    [clientReplies removeLastObject];
    [infoReplies removeLastObject];
    parent(client);
    info(@{kMRATitle: title});
}
static void replyCurrent(int pid) {
    replyMetadata(pid, [NSString stringWithFormat:@"title-%d", pid]);
}
static void assertCurrent(int pid) {
    NSDictionary *data = payloads.lastObject;
    require(allMandatoryPayloadKeysSet(data, false), @"playing-only notification must produce a complete payload");
    require([data[kMRAProcessIdentifier] isEqual:@(pid)], @"payload PID did not follow the playing notification");
    require([data[kMRABundleIdentifier] isEqual:[NSString stringWithFormat:@"fixture.player.%d", pid]], @"wrong bundle identity");
    require([data[kMRATitle] isEqual:[NSString stringWithFormat:@"title-%d", pid]], @"old metadata overwrote the current player");
    require([data[kMRAPlaying] isEqual:@YES], @"old playback state overwrote the current player");
    require([data[kMRAParentApplicationBundleIdentifier] isEqual:[NSString stringWithFormat:@"fixture.parent.%d", pid]], @"old parent identity overwrote the current player");
}

static void registerNotifications(dispatch_queue_t queue) {
    enqueue(^{
        notifyPlaying(101);
        enqueue(^{
            replyCurrent(101);
            assertCurrent(101);
            notifyPlaying(raceApplication ? 303 : refreshSamePlayer ? 101 : 202);
            enqueue(^{
                if (refreshSamePlayer) {
                    replyMetadata(101, @"new track from the same player");
                    NSDictionary *data = payloads.lastObject;
                    require([data[kMRATitle] isEqual:@"new track from the same player"], @"same-player notification discarded the replacement metadata request");
                    require([data[kMRAProcessIdentifier] isEqual:@101], @"same-player refresh changed identity");
                    finish();
                } else if (raceApplication) {
                    require(heldApplication != nil, @"old notification must be held at the lookup boundary");
                    notifyPlaying(404);
                    enqueue(^{
                        replyCurrent(404);
                        assertCurrent(404);
                        NSUInteger before = payloads.count;
                        heldApplication(application(303));
                        require(payloads.count == before, @"late application lookup published another player's state");
                        assertCurrent(404);
                        finish();
                    });
                } else {
                    replyCurrent(202);
                    assertCurrent(202);
                    NSUInteger before = payloads.count;
                    // All four startup requests were left pending before either
                    // player's notification. Their late replies must be ignored.
                    MRMediaRemoteGetNowPlayingApplicationPIDCompletion_t pid = pidReplies[0];
                    MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion_t playing = playingReplies[0];
                    MRMediaRemoteGetNowPlayingClientCompletion_t parent = clientReplies[0];
                    MRMediaRemoteGetNowPlayingInfoCompletion_t info = infoReplies[0];
                    pid(101); playing(false); parent(nil); info(@{kMRATitle: @"retired title"});
                    require(payloads.count == before, @"late startup replies published stale state");
                    assertCurrent(202);
                    finish();
                }
            });
        });
    });
}
static void unregisterNotifications(void) {}
static void requestPID(dispatch_queue_t q, MRMediaRemoteGetNowPlayingApplicationPIDCompletion_t block) { [pidReplies addObject:[block copy]]; }
static void requestClient(dispatch_queue_t q, MRMediaRemoteGetNowPlayingClientCompletion_t block) { [clientReplies addObject:[block copy]]; }
static void requestPlaying(dispatch_queue_t q, MRMediaRemoteGetNowPlayingApplicationIsPlayingCompletion_t block) { [playingReplies addObject:[block copy]]; }
static void requestInfo(dispatch_queue_t q, MRMediaRemoteGetNowPlayingInfoCompletion_t block) { [infoReplies addObject:[block copy]]; }

@implementation MediaRemote
- (MRMediaRemoteRegisterForNowPlayingNotifications_t)registerForNowPlayingNotifications { return registerNotifications; }
- (MRMediaRemoteUnregisterForNowPlayingNotifications_t)unregisterForNowPlayingNotifications { return unregisterNotifications; }
- (MRMediaRemoteGetNowPlayingApplicationPID_t)getNowPlayingApplicationPID { return requestPID; }
- (MRMediaRemoteGetNowPlayingClient_t)getNowPlayingClient { return requestClient; }
- (MRMediaRemoteGetNowPlayingInfo_t)getNowPlayingInfo { return requestInfo; }
- (MRMediaRemoteGetNowPlayingApplicationIsPlaying_t)getNowPlayingApplicationIsPlaying { return requestPlaying; }
- (MRMediaRemoteSendCommand_t)sendCommand { return NULL; }
- (MRMediaRemoteSetPlaybackSpeed_t)setPlaybackSpeed { return NULL; }
- (MRMediaRemoteSetElapsedTime_t)setElapsedTime { return NULL; }
- (MRMediaRemoteSetShuffleMode_t)setShuffleMode { return NULL; }
- (MRMediaRemoteSetRepeatMode_t)setRepeatMode { return NULL; }
- (id)init { return [super init]; }
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        raceApplication = argc > 1 && strcmp(argv[1], "application-race") == 0;
        refreshSamePlayer = argc > 1 && strcmp(argv[1], "same-player") == 0;
        pidReplies = [NSMutableArray new]; clientReplies = [NSMutableArray new];
        playingReplies = [NSMutableArray new]; infoReplies = [NSMutableArray new]; payloads = [NSMutableArray new];
        g_serialdispatchQueue = dispatch_queue_create("fixture.stream", DISPATCH_QUEUE_SERIAL);
        g_mediaRemote = [MediaRemote new];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            require(NO, @"stream regression timed out"); _adapter_stream_cancel();
        });
        adapter_stream();
        require(payloads.count > 0, @"stream produced no observations");
        printf("{\"failures\":%d,\"payloads\":%lu,\"real_media_access\":false}\n", failures, (unsigned long)payloads.count);
    }
    return failures ? 1 : 0;
}
