#import <AppKit/AppKit.h>
#import "CompressionUI.h"

static const NSInteger kFreeConversionLimit = 5;
static const NSTimeInterval kLicenseValidationInterval = 7 * 24 * 60 * 60;
static const NSTimeInterval kOfflineGraceInterval = 14 * 24 * 60 * 60;
// 0.6.2 starts a fresh, one-time Beta trial epoch. Keeping the new key stable
// across later releases prevents ordinary upgrades from resetting the limit.
static NSString * const kConversionCountKey = @"freeConversionCountV2";
static NSString * const kLastLicenseValidationKey = @"lastLicenseValidation";
#ifndef RCC_LICENSE_SERVER_URL
#define RCC_LICENSE_SERVER_URL @"https://rightclick-converter.sourit2001.chatgpt.site"
#endif
static NSString * const kLicenseServerURL = RCC_LICENSE_SERVER_URL;
static NSString * const kInstallationIdentifierKey = @"installationIdentifier";
static NSString * const kActivationTokenKey = @"activationToken";

static NSString *StoredValue(NSString *key) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static BOOL SetStoredValue(NSString *key, NSString *value) {
    [NSUserDefaults.standardUserDefaults setObject:value forKey:key];
    return [NSUserDefaults.standardUserDefaults synchronize];
}

static void DeleteStoredValue(NSString *key) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
    [NSUserDefaults.standardUserDefaults synchronize];
}

@interface FinderAudioToolsDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSMutableSet<NSTask *> *tasks;
@property(nonatomic) NSInteger pendingNetworkRequests;
@property(nonatomic) NSInteger pendingDialogs;
@property(nonatomic) NSInteger conversionReservations;
@property(nonatomic, strong) NSMutableSet<CompressionController *> *compressions;
@end

@implementation FinderAudioToolsDelegate

- (instancetype)init {
    self = [super init];
    if (self) { self.tasks = [NSMutableSet set]; self.compressions = [NSMutableSet set]; }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self quitWhenIdle];
    });
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) [self handleConversionURL:url];
}

- (void)quitWhenIdle {
    if (self.tasks.count == 0 && self.pendingNetworkRequests == 0 && self.pendingDialogs == 0 && self.compressions.count == 0) [NSApp terminate:nil];
}

- (NSString *)installationIdentifier {
    NSString *identifier = StoredValue(kInstallationIdentifierKey);
    if (identifier.length > 0) return identifier;
    identifier = NSUUID.UUID.UUIDString;
    return SetStoredValue(kInstallationIdentifierKey, identifier) ? identifier : nil;
}

- (void)handleConversionURL:(NSURL *)url {
    if (![url.scheme.lowercaseString isEqualToString:@"finderaudiotools"]) return;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if ([url.host.lowercaseString isEqualToString:@"unlock"]) {
        NSString *session = nil;
        for (NSURLQueryItem *item in components.queryItems) if ([item.name isEqualToString:@"session"]) session = item.value;
        if (session.length > 0) [self activatePaidSession:session];
        return;
    }
    if ([url.host.lowercaseString isEqualToString:@"compress"]) {
        NSString *target = nil;
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        NSSet *videos = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v", @"mkv", @"webm", @"avi"]];
        for (NSURLQueryItem *item in components.queryItems) {
            if ([item.name isEqual:@"target"]) target = item.value;
            if ([item.name isEqual:@"path"] && item.value.isAbsolutePath && [videos containsObject:item.value.pathExtension.lowercaseString]) [paths addObject:item.value];
        }
        if (![@[@"quick", @"20", @"50", @"100", @"custom"] containsObject:target] || !paths.count) return;
        self.pendingDialogs += 1;
        NSDictionary *options = [target isEqual:@"custom"] ? CompressionOptions() : @{@"mb": @([target isEqual:@"quick"] ? 0 : target.doubleValue), @"resolution": @"auto", @"mute": @NO};
        if (options) [self authorizePaths:paths action:^{ [self startCompression:paths options:options]; }];
        self.pendingDialogs -= 1;
        [self quitWhenIdle];
        return;
    }
    if (![url.host.lowercaseString isEqualToString:@"convert"]) return;

    NSString *format = nil;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"format"]) format = item.value.lowercaseString;
        if ([item.name isEqualToString:@"path"] && item.value.length > 0) [paths addObject:item.value];
    }
    if (![@[@"mp3", @"m4a", @"wav"] containsObject:format] || paths.count == 0) return;
    [self authorizeThenConvertPaths:paths format:format];
}

- (void)authorizeThenConvertPaths:(NSArray<NSString *> *)paths format:(NSString *)format {
    [self authorizePaths:paths action:^{ [self startConversionPaths:paths format:format]; }];
}

- (void)startCompression:(NSArray<NSString *> *)paths options:(NSDictionary *)options {
    CompressionController *controller = [[CompressionController alloc] initWithPaths:paths options:options];
    [self.compressions addObject:controller];
    __weak typeof(self) weakSelf = self;
    __weak CompressionController *weakController = controller;
    controller.onFinished = ^{ weakSelf.conversionReservations = MAX(0, weakSelf.conversionReservations - (NSInteger)paths.count); };
    controller.onSuccess = ^{ [weakSelf recordSuccessfulConversions:1]; };
    controller.onClose = ^{
        [weakSelf.compressions removeObject:weakController];
        [weakSelf quitWhenIdle];
    };
    [controller start];
}

- (void)authorizePaths:(NSArray<NSString *> *)paths action:(void (^)(void))action {
    NSString *token = StoredValue(kActivationTokenKey);
    if (token.length == 0) {
        NSInteger count = [NSUserDefaults.standardUserDefaults integerForKey:kConversionCountKey];
        if (count < kFreeConversionLimit && count + self.conversionReservations + (NSInteger)paths.count <= kFreeConversionLimit) {
            self.conversionReservations += paths.count;
            action();
        } else {
            [self showCheckout];
        }
        return;
    }
    NSDate *lastValidation = [NSUserDefaults.standardUserDefaults objectForKey:kLastLicenseValidationKey];
    if (lastValidation && -[lastValidation timeIntervalSinceNow] < kLicenseValidationInterval) {
        action();
        return;
    }
    [self validateLicenseToken:token completion:^(BOOL active, BOOL retryable) {
        if (active || (retryable && lastValidation && -[lastValidation timeIntervalSinceNow] < kOfflineGraceInterval)) {
            action();
        } else if (retryable) {
            [self showMessage:@"Connect to the internet" detail:@"RightClick Converter needs to verify your purchase before it can continue."];
        } else {
            DeleteStoredValue(kActivationTokenKey);
            [self showCheckout];
        }
    }];
}

- (void)showCheckout {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Unlock unlimited conversions";
    alert.informativeText = @"Your 5 free conversions are complete. Pay once and this Mac unlocks automatically when payment finishes.";
    [alert addButtonWithTitle:@"Continue to payment"];
    [alert addButtonWithTitle:@"Not now"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *installationId = [self installationIdentifier];
    if (!installationId) {
        [self showMessage:@"Unable to start payment" detail:@"macOS could not save this Mac's secure purchase identifier."];
        return;
    }
    NSURLComponents *components = [NSURLComponents componentsWithString:[kLicenseServerURL stringByAppendingString:@"/api/checkout"]];
    components.queryItems = @[[NSURLQueryItem queryItemWithName:@"installation_id" value:installationId]];
    [[NSWorkspace sharedWorkspace] openURL:components.URL];
}

- (void)activatePaidSession:(NSString *)sessionId {
    [self activatePaidSession:sessionId attempt:0];
}

- (void)activatePaidSession:(NSString *)sessionId attempt:(NSInteger)attempt {
    NSString *installationId = [self installationIdentifier];
    if (!installationId) return;
    [self postJSON:@"/api/license/activate" body:@{ @"sessionId": sessionId, @"installationId": installationId } completion:^(NSDictionary *response, BOOL retryable) {
        NSString *token = [response[@"activationToken"] isKindOfClass:NSString.class] ? response[@"activationToken"] : nil;
        if (token.length > 0 && SetStoredValue(kActivationTokenKey, token)) {
            [NSUserDefaults.standardUserDefaults setObject:NSDate.date forKey:kLastLicenseValidationKey];
            [NSUserDefaults.standardUserDefaults synchronize];
            [self showMessage:@"Unlimited conversions unlocked" detail:@"Payment confirmed. Return to Finder and convert any file."];
        } else if ([response[@"pending"] boolValue] && attempt < 10) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [self activatePaidSession:sessionId attempt:attempt + 1];
            });
        } else {
            [self showMessage:@"Payment is being confirmed" detail:@"Please wait a moment, then try the conversion again. No extra step is needed."];
        }
    }];
}

- (void)validateLicenseToken:(NSString *)token completion:(void (^)(BOOL active, BOOL retryable))completion {
    NSString *installationId = [self installationIdentifier];
    if (!installationId) { completion(NO, NO); return; }
    [self postJSON:@"/api/license/status" body:@{ @"installationId": installationId, @"activationToken": token } completion:^(NSDictionary *response, BOOL retryable) {
        BOOL active = [response[@"active"] boolValue];
        if (active) {
            [NSUserDefaults.standardUserDefaults setObject:NSDate.date forKey:kLastLicenseValidationKey];
            [NSUserDefaults.standardUserDefaults synchronize];
        }
        completion(active, retryable || [response[@"retry"] boolValue]);
    }];
}

- (void)postJSON:(NSString *)path body:(NSDictionary *)body completion:(void (^)(NSDictionary *response, BOOL retryable))completion {
    NSURL *url = [NSURL URLWithString:[kLicenseServerURL stringByAppendingString:path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    self.pendingNetworkRequests += 1;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *urlResponse, NSError *error) {
        NSDictionary *response = nil;
        if (data.length > 0) response = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        BOOL retryable = error != nil || ![urlResponse isKindOfClass:NSHTTPURLResponse.class] || ((NSHTTPURLResponse *)urlResponse).statusCode >= 500;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.pendingNetworkRequests -= 1;
            completion([response isKindOfClass:NSDictionary.class] ? response : @{}, retryable);
            [self quitWhenIdle];
        });
    }] resume];
}

- (void)startConversionPaths:(NSArray<NSString *> *)paths format:(NSString *)format {
    NSString *converterPath = [NSBundle.mainBundle pathForResource:@"convert_media" ofType:@"sh"];
    if (converterPath.length == 0) { self.conversionReservations = MAX(0, self.conversionReservations - (NSInteger)paths.count); return; }
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObject:format];
    [arguments addObjectsFromArray:paths];
    NSString *logDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:logDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *logPath = [logDirectory stringByAppendingPathComponent:@"Finder Audio Tools.log"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:logPath]) [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
    NSFileHandle *logHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    [logHandle seekToEndOfFile];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:converterPath];
    task.arguments = arguments;
    task.standardOutput = logHandle;
    task.standardError = logHandle;
    [self.tasks addObject:task];
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finishedTask) {
        [logHandle closeFile];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finishedTask.terminationStatus == 0) [weakSelf recordSuccessfulConversions:paths.count];
            weakSelf.conversionReservations = MAX(0, weakSelf.conversionReservations - (NSInteger)paths.count);
            [weakSelf.tasks removeObject:finishedTask];
            [weakSelf quitWhenIdle];
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [logHandle closeFile];
        self.conversionReservations = MAX(0, self.conversionReservations - (NSInteger)paths.count);
        [self.tasks removeObject:task];
    }
}

- (void)recordSuccessfulConversions:(NSUInteger)conversionCount {
    if (StoredValue(kActivationTokenKey).length > 0) return;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:[defaults integerForKey:kConversionCountKey] + (NSInteger)conversionCount forKey:kConversionCountKey];
    [defaults synchronize];
}

- (void)showMessage:(NSString *)title detail:(NSString *)detail {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = detail;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        FinderAudioToolsDelegate *delegate = [FinderAudioToolsDelegate new];
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        application.delegate = delegate;
        [application run];
    }
    return EXIT_SUCCESS;
}
