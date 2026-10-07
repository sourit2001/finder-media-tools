#import "CompressionUI.h"
#include <math.h>

static NSTextField *Label(NSString *text, NSRect frame, CGFloat size, BOOL bold) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.frame = frame;
    label.font = bold ? [NSFont systemFontOfSize:size weight:NSFontWeightSemibold] : [NSFont systemFontOfSize:size];
    return label;
}
NSDictionary *CompressionOptions(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Compress video";
    alert.informativeText = @"Each video will fit below this limit. Processing stays on your Mac; originals are kept.";
    [alert addButtonWithTitle:@"Compress"];
    [alert addButtonWithTitle:@"Cancel"];
    NSView *form = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 350, 160)];
    [form addSubview:Label(@"Maximum size", NSMakeRect(0, 126, 130, 24), 13, NO)];
    NSTextField *size = [[NSTextField alloc] initWithFrame:NSMakeRect(145, 126, 140, 24)];
    double saved = [defaults doubleForKey:@"compressionTargetMB"];
    size.stringValue = [NSString stringWithFormat:@"%g", saved > 0 ? saved : 20];
    [form addSubview:size];
    [form addSubview:Label(@"MB", NSMakeRect(294, 126, 45, 24), 13, NO)];
    [form addSubview:Label(@"Resolution", NSMakeRect(0, 88, 130, 24), 13, NO)];
    NSPopUpButton *resolution = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(145, 88, 200, 26) pullsDown:NO];
    [resolution addItemsWithTitles:@[@"Automatic", @"Keep original", @"Up to 1080p", @"Up to 720p"]];
    NSArray *values = @[@"auto", @"original", @"1080", @"720"];
    NSUInteger selected = [values indexOfObject:[defaults stringForKey:@"compressionResolution"] ?: @"auto"];
    [resolution selectItemAtIndex:selected == NSNotFound ? 0 : selected];
    [form addSubview:resolution];
    NSButton *mute = [NSButton checkboxWithTitle:@"Remove audio" target:nil action:nil];
    mute.frame = NSMakeRect(145, 52, 200, 24);
    mute.state = [defaults boolForKey:@"compressionMute"] ? NSControlStateValueOn : NSControlStateValueOff;
    [form addSubview:mute];
    NSTextField *help = Label(@"Smaller limits can reduce picture quality. MP4 output, with the video's proportions preserved.", NSMakeRect(0, 0, 345, 42), 11, NO);
    help.textColor = NSColor.secondaryLabelColor;
    [form addSubview:help];
    alert.accessoryView = form;
    [alert.window setInitialFirstResponder:size];
    [NSApp activateIgnoringOtherApps:YES];
    while ([alert runModal] == NSAlertFirstButtonReturn) {
        NSScanner *scanner = [NSScanner scannerWithString:size.stringValue];
        double mb = 0;
        if (![scanner scanDouble:&mb] || !scanner.isAtEnd || !isfinite(mb) || mb < 0.1 || mb > 100000) {
            alert.informativeText = @"Enter a size from 0.1 to 100,000 MB. Each selected video gets its own limit.";
            continue;
        }
        NSString *r = values[resolution.indexOfSelectedItem];
        BOOL remove = mute.state == NSControlStateValueOn;
        [defaults setDouble:mb forKey:@"compressionTargetMB"];
        [defaults setObject:r forKey:@"compressionResolution"];
        [defaults setBool:remove forKey:@"compressionMute"];
        return @{@"mb": @(mb), @"resolution": r, @"mute": @(remove)};
    }
    return nil;
}
@interface CompressionController ()
@property(nonatomic, strong) NSArray<NSString *> *paths;
@property(nonatomic, strong) NSDictionary *options;
@property(nonatomic, strong) NSTask *task;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSProgressIndicator *progress;
@property(nonatomic, strong) NSButton *cancelButton;
@property(nonatomic, strong) NSButton *finderButton;
@property(nonatomic, strong) NSTextView *results;
@property(nonatomic, strong) NSMutableArray<NSURL *> *outputs;
@property(nonatomic) BOOL running;
@property(nonatomic) BOOL cancelling;
@property(nonatomic) BOOL receivedSummary;
@end
@implementation CompressionController
- (instancetype)initWithPaths:(NSArray<NSString *> *)paths options:(NSDictionary *)options {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 440, 320)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:panel];
    if (!self) return nil;
    self.paths = paths; self.options = options; self.outputs = [NSMutableArray array];
    panel.title = @"ConvertRight · Video Compression";
    panel.level = NSFloatingWindowLevel;
    panel.hidesOnDeactivate = NO;
    panel.delegate = self;
    NSVisualEffectView *glass = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 440, 320)];
    glass.material = NSVisualEffectMaterialHUDWindow;
    glass.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    glass.state = NSVisualEffectStateActive;
    panel.contentView = glass;
    self.titleLabel = Label(@"Preparing video…", NSMakeRect(22, 258, 396, 40), 15, YES);
    self.titleLabel.maximumNumberOfLines = 2;
    [glass addSubview:self.titleLabel];
    self.statusLabel = Label(@"Your original files will be kept.", NSMakeRect(22, 216, 396, 34), 12, NO);
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    [glass addSubview:self.statusLabel];
    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(22, 193, 396, 12)];
    self.progress.style = NSProgressIndicatorStyleBar;
    self.progress.indeterminate = YES;
    self.progress.maxValue = 100;
    [glass addSubview:self.progress];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(22, 66, 396, 113)];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    self.results = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 376, 113)];
    self.results.editable = NO;
    self.results.selectable = YES;
    self.results.drawsBackground = NO;
    self.results.font = [NSFont systemFontOfSize:12];
    self.results.textColor = NSColor.labelColor;
    self.results.verticallyResizable = YES;
    self.results.textContainer.widthTracksTextView = YES;
    scroll.documentView = self.results;
    [glass addSubview:scroll];
    self.cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelOrClose:)];
    self.cancelButton.frame = NSMakeRect(324, 20, 94, 30);
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    [glass addSubview:self.cancelButton];
    self.finderButton = [NSButton buttonWithTitle:@"Show in Finder" target:self action:@selector(reveal:)];
    self.finderButton.frame = NSMakeRect(22, 20, 148, 30);
    self.finderButton.bezelStyle = NSBezelStyleRounded;
    self.finderButton.hidden = YES;
    [glass addSubview:self.finderButton];
    [panel center];
    return self;
}
- (void)start {
    self.running = YES;
    [self showWindow:nil];
    [self.window orderFrontRegardless];
    NSString *worker = [NSBundle.mainBundle pathForResource:@"CompressionWorker" ofType:nil];
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:worker ?: @"/nonexistent"];
    NSMutableArray *args = [NSMutableArray arrayWithArray:@[[self.options[@"mb"] stringValue], self.options[@"resolution"], [self.options[@"mute"] boolValue] ? @"mute" : @"keep"]];
    [args addObjectsFromArray:self.paths];
    task.arguments = args;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *log = [directory stringByAppendingPathComponent:@"ConvertRight Compression.log"];
    if (![NSFileManager.defaultManager fileExistsAtPath:log]) [NSFileManager.defaultManager createFileAtPath:log contents:nil attributes:nil];
    NSFileHandle *logHandle = [NSFileHandle fileHandleForWritingAtPath:log];
    [logHandle seekToEndOfFile];
    task.standardError = logHandle ?: NSFileHandle.fileHandleWithNullDevice;
    self.task = task;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [logHandle closeFile];
        self.statusLabel.stringValue = error.localizedDescription;
        [self finish]; return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableData *pending = [NSMutableData data];
        while (YES) {
            NSData *chunk = [pipe.fileHandleForReading availableData];
            if (!chunk.length) break;
            [pending appendData:chunk];
            while (YES) {
                const unsigned char *bytes = pending.bytes;
                NSUInteger end = 0;
                while (end < pending.length && bytes[end] != '\n') ++end;
                if (end == pending.length) break;
                NSData *line = [pending subdataWithRange:NSMakeRange(0, end)];
                id event = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
                if ([event isKindOfClass:NSDictionary.class]) dispatch_async(dispatch_get_main_queue(), ^{ [self event:event]; });
                [pending replaceBytesInRange:NSMakeRange(0, end + 1) withBytes:NULL length:0];
            }
        }
        [task waitUntilExit];
        [logHandle closeFile];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.receivedSummary) self.statusLabel.stringValue = self.cancelling ? @"Cancelled. Original files kept." : @"Compression stopped unexpectedly. Original files kept. See the compression log for details.";
            [self finish];
        });
    });
}
- (void)appendResult:(NSString *)text {
    NSDictionary *attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:12], NSForegroundColorAttributeName: NSColor.labelColor};
    [self.results.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:[text stringByAppendingString:@"\n\n"] attributes:attributes]];
    [self.results scrollRangeToVisible:NSMakeRange(self.results.string.length, 0)];
}
- (void)event:(NSDictionary *)event {
    NSString *type = event[@"type"];
    if ([type isEqual:@"state"] || [type isEqual:@"progress"]) {
        if (self.cancelling) return;
        NSUInteger index = [event[@"index"] unsignedIntegerValue], total = [event[@"total"] unsignedIntegerValue];
        if ([type isEqual:@"state"]) {
            self.titleLabel.stringValue = [NSString stringWithFormat:@"%lu of %lu · %@", (unsigned long)(index + 1), (unsigned long)total, event[@"name"]];
            self.statusLabel.stringValue = event[@"detail"];
            self.progress.indeterminate = YES;
            [self.progress startAnimation:nil];
        } else {
            self.progress.indeterminate = NO;
            double fraction = [event[@"fraction"] doubleValue];
            self.progress.doubleValue = 100 * (index + fraction) / MAX(1, total);
        }
    } else if ([type isEqual:@"success"]) {
        [self.outputs addObject:[NSURL fileURLWithPath:event[@"output"]]];
        self.finderButton.hidden = NO;
        [self appendResult:[NSString stringWithFormat:@"%@\n%.2f MB → %.2f MB", event[@"name"], [event[@"originalBytes"] doubleValue] / 1000000, [event[@"outputBytes"] doubleValue] / 1000000]];
        if (self.onSuccess) self.onSuccess();
    } else if ([type isEqual:@"error"] || [type isEqual:@"skipped"] || [type isEqual:@"cancelled"]) {
        [self appendResult:[NSString stringWithFormat:@"%@\n%@", event[@"name"], event[@"detail"]]];
    } else if ([type isEqual:@"finished"]) {
        self.receivedSummary = YES;
        BOOL cancelled = [event[@"cancelled"] boolValue];
        self.titleLabel.stringValue = cancelled ? @"Compression cancelled" : @"Compression complete";
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ compressed · %@ skipped · %@ failed. Originals kept.", event[@"successes"], event[@"skips"], event[@"failures"]];
        if (cancelled) self.statusLabel.stringValue = [self.statusLabel.stringValue stringByAppendingString:@" Remaining files cancelled."];
        self.progress.indeterminate = NO;
        if (!cancelled) self.progress.doubleValue = 100;
    }
}
- (void)finish {
    BOOL wasRunning = self.running;
    self.running = NO;
    if (wasRunning && self.onFinished) self.onFinished();
    [self.progress stopAnimation:nil];
    self.progress.indeterminate = NO;
    self.cancelButton.title = @"Done";
    self.cancelButton.enabled = YES;
    self.task = nil;
}
- (void)cancelOrClose:(id)sender {
    if (!self.running) { [self close]; return; }
    if (self.cancelling) return;
    self.cancelling = YES;
    self.cancelButton.enabled = NO;
    self.statusLabel.stringValue = @"Cancelling… Completed files will be kept.";
    if (self.task.running) [self.task terminate];
}
- (void)reveal:(id)sender { [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:self.outputs]; }
- (BOOL)windowShouldClose:(NSWindow *)window {
    if (self.running) { [self cancelOrClose:nil]; return NO; }
    return YES;
}
- (void)windowWillClose:(NSNotification *)notification { if (self.onClose) self.onClose(); }
@end
