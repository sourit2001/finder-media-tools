#import <AppKit/AppKit.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "用法：invoke_service <video-path> [video-path ...]\n");
            return 64;
        }

        NSMutableArray<NSURL *> *inputURLs = [NSMutableArray arrayWithCapacity:(NSUInteger)argc - 1];
        for (int index = 1; index < argc; index++) {
            NSString *path = [NSString stringWithUTF8String:argv[index]];
            [inputURLs addObject:[NSURL fileURLWithPath:path].standardizedURL];
        }

        NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:@"MediaToolsPrototypeTests"];
        [pasteboard clearContents];

        if (![pasteboard writeObjects:inputURLs]) {
            fprintf(stderr, "无法把测试文件写入 NSPasteboard。\n");
            return 65;
        }

        if (!NSPerformService(@"提取音频", pasteboard)) {
            fprintf(stderr, "macOS 没有接受“提取音频”服务调用。\n");
            return 69;
        }

        printf("macOS 已接受“提取音频”服务调用：%lu 个文件\n", (unsigned long)inputURLs.count);
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:10.0]];
        return 0;
    }
}
