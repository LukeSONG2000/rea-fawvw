// MCSDKTrips.m — 历史行程查询（只读）
#import "MCSDK_Internal.h"
#import <objc/message.h>

@implementation MCSDK (Trips)

- (void)tripsOfCurrentVehicleWithCompletion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion {
    if (!self.vehicleActions) {
        !completion ? : completion(nil, [NSError errorWithDomain:@"MCSDK" code:-30
                    userInfo:@{NSLocalizedDescriptionKey: @"尚未选择车辆"}]);
        return;
    }
    // tripStatistics(tripType:statusFunction:)；TripType 为 Int 枚举，1=短期行程（0=长期、2=周期，依据 SDK TripType.description 反汇编）
    id action = ((id(*)(id,SEL,long,id))objc_msgSend)(self.vehicleActions,
        @selector(tripStatisticsWithTripType:statusFunction:), (long)1,
        ^(id trips) {
            // [TripData] → 摘要字典数组（不打印 VIN）
            NSMutableArray *out = [NSMutableArray array];
            for (id t in (NSArray *)trips) {
                NSMutableDictionary *d = [NSMutableDictionary dictionary];
                for (NSString *k in @[@"id",@"tripType",@"tripEnd",@"travelTime",@"startMileage",
                                      @"mileage",@"overallMileage",@"averageSpeed",
                                      @"averageFuelConsumption",@"averageElectricEngineConsumption",
                                      @"averageRecuperation",@"zeroEmissionDistance",@"reportReason"]) {
                    id v = MCSafeGet(t, k);
                    if (v) d[k] = [v description];
                }
                [out addObject:d];
            }
            if (completion) completion(out, nil);
        });
    ((id(*)(id,SEL,id))objc_msgSend)(action, @selector(loadWithErrorFunction:),
        ^(id sdkError) {
            NSString *msg = [sdkError description];
            if (completion) completion(nil, [NSError errorWithDomain:@"MCSDK" code:-70
                        userInfo:@{NSLocalizedDescriptionKey: msg}]);
        });
}

@end
