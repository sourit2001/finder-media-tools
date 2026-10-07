#import <AppKit/AppKit.h>

NSDictionary *CompressionOptions(void);
@interface CompressionController : NSWindowController <NSWindowDelegate>
@property(nonatomic, copy) void (^onSuccess)(void);
@property(nonatomic, copy) void (^onFinished)(void);
@property(nonatomic, copy) void (^onClose)(void);
- (instancetype)initWithPaths:(NSArray<NSString *> *)paths options:(NSDictionary *)options;
- (void)start;
@end
