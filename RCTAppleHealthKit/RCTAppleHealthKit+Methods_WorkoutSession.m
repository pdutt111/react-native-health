//
//  RCTAppleHealthKit+Methods_WorkoutSession.m
//  RCTAppleHealthKit
//

#import "RCTAppleHealthKit+Methods_WorkoutSession.h"
#import "RCTAppleHealthKit+Utils.h"

#import <HealthKit/HealthKit.h>
#import <objc/runtime.h>

#if __has_include(<WatchConnectivity/WatchConnectivity.h>)
#import <WatchConnectivity/WatchConnectivity.h>
#define RNH_HAS_WATCH_CONNECTIVITY 1
#else
#define RNH_HAS_WATCH_CONNECTIVITY 0
#endif

// Associated-object keys — the category needs to keep references to the
// session, builder, and query so they survive across start/stop calls.
static char const * const kRNHWorkoutSessionKey = "RNHWorkoutSession";
static char const * const kRNHWorkoutBuilderKey = "RNHWorkoutBuilder";
static char const * const kRNHWorkoutHRQueryKey = "RNHWorkoutHRQuery";
static char const * const kRNHWorkoutSessionStartKey = "RNHWorkoutSessionStart";

@implementation RCTAppleHealthKit (Methods_WorkoutSession)

#pragma mark - Property accessors via associated objects

- (HKWorkoutSession *)rnh_workoutSession {
    return objc_getAssociatedObject(self, kRNHWorkoutSessionKey);
}
- (void)rnh_setWorkoutSession:(HKWorkoutSession *)value {
    objc_setAssociatedObject(self, kRNHWorkoutSessionKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id)rnh_workoutBuilder {
    return objc_getAssociatedObject(self, kRNHWorkoutBuilderKey);
}
- (void)rnh_setWorkoutBuilder:(id)value {
    objc_setAssociatedObject(self, kRNHWorkoutBuilderKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (HKAnchoredObjectQuery *)rnh_workoutHRQuery {
    return objc_getAssociatedObject(self, kRNHWorkoutHRQueryKey);
}
- (void)rnh_setWorkoutHRQuery:(HKAnchoredObjectQuery *)value {
    objc_setAssociatedObject(self, kRNHWorkoutHRQueryKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSDate *)rnh_workoutSessionStart {
    return objc_getAssociatedObject(self, kRNHWorkoutSessionStartKey);
}
- (void)rnh_setWorkoutSessionStart:(NSDate *)value {
    objc_setAssociatedObject(self, kRNHWorkoutSessionStartKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Helpers

+ (BOOL)rnh_isWatchPaired {
#if RNH_HAS_WATCH_CONNECTIVITY
    if ([WCSession isSupported]) {
        WCSession *session = [WCSession defaultSession];
        // Activation is a no-op when already active. We check synchronously.
        if (session.activationState == WCSessionActivationStateNotActivated) {
            [session activateSession];
        }
        return session.isPaired;
    }
#endif
    return NO;
}

+ (HKWorkoutActivityType)rnh_activityTypeFromString:(NSString *)s {
    if ([s isEqualToString:@"Running"]) return HKWorkoutActivityTypeRunning;
    if ([s isEqualToString:@"Cycling"]) return HKWorkoutActivityTypeCycling;
    if ([s isEqualToString:@"Walking"]) return HKWorkoutActivityTypeWalking;
    if ([s isEqualToString:@"HighIntensityIntervalTraining"]) return HKWorkoutActivityTypeHighIntensityIntervalTraining;
    if ([s isEqualToString:@"FunctionalStrengthTraining"]) return HKWorkoutActivityTypeFunctionalStrengthTraining;
    if ([s isEqualToString:@"TraditionalStrengthTraining"]) return HKWorkoutActivityTypeTraditionalStrengthTraining;
    if ([s isEqualToString:@"MixedCardio"]) return HKWorkoutActivityTypeMixedCardio;
    if ([s isEqualToString:@"CoreTraining"]) return HKWorkoutActivityTypeCoreTraining;
    if ([s isEqualToString:@"Yoga"]) return HKWorkoutActivityTypeYoga;
    return HKWorkoutActivityTypeFunctionalStrengthTraining;
}

+ (HKWorkoutSessionLocationType)rnh_locationTypeFromString:(NSString *)s {
    if ([s isEqualToString:@"outdoor"]) return HKWorkoutSessionLocationTypeOutdoor;
    if ([s isEqualToString:@"indoor"]) return HKWorkoutSessionLocationTypeIndoor;
    return HKWorkoutSessionLocationTypeUnknown;
}

#pragma mark - Public methods

- (void)workoutSession_isAvailable:(NSDictionary *)input callback:(RCTResponseSenderBlock)callback {
    BOOL available = NO;
    NSString *reason = @"unknown";

    // iPhone-side HKWorkoutSession requires iOS 17+.
    if (@available(iOS 17.0, *)) {
        if ([HKHealthStore isHealthDataAvailable]) {
            available = YES;
            reason = @"available";
        } else {
            reason = @"healthkit-not-available";
        }
    } else {
        reason = @"ios-below-17";
    }

    NSLog(@"[iPhoneWorkout][native] isAvailable: %@ (reason=%@, watchPaired=%@)",
          available ? @"YES" : @"NO",
          reason,
          [[self class] rnh_isWatchPaired] ? @"YES" : @"NO");

    callback(@[[NSNull null], @(available)]);
}

- (void)workoutSession_start:(NSDictionary *)input callback:(RCTResponseSenderBlock)callback {
    if (@available(iOS 17.0, *)) {
        if (self.rnh_workoutSession) {
            // Idempotent: re-entrant start collapses to the existing session.
            callback(@[[NSNull null], @{@"alreadyRunning": @YES}]);
            return;
        }

        NSString *activityStr = [RCTAppleHealthKit stringFromOptions:input
                                                                  key:@"activityType"
                                                          withDefault:@"FunctionalStrengthTraining"];
        NSString *locationStr = [RCTAppleHealthKit stringFromOptions:input
                                                                  key:@"locationType"
                                                          withDefault:@"unknown"];

        HKWorkoutConfiguration *config = [[HKWorkoutConfiguration alloc] init];
        config.activityType = [[self class] rnh_activityTypeFromString:activityStr];
        config.locationType = [[self class] rnh_locationTypeFromString:locationStr];

        NSError *sessionError = nil;
        HKWorkoutSession *session = [[HKWorkoutSession alloc] initWithHealthStore:self.healthStore
                                                                     configuration:config
                                                                              error:&sessionError];
        if (!session) {
            NSLog(@"[iPhoneWorkout][native] start FAILED: %@", sessionError.localizedDescription);
            callback(@[RCTJSErrorFromNSError(sessionError)]);
            return;
        }
        NSLog(@"[iPhoneWorkout][native] HKWorkoutSession created (activity=%@, location=%@)",
              activityStr, locationStr);

        HKLiveWorkoutBuilder *builder = session.associatedWorkoutBuilder;
        builder.dataSource = [[HKLiveWorkoutDataSource alloc] initWithHealthStore:self.healthStore
                                                                    workoutConfiguration:config];

        NSDate *startDate = [NSDate date];
        [session startActivityWithDate:startDate];
        NSLog(@"[iPhoneWorkout][native] startActivity at %@", startDate);
        [builder beginCollectionWithStartDate:startDate completion:^(BOOL success, NSError * _Nullable err) {
            NSLog(@"[iPhoneWorkout][native] beginCollection success=%@ err=%@",
                  success ? @"YES" : @"NO", err.localizedDescription ?: @"none");
            // Surface failures to the JS layer via an event so the caller
            // can decide to abort and fall back to the BLE/manual path.
            if (!success && err) {
                [self sendEventWithName:@"healthKit:WorkoutSession:failure"
                                   body:@{@"error": err.localizedDescription ?: @"unknown"}];
            }
        }];

        // Anchored HR query — emits live samples from whatever HR source
        // HealthKit routes into the session (AirPods Pro 3 / Beats Pro 2 /
        // foreground Watch).
        HKQuantityType *hrType = [HKQuantityType quantityTypeForIdentifier:HKQuantityTypeIdentifierHeartRate];
        HKAnchoredObjectQuery *query = [[HKAnchoredObjectQuery alloc]
            initWithType:hrType
               predicate:nil
                  anchor:nil
                   limit:HKObjectQueryNoLimit
          resultsHandler:^(HKAnchoredObjectQuery *q, NSArray<__kindof HKSample *> *samples, NSArray<HKDeletedObject *> *deleted, HKQueryAnchor *newAnchor, NSError *error) {
              [self rnh_emitHeartRateSamples:samples];
          }];
        query.updateHandler = ^(HKAnchoredObjectQuery *q, NSArray<__kindof HKSample *> *samples, NSArray<HKDeletedObject *> *deleted, HKQueryAnchor *newAnchor, NSError *error) {
            [self rnh_emitHeartRateSamples:samples];
        };
        [self.healthStore executeQuery:query];

        [self rnh_setWorkoutSession:session];
        [self rnh_setWorkoutBuilder:builder];
        [self rnh_setWorkoutHRQuery:query];
        [self rnh_setWorkoutSessionStart:startDate];

        callback(@[[NSNull null], @{
            @"started": @YES,
            @"startDate": @([startDate timeIntervalSince1970] * 1000),
        }]);
        return;
    }

    callback(@[RCTMakeError(@"iPhone HKWorkoutSession requires iOS 17+", nil, nil)]);
}

- (void)workoutSession_stop:(NSDictionary *)input callback:(RCTResponseSenderBlock)callback {
    if (@available(iOS 17.0, *)) {
        HKWorkoutSession *session = self.rnh_workoutSession;
        HKLiveWorkoutBuilder *builder = self.rnh_workoutBuilder;
        HKAnchoredObjectQuery *query = self.rnh_workoutHRQuery;

        if (!session && !builder) {
            callback(@[[NSNull null], @{@"stopped": @YES, @"alreadyStopped": @YES}]);
            return;
        }

        // Caller may pass an ISO end_time (matching the captured-stop-time
        // pattern used elsewhere). Fall back to now if absent or unparseable.
        NSDate *endDate = [NSDate date];
        NSString *endIso = [RCTAppleHealthKit stringFromOptions:input key:@"endedAt" withDefault:@""];
        if (endIso.length > 0) {
            NSISO8601DateFormatter *fmt = [[NSISO8601DateFormatter alloc] init];
            fmt.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
            NSDate *parsed = [fmt dateFromString:endIso];
            if (!parsed) {
                NSISO8601DateFormatter *fmt2 = [[NSISO8601DateFormatter alloc] init];
                fmt2.formatOptions = NSISO8601DateFormatWithInternetDateTime;
                parsed = [fmt2 dateFromString:endIso];
            }
            if (parsed) endDate = parsed;
        }

        if (query) {
            [self.healthStore stopQuery:query];
        }

        [session endCurrentActivityOnDate:endDate];
        [session end];

        [builder endCollectionWithEndDate:endDate completion:^(BOOL success, NSError * _Nullable err) {
            [builder finishWorkoutWithCompletion:^(HKWorkout * _Nullable workout, NSError * _Nullable finishErr) {
                // Always clear refs even if finish failed — the session is
                // terminated and no further samples should arrive.
                [self rnh_setWorkoutSession:nil];
                [self rnh_setWorkoutBuilder:nil];
                [self rnh_setWorkoutHRQuery:nil];
                [self rnh_setWorkoutSessionStart:nil];

                if (callback) {
                    callback(@[[NSNull null], @{
                        @"stopped": @YES,
                        @"endDate": @([endDate timeIntervalSince1970] * 1000),
                    }]);
                }
            }];
        }];
        return;
    }

    callback(@[RCTMakeError(@"iPhone HKWorkoutSession requires iOS 17+", nil, nil)]);
}

#pragma mark - Sample emission

- (void)rnh_emitHeartRateSamples:(NSArray<__kindof HKSample *> *)samples {
    if (samples.count == 0) return;
    NSLog(@"[iPhoneWorkout][native] HR samples received: %lu", (unsigned long)samples.count);
    NSDate *sessionStart = self.rnh_workoutSessionStart;
    HKUnit *bpm = [[HKUnit countUnit] unitDividedByUnit:[HKUnit minuteUnit]];
    // Filter out HR samples written by THIS app — otherwise saveHeartRate
    // writes from the JS layer feed back into the anchored query and the
    // app sees its own value as a "new" sample, creating a loop where the
    // last AirPods reading sticks forever after the buds come off.
    NSString *ownBundle = [[NSBundle mainBundle] bundleIdentifier];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:samples.count];
    for (HKQuantitySample *s in samples) {
        if (![s isKindOfClass:[HKQuantitySample class]]) continue;
        // Drop samples that pre-date the session — anchored queries can
        // surface a tail of historical points on first results-handler fire.
        if (sessionStart && [s.endDate compare:sessionStart] == NSOrderedAscending) continue;
        NSString *sourceBundle = s.sourceRevision.source.bundleIdentifier ?: @"";
        if (ownBundle && [sourceBundle isEqualToString:ownBundle]) {
            continue;  // ignore our own writes
        }
        double value = [s.quantity doubleValueForUnit:bpm];
        if (value <= 0) continue;
        [out addObject:@{
            @"value": @(value),
            @"startDate": @([s.startDate timeIntervalSince1970] * 1000),
            @"endDate": @([s.endDate timeIntervalSince1970] * 1000),
            @"sourceName": s.sourceRevision.source.name ?: @"",
            @"sourceBundle": sourceBundle,
        }];
    }
    if (out.count > 0) {
        [self sendEventWithName:@"healthKit:WorkoutSession:heartRate" body:@{@"samples": out}];
    }
}

@end
