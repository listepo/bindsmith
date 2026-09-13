#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin AVFoundation player declared in the entry header so the ObjC
/// driver can bind it. Framework-only headers are invisible to the pull list.
@interface BSMAudioPlayer : NSObject

+ (nullable instancetype)playerWithURL:(NSURL *)url;
- (BOOL)play;
- (void)stop;
@property(nonatomic, readonly) NSTimeInterval duration;

@end

NS_ASSUME_NONNULL_END
