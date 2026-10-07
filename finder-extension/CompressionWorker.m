#import <Foundation/Foundation.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <math.h>

// A separate worker lets the small Finder panel cancel without blocking AppKit.
// Only the current encoder is signalled; completed files are never removed.
static volatile sig_atomic_t cancelled = 0;
static volatile sig_atomic_t encoderPID = 0;
static void Stop(int signalNumber) {
    cancelled = 1;
    if (encoderPID > 0) kill(encoderPID, SIGTERM);
}
static void Emit(NSDictionary *event) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:event options:0 error:nil];
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}
static unsigned long long FileBytes(NSString *path) {
    return [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue];
}
static NSData *Run(NSString *executable, NSArray *arguments, int *status, void (^lineHandler)(NSString *)) {
    if (cancelled) { *status = 130; return nil; }
    NSTask *task = [NSTask new];
    NSPipe *pipe = [NSPipe pipe];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = arguments;
    task.standardOutput = pipe;
    task.standardError = NSFileHandle.fileHandleWithStandardError;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
        *status = 69; return nil;
    }
    encoderPID = task.processIdentifier;
    if (cancelled) kill(encoderPID, SIGTERM);
    NSMutableData *all = [NSMutableData data];
    NSMutableData *pending = [NSMutableData data];
    while (YES) {
        NSData *chunk = [pipe.fileHandleForReading availableData];
        if (!chunk.length) break;
        if (!lineHandler) [all appendData:chunk];
        else {
            [pending appendData:chunk];
            while (YES) {
                const unsigned char *bytes = pending.bytes;
                NSUInteger length = pending.length, end = 0;
                while (end < length && bytes[end] != '\n') ++end;
                if (end == length) break;
                NSString *line = [[NSString alloc] initWithBytes:bytes length:end encoding:NSUTF8StringEncoding];
                if (line) lineHandler(line);
                [pending replaceBytesInRange:NSMakeRange(0, end + 1) withBytes:NULL length:0];
            }
        }
    }
    [task waitUntilExit];
    encoderPID = 0;
    *status = cancelled ? 130 : task.terminationStatus;
    return all;
}
static NSDictionary *Probe(NSString *probe, NSString *path) {
    int status = 0;
    NSData *data = Run(probe, @[@"-v", @"error", @"-show_streams", @"-show_format", @"-of", @"json", path], &status, nil);
    if (status != 0 || !data.length) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:NSDictionary.class] ? json : nil;
}
static NSDictionary *Video(NSDictionary *info) {
    for (NSDictionary *stream in info[@"streams"]) {
        if ([stream[@"codec_type"] isEqual:@"video"] && ![stream[@"disposition"][@"attached_pic"] boolValue]) return stream;
    }
    return nil;
}
static NSString *Reserve(NSString *input, NSString *suffix) {
    NSString *stem = [[input stringByDeletingPathExtension] stringByAppendingString:suffix];
    for (NSUInteger i = 0; i < 10000; ++i) {
        NSString *path = i == 0 ? [stem stringByAppendingString:@".mp4"] : [NSString stringWithFormat:@"%@_%lu.mp4", stem, (unsigned long)i];
        int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL, 0600);
        if (fd >= 0) { close(fd); return path; }
        if (errno != EEXIST) return nil;
    }
    return nil;
}
static NSDictionary *Compress(NSString *input, double targetMB, NSString *resolution, BOOL mute, NSString *ffmpeg, NSString *probe, NSUInteger index, NSUInteger total) {
    unsigned long long original = FileBytes(input);
    NSString *name = input.lastPathComponent;
    void (^state)(NSString *) = ^(NSString *text) {
        Emit(@{@"type": @"state", @"name": name, @"index": @(index), @"total": @(total), @"detail": text});
    };
    NSDictionary *(^result)(NSString *, NSString *) = ^NSDictionary *(NSString *type, NSString *detail) {
        return @{@"type": type, @"input": input, @"name": name, @"detail": detail, @"originalBytes": @(original)};
    };
    state(@"Reading video…");
    NSDictionary *info = Probe(probe, input), *video = Video(info);
    if (cancelled) return result(@"cancelled", @"Cancelled");
    double duration = [info[@"format"][@"duration"] doubleValue];
    if (!video || !isfinite(duration) || duration <= 0 || !original)
        return result(@"error", @"Cannot read this video. The file may be damaged or unsupported.");
    BOOL hasAudio = NO;
    for (NSDictionary *stream in info[@"streams"]) if ([stream[@"codec_type"] isEqual:@"audio"]) hasAudio = YES;
    hasAudio = hasAudio && !mute;
    unsigned long long limit = targetMB > 0 ? (unsigned long long)(targetMB * 1000000.0) : 0;
    int width = [video[@"width"] intValue], height = [video[@"height"] intValue];
    for (NSDictionary *side in video[@"side_data_list"]) {
        double rotation = fabs([side[@"rotation"] doubleValue]);
        if (fabs(fmod(rotation, 180.0) - 90.0) < 1) { int swap = width; width = height; height = swap; break; }
    }
    int requestedEdge = [resolution isEqual:@"720"] ? 1280 : [resolution isEqual:@"1080"] ? 1920 : 0;
    NSArray *sarParts = [video[@"sample_aspect_ratio"] componentsSeparatedByString:@":"];
    double sar = sarParts.count == 2 && [sarParts[1] doubleValue] > 0 ? [sarParts[0] doubleValue] / [sarParts[1] doubleValue] : 1;
    if (!isfinite(sar) || sar <= 0) sar = 1;
    BOOL needsResize = requestedEdge > 0 && MAX(width, height) > requestedEdge;
    BOOL compatible = [@[@"mp4", @"m4v"] containsObject:input.pathExtension.lowercaseString] && [video[@"codec_name"] isEqual:@"h264"];
    for (NSDictionary *stream in info[@"streams"]) if ([stream[@"codec_type"] isEqual:@"audio"] && ![stream[@"codec_name"] isEqual:@"aac"]) compatible = NO;
    if (limit && original < limit && compatible && !mute && !needsResize)
        return result(@"skipped", @"Already below the size limit. Original kept.");
    double audioRate = hasAudio ? 128000 : 0;
    double videoRate;
    if (limit) {
        double totalRate = (double)limit * 8 * 0.93 / duration;
        if (hasAudio && totalRate < 600000) audioRate = 64000;
        videoRate = totalRate - audioRate;
        if (videoRate < 80000)
            return result(@"error", @"This size is too small for the full video. Choose a larger limit or a shorter clip.");
    } else {
        double inputRate = (double)original * 8 / duration;
        videoRate = MIN(4000000, inputRate * 0.72 - audioRate);
        if (videoRate < 150000) return result(@"skipped", @"This video is already highly compressed. Original kept.");
    }
    NSString *suffix = limit ? [NSString stringWithFormat:@"_under-%gMB", targetMB] : @"_compressed";
    NSString *output = Reserve(input, suffix);
    if (!output) return result(@"error", @"Cannot write to this folder. Check its permissions or copy the video to a writable folder.");
    // The placeholder reserves a collision-free filename. Only a checked,
    // complete temporary file is renamed over that placeholder.
    NSString *temporary = [input.stringByDeletingLastPathComponent stringByAppendingPathComponent:
        [NSString stringWithFormat:@".convertright-%@.mp4", NSUUID.UUID.UUIDString]];
    NSString *passlog = [temporary stringByAppendingString:@"-pass"];
    BOOL software = videoRate < 900000;
    NSDictionary *answer = nil;
    for (NSUInteger attempt = 0; attempt < 4 && !cancelled; ++attempt) {
        int edge = requestedEdge;
        if ([resolution isEqual:@"auto"]) {
            edge = videoRate < 400000 ? 640 : videoRate < 900000 ? 960 : videoRate < 2000000 ? 1280 : 1920;
        }
        NSMutableArray<NSString *> *filters = [NSMutableArray array];
        if (fabs(sar - 1) > 0.001) [filters addObject:@"scale=w='trunc(iw*sar/2)*2':h='trunc(ih/2)*2',setsar=1"];
        NSString *transfer = video[@"color_transfer"];
        BOOL hdr = [transfer isEqual:@"smpte2084"] || [transfer isEqual:@"arib-std-b67"];
        if (hdr) {
            // Phone HDR needs tone mapping rather than merely dropping to 8 bits.
            [filters addObject:@"zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p"];
        }
        if (edge > 0) {
            int maxWidth = width >= height ? edge : edge * 9 / 16;
            int maxHeight = width >= height ? edge * 9 / 16 : edge;
            [filters addObject:[NSString stringWithFormat:@"scale=w='min(iw,%d)':h='min(ih,%d)':force_original_aspect_ratio=decrease:force_divisible_by=2", maxWidth, maxHeight]];
        } else {
            [filters addObject:@"scale=trunc(iw/2)*2:trunc(ih/2)*2"];
        }
        [filters addObject:@"setsar=1"];
        NSMutableArray *args = [NSMutableArray arrayWithArray:@[@"-hide_banner", @"-loglevel", @"error", @"-nostdin", @"-y", @"-i", input,
            @"-map", [NSString stringWithFormat:@"0:%@", video[@"index"]], @"-vf", [filters componentsJoinedByString:@","], @"-c:v", software ? @"libx264" : @"h264_videotoolbox",
            @"-b:v", [NSString stringWithFormat:@"%.0f", videoRate], @"-pix_fmt", @"yuv420p",
            @"-fpsmax", @"30", @"-tag:v", @"avc1"]];
        if (hdr) [args addObjectsFromArray:@[@"-color_primaries", @"bt709", @"-color_trc", @"bt709", @"-colorspace", @"bt709", @"-color_range", @"tv"]];
        if (software) [args addObjectsFromArray:@[@"-preset", @"fast"]];
        else [args addObjectsFromArray:@[@"-allow_sw", @"1"]];
        if (software && limit) {
            state(@"Analysing video for precise compression (pass 1 of 2)…");
            NSMutableArray *firstPass = [args mutableCopy];
            [firstPass addObjectsFromArray:@[@"-an", @"-pass", @"1", @"-passlogfile", passlog, @"-progress", @"pipe:1", @"-nostats", @"-f", @"null", @"/dev/null"]];
            int firstStatus = 0;
            Run(ffmpeg, firstPass, &firstStatus, ^(NSString *line) {
                if ([line hasPrefix:@"out_time_us="]) Emit(@{@"type": @"progress", @"fraction": @(MIN(0.49, [[line substringFromIndex:12] doubleValue] / 1000000 / duration * 0.5)), @"index": @(index), @"total": @(total)});
            });
            if (cancelled) break;
            if (firstStatus != 0) { answer = result(@"error", @"Video analysis failed. Original kept."); break; }
            [args addObjectsFromArray:@[@"-pass", @"2", @"-passlogfile", passlog]];
        }
        if (hasAudio) [args addObjectsFromArray:@[@"-map", @"0:a:0?", @"-c:a", @"aac", @"-b:a", [NSString stringWithFormat:@"%.0f", audioRate], @"-ac", @"2"]];
        else [args addObject:@"-an"];
        [args addObjectsFromArray:@[@"-map_metadata", @"-1", @"-map_chapters", @"-1", @"-movflags", @"+faststart", @"-progress", @"pipe:1", @"-nostats", temporary]];
        state(software && limit ? @"Compressing video (pass 2 of 2)…" : attempt ? @"Adjusting to fit the size limit…" : @"Compressing locally…");
        int status = 0;
        Run(ffmpeg, args, &status, ^(NSString *line) {
            if ([line hasPrefix:@"out_time_us="]) {
                double fraction = MIN(0.99, MAX(0, [[line substringFromIndex:12] doubleValue] / 1000000 / duration));
                Emit(@{@"type": @"progress", @"fraction": @(software && limit ? 0.5 + fraction * 0.5 : fraction), @"index": @(index), @"total": @(total)});
            }
        });
        if (cancelled) break;
        if (status != 0 && !software) { software = YES; continue; }
        if (status != 0) { answer = result(@"error", @"Video encoding failed. Original kept. See Library/Logs/ConvertRight Compression.log for details."); break; }
        unsigned long long bytes = FileBytes(temporary);
        if (!bytes) { answer = result(@"error", @"No video was generated. Original kept."); break; }
        if (limit && bytes >= limit) {
            software = YES;
            videoRate = MAX(40000, videoRate * ((double)limit * 0.88 / bytes));
            continue;
        }
        if (!limit && bytes >= original) { answer = result(@"skipped", @"Compression did not make this video smaller. Original kept."); break; }
        state(@"Checking the compressed video…");
        NSDictionary *outputInfo = Probe(probe, temporary);
        double outputDuration = [outputInfo[@"format"][@"duration"] doubleValue];
        if (cancelled) break;
        if (!Video(outputInfo) || !isfinite(outputDuration) || fabs(outputDuration - duration) > MAX(0.75, duration * 0.02)) {
            answer = result(@"error", @"The compressed video did not pass validation. Original kept."); break;
        }
        // Atomic rename on the same volume; never copy over the source.
        if (rename(temporary.fileSystemRepresentation, output.fileSystemRepresentation) != 0) {
            answer = result(@"error", @"Could not save the compressed video. Original kept."); break;
        }
        answer = @{@"type": @"success", @"input": input, @"output": output, @"name": name,
                   @"originalBytes": @(original), @"outputBytes": @(bytes)};
        break;
    }
    [[NSFileManager defaultManager] removeItemAtPath:temporary error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[passlog stringByAppendingString:@"-0.log"] error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[passlog stringByAppendingString:@"-0.log.mbtree"] error:nil];
    if (![answer[@"type"] isEqual:@"success"]) [[NSFileManager defaultManager] removeItemAtPath:output error:nil];
    return answer ?: result(cancelled ? @"cancelled" : @"error", cancelled ? @"Cancelled. Original kept." : @"Could not fit this video within the limit. Try a larger size.");
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        signal(SIGTERM, Stop); signal(SIGINT, Stop);
        if (argc < 5) { fprintf(stderr, "Usage: CompressionWorker <MB|0 for quick> <auto|original|1080|720> <keep|mute> <files...>\n"); return 64; }
        NSString *target = [NSString stringWithUTF8String:argv[1]];
        NSScanner *scanner = [NSScanner scannerWithString:target];
        double mb = 0;
        if (![scanner scanDouble:&mb] || !scanner.isAtEnd || !isfinite(mb) || mb < 0 || mb > 100000) return 64;
        NSString *resolution = [NSString stringWithUTF8String:argv[2]];
        NSString *audio = [NSString stringWithUTF8String:argv[3]];
        if (![@[@"auto", @"original", @"1080", @"720"] containsObject:resolution] || ![@[@"keep", @"mute"] containsObject:audio]) return 64;
        NSString *resources = [[[NSProcessInfo.processInfo.arguments firstObject] stringByStandardizingPath] stringByDeletingLastPathComponent];
        NSString *ffmpeg = [resources stringByAppendingPathComponent:@"ffmpeg"];
        NSString *probe = [resources stringByAppendingPathComponent:@"ffprobe"];
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:ffmpeg] || ![[NSFileManager defaultManager] isExecutableFileAtPath:probe]) return 69;
        NSUInteger successes = 0, failures = 0, skips = 0;
        for (int i = 4; i < argc && !cancelled; ++i) {
            @autoreleasepool {
                NSString *input = [[NSString stringWithUTF8String:argv[i]] stringByStandardizingPath];
                NSDictionary *event = Compress(input, mb, resolution, [audio isEqual:@"mute"], ffmpeg, probe, i - 4, argc - 4);
                Emit(event);
                if ([event[@"type"] isEqual:@"success"]) ++successes;
                else if ([event[@"type"] isEqual:@"skipped"]) ++skips;
                else if ([event[@"type"] isEqual:@"error"]) ++failures;
            }
        }
        Emit(@{@"type": @"finished", @"successes": @(successes), @"failures": @(failures), @"skips": @(skips), @"cancelled": @(cancelled != 0)});
        return cancelled ? 130 : failures ? 1 : 0;
    }
}
