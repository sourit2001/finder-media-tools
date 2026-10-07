// Development-only harness for the exact production compression UI and worker.
// Not included by either release build script, and never reads purchase data.
#import "../finder-extension/CompressionUI.h"
@interface Preview : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) CompressionController *controller;
@end
@implementation Preview
- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) {
        if (![url.host isEqual:@"compress"]) continue;
        NSString *target = nil;
        NSMutableArray *paths = [NSMutableArray array];
        for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
            if ([item.name isEqual:@"target"]) target = item.value;
            if ([item.name isEqual:@"path"]) [paths addObject:item.value];
        }
        NSDictionary *options = [target isEqual:@"custom"] ? CompressionOptions() : @{@"mb": @([target isEqual:@"quick"] ? 0 : target.doubleValue), @"resolution": @"auto", @"mute": @NO};
        if (!options || !paths.count) { [NSApp terminate:nil]; return; }
        self.controller = [[CompressionController alloc] initWithPaths:paths options:options];
        self.controller.onClose = ^{ [NSApp terminate:nil]; };
        [self.controller start];
    }
}
@end
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        Preview *delegate = [Preview new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
}
