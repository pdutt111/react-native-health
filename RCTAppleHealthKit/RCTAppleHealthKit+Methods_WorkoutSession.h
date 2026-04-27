//
//  RCTAppleHealthKit+Methods_WorkoutSession.h
//  RCTAppleHealthKit
//
//  iPhone-native workout session driver. iOS 17+ exposes HKWorkoutSession
//  on the phone, and once a session is active HealthKit will route HR
//  samples from any connected HR-capable accessory (Beats Pro 2,
//  AirPods Pro 3, paired Watch in foreground) into our anchored query.
//
//  Watch precedence is enforced at availability time via WCSession —
//  if a Watch is paired, isWorkoutSessionAvailable returns false and
//  consumers fall back to their existing flow.
//

#import "RCTAppleHealthKit.h"

@interface RCTAppleHealthKit (Methods_WorkoutSession)

- (void)workoutSession_isAvailable:(NSDictionary *)input callback:(RCTResponseSenderBlock)callback;
- (void)workoutSession_start:(NSDictionary *)input callback:(RCTResponseSenderBlock)callback;
- (void)workoutSession_stop:(NSDictionary *)input callback:(RCTResponseSenderBlock)callback;

@end
