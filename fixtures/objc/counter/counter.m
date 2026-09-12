// Implementation of the counter fixture: what the generated binding is called
// against in `fixtures/bin/counter_objc.dart`.

#import "counter.h"

/// Not in the header on purpose: the fixture's errors are its own business,
/// and a global constant would only add a binding shape already covered.
static NSString *const BSMCounterErrorDomain = @"BSMCounterError";

@implementation BSMCounter {
  NSInteger _value;
}

+ (instancetype)counterWithLabel:(NSString *)label {
  return [[self alloc] initWithLabel:label];
}

- (instancetype)initWithLabel:(NSString *)label {
  self = [super init];
  if (self) {
    _label = [label copy];
    _value = 0;
  }
  return self;
}

- (instancetype)init {
  return [self initWithLabel:@"count"];
}

- (NSInteger)value {
  return _value;
}

- (NSInteger)increment:(NSInteger)amount {
  _value += amount;
  [self.delegate counterDidTick:_value];
  return _value;
}

- (void)countTo:(NSInteger)target completion:(BSMCountHandler)handler {
  NSError *error = nil;
  if (![self validate:target error:&error]) {
    handler(_value, error);
    return;
  }
  while (_value < target) {
    [self increment:1];
  }
  id<BSMCounterDelegate> delegate = self.delegate;
  if ([delegate respondsToSelector:@selector(counterDidFinish)]) {
    [delegate counterDidFinish];
  }
  handler(_value, nil);
}

- (BOOL)validate:(NSInteger)target error:(NSError **)error {
  if (target >= 0) {
    return YES;
  }
  if (error != NULL) {
    *error = [NSError
        errorWithDomain:BSMCounterErrorDomain
                   code:1
               userInfo:@{
                 NSLocalizedDescriptionKey :
                     [NSString stringWithFormat:@"cannot count to %ld",
                                                (long)target]
               }];
  }
  return NO;
}

@end

@implementation BSMCounter (Formatting)

- (NSString *)describeWithVolume:(BSMVolume)volume {
  NSString *plain =
      [NSString stringWithFormat:@"%@ %ld", self.label, (long)self.value];
  switch (volume) {
    case BSMVolumeQuiet:
      return [plain lowercaseString];
    case BSMVolumeNormal:
      return plain;
    case BSMVolumeLoud:
      return [[plain uppercaseString] stringByAppendingString:@"!"];
  }
}

@end
