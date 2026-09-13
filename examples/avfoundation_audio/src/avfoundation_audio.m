#import "avfoundation_audio.h"

@interface BSMAudioPlayer ()
@property(nonatomic, strong) AVAudioPlayer *player;
@end

@implementation BSMAudioPlayer

+ (instancetype)playerWithURL:(NSURL *)url {
  AVAudioPlayer *inner =
      [[AVAudioPlayer alloc] initWithContentsOfURL:url error:nil];
  if (inner == nil) {
    return nil;
  }
  BSMAudioPlayer *outer = [[BSMAudioPlayer alloc] init];
  outer.player = inner;
  return outer;
}

- (BOOL)play {
  return [self.player play];
}

- (void)stop {
  [self.player stop];
}

- (NSTimeInterval)duration {
  return self.player.duration;
}

@end
