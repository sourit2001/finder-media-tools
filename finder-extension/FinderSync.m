#import <AppKit/AppKit.h>
#import <FinderSync/FinderSync.h>

@interface FinderSync : FIFinderSync
@end

extern int NSExtensionMain(int argc, const char *argv[]);

int main(int argc, const char *argv[]) {
    return NSExtensionMain(argc, argv);
}

@implementation FinderSync

- (instancetype)init {
    self = [super init];
    if (self) {
        // A sandboxed extension's NSHomeDirectory points at its container,
        // not the user's real home folder. Monitoring the file-system root is
        // required so the context menu is available in Finder everywhere.
        NSMutableSet<NSURL *> *monitoredDirectories = [NSMutableSet setWithObject:
            [NSURL fileURLWithPath:@"/" isDirectory:YES]];

        // Finder Sync does not always treat the root directory as covering
        // removable volumes. Register every volume currently mounted under
        // /Volumes as an explicit monitored directory as well.
        NSArray<NSString *> *mountedVolumeNames =
            [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Volumes" error:nil];
        for (NSString *volumeName in mountedVolumeNames) {
            if ([volumeName hasPrefix:@"."]) {
                continue;
            }
            NSString *volumePath = [@"/Volumes" stringByAppendingPathComponent:volumeName];
            BOOL directory = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:volumePath isDirectory:&directory] && directory) {
                [monitoredDirectories addObject:[NSURL fileURLWithPath:volumePath isDirectory:YES]];
            }
        }

        [FIFinderSyncController defaultController].directoryURLs = monitoredDirectories;
        NSLog(@"Finder Audio Tools monitoring %lu directories", (unsigned long)monitoredDirectories.count);
        NSLog(@"Finder Audio Tools extension initialized");
    }
    return self;
}

- (NSMenu *)menuForMenuKind:(FIMenuKind)whichMenu {
    NSLog(@"Finder Audio Tools requested menu kind: %lu", (unsigned long)whichMenu);
    if (whichMenu != FIMenuKindContextualMenuForItems) {
        return nil;
    }

    NSArray<NSURL *> *selectedURLs = [FIFinderSyncController defaultController].selectedItemURLs;
    if (![self containsSupportedMedia:selectedURLs]) {
        return nil;
    }

    NSString *menuTitle = [self menuTitleForSelectedURLs:selectedURLs];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *parent = [[NSMenuItem alloc] initWithTitle:menuTitle
                                                    action:nil
                                             keyEquivalent:@""];
    NSMenu *formats = [[NSMenu alloc] initWithTitle:menuTitle];
    [formats addItem:[self itemWithTitle:@"MP3" action:@selector(convertToMP3:)]];
    [formats addItem:[self itemWithTitle:@"M4A" action:@selector(convertToM4A:)]];
    [formats addItem:[self itemWithTitle:@"WAV" action:@selector(convertToWAV:)]];
    parent.submenu = formats;
    [menu addItem:parent];
    NSSet *videos = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v", @"mkv", @"webm", @"avi"]];
    BOOL hasVideo = NO;
    for (NSURL *url in selectedURLs) if ([videos containsObject:url.pathExtension.lowercaseString]) hasVideo = YES;
    if (hasVideo) {
        NSMenuItem *compression = [[NSMenuItem alloc] initWithTitle:@"Compress Video" action:nil keyEquivalent:@""];
        NSMenu *presets = [[NSMenu alloc] initWithTitle:@"Compress Video"];
        [presets addItem:[self itemWithTitle:@"Quick Compress" action:@selector(compressQuick:)]];
        [presets addItem:NSMenuItem.separatorItem];
        [presets addItem:[self itemWithTitle:@"Under 10 MB" action:@selector(compress10:)]];
        [presets addItem:[self itemWithTitle:@"Under 20 MB" action:@selector(compress20:)]];
        [presets addItem:[self itemWithTitle:@"Under 50 MB" action:@selector(compress50:)]];
        [presets addItem:[self itemWithTitle:@"Under 100 MB" action:@selector(compress100:)]];
        [presets addItem:[self itemWithTitle:@"Custom Size…" action:@selector(compressCustom:)]];
        compression.submenu = presets;
        [menu addItem:compression];
    }
    return menu;
}

- (NSString *)menuTitleForSelectedURLs:(NSArray<NSURL *> *)urls {
    static NSSet<NSString *> *videoExtensions;
    static NSSet<NSString *> *audioExtensions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        videoExtensions = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v", @"mkv", @"webm", @"avi"]];
        audioExtensions = [NSSet setWithArray:@[
            @"mp3", @"m4a", @"aac", @"wav", @"flac", @"ogg", @"oga", @"opus", @"aif", @"aiff"
        ]];
    });

    BOOL hasVideo = NO;
    BOOL hasAudio = NO;
    for (NSURL *url in urls) {
        NSString *extension = url.pathExtension.lowercaseString;
        hasVideo = hasVideo || [videoExtensions containsObject:extension];
        hasAudio = hasAudio || [audioExtensions containsObject:extension];
    }

    if (hasVideo && !hasAudio) {
        return @"Extract Audio As…";
    }
    if (hasAudio && !hasVideo) {
        return @"Convert Audio To…";
    }
    return @"Convert to Audio…";
}

- (NSMenuItem *)itemWithTitle:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    return item;
}

- (BOOL)containsSupportedMedia:(NSArray<NSURL *> *)urls {
    static NSSet<NSString *> *extensions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        extensions = [NSSet setWithArray:@[
            @"mp4", @"mov", @"m4v", @"mkv", @"webm", @"avi",
            @"mp3", @"m4a", @"aac", @"wav", @"flac", @"ogg",
            @"oga", @"opus", @"aif", @"aiff"
        ]];
    });

    for (NSURL *url in urls) {
        if ([extensions containsObject:url.pathExtension.lowercaseString]) {
            return YES;
        }
    }
    return NO;
}

- (void)compressQuick:(id)sender { [self compressSelectedItems:@"quick"]; }
- (void)compress10:(id)sender { [self compressSelectedItems:@"10"]; }
- (void)compress20:(id)sender { [self compressSelectedItems:@"20"]; }
- (void)compress50:(id)sender { [self compressSelectedItems:@"50"]; }
- (void)compress100:(id)sender { [self compressSelectedItems:@"100"]; }
- (void)compressCustom:(id)sender { [self compressSelectedItems:@"custom"]; }
- (void)compressSelectedItems:(NSString *)target {
    NSArray<NSURL *> *urls = [FIFinderSyncController defaultController].selectedItemURLs;
    NSSet *videos = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v", @"mkv", @"webm", @"avi"]];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSURL *url in urls) if (url.isFileURL && [videos containsObject:url.pathExtension.lowercaseString]) [paths addObject:url.path];
    [self dispatchPaths:paths operation:@"compress" option:target];
}

- (void)convertToMP3:(id)sender { [self convertSelectedItemsToFormat:@"mp3"]; }
- (void)convertToM4A:(id)sender { [self convertSelectedItemsToFormat:@"m4a"]; }
- (void)convertToWAV:(id)sender { [self convertSelectedItemsToFormat:@"wav"]; }

- (void)convertSelectedItemsToFormat:(NSString *)format {
    NSArray<NSURL *> *selectedURLs = [FIFinderSyncController defaultController].selectedItemURLs;
    NSLog(@"Finder Audio Tools conversion requested: %@, selected: %lu",
          format, (unsigned long)selectedURLs.count);
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSURL *url in selectedURLs) {
        if (url.isFileURL && [self containsSupportedMedia:@[url]]) {
            [paths addObject:url.path];
        }
    }
    [self dispatchPaths:paths operation:@"convert" option:format];
}

- (void)dispatchPaths:(NSArray<NSString *> *)paths operation:(NSString *)operation option:(NSString *)option {
    if (paths.count == 0) {
        NSLog(@"Finder Audio Tools found no supported selected files");
        return;
    }

    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = @"finderaudiotools";
    components.host = operation;
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithObject:
        [NSURLQueryItem queryItemWithName:([operation isEqual:@"compress"] ? @"target" : @"format") value:option]];
    for (NSString *path in paths) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"path" value:path]];
    }
    components.queryItems = items;

    // Open the host that contains this exact extension. Dispatching only by the
    // custom URL scheme is ambiguous when an older copy or the mounted DMG is
    // still registered with Launch Services.
    NSURL *extensionURL = NSBundle.mainBundle.bundleURL;
    NSURL *hostAppURL = [[[[extensionURL URLByDeletingLastPathComponent]
                           URLByDeletingLastPathComponent]
                          URLByDeletingLastPathComponent] URLByStandardizingPath];
    if (![hostAppURL.pathExtension.lowercaseString isEqualToString:@"app"]) {
        NSLog(@"Finder Audio Tools could not resolve host app from %@", extensionURL.path);
        return;
    }

    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = NO;
    [[NSWorkspace sharedWorkspace]
        openURLs:@[components.URL]
        withApplicationAtURL:hostAppURL
        configuration:configuration
        completionHandler:^(NSRunningApplication *application, NSError *error) {
            NSLog(@"Finder Audio Tools handed conversion to host %@: %@",
                  hostAppURL.path,
                  error ? error.localizedDescription : @"yes");
        }];
}

@end
