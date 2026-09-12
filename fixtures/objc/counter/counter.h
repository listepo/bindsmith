// Fixture for the bindsmith ObjC driver: one interface with properties, a
// class method, a designated initializer, a completion handler and an
// NSError** out-parameter, plus a protocol and a category.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// How loudly the counter reports itself.
typedef NS_ENUM(NSInteger, BSMVolume) {
  BSMVolumeQuiet = 0,
  BSMVolumeNormal = 1,
  BSMVolumeLoud = 2,
};

/// Called once a count finishes.
typedef void (^BSMCountHandler)(NSInteger total, NSError *_Nullable error);

/// Receives counter updates.
@protocol BSMCounterDelegate <NSObject>
/// Called on every tick.
- (void)counterDidTick:(NSInteger)value;
@optional
/// Called once, after the last tick.
- (void)counterDidFinish;
@end

/// Counts things, loudly or otherwise.
@interface BSMCounter : NSObject

/// The current value.
@property(nonatomic, readonly) NSInteger value;

/// The label shown next to the value.
@property(nonatomic, copy) NSString *label;

/// Who to notify on every tick.
@property(nonatomic, weak, nullable) id<BSMCounterDelegate> delegate;

/// A counter that starts at zero.
+ (instancetype)counterWithLabel:(NSString *)label;

- (instancetype)initWithLabel:(NSString *)label NS_DESIGNATED_INITIALIZER;

/// Adds `amount` and returns the new value.
- (NSInteger)increment:(NSInteger)amount;

/// Counts up to `target`, then calls `handler`.
- (void)countTo:(NSInteger)target completion:(BSMCountHandler)handler;

/// Reports `NO` and fills `error` when `target` is negative.
- (BOOL)validate:(NSInteger)target error:(NSError **)error;

@end

/// Formatting helpers kept out of the main interface.
@interface BSMCounter (Formatting)
/// Renders the value at the given volume.
- (NSString *)describeWithVolume:(BSMVolume)volume;
@end

NS_ASSUME_NONNULL_END
