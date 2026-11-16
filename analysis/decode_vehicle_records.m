#import <Foundation/Foundation.h>
@interface CCOVehicleRecord : NSObject <NSCoding>
@property(nonatomic, copy) NSString *vin;
@property(nonatomic, copy) NSString *operateVehicleModelName;
@property(nonatomic, copy) NSString *modelName;
@property(nonatomic, copy) NSString *seriesName;
@property(nonatomic, copy) NSString *licensePlateNumber;
@property(nonatomic) BOOL isDefaultVehicle;
@end
@implementation CCOVehicleRecord
- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        for (NSString *key in @[@"vin", @"operateVehicleModelName", @"modelName", @"seriesName", @"licensePlateNumber"]) {
            id value = [coder decodeObjectForKey:key];
            if ([value isKindOfClass:NSString.class]) [self setValue:value forKey:key];
        }
        self.isDefaultVehicle = [[coder decodeObjectForKey:@"isDefaultVehicle"] boolValue];
        NSLog(@"decoded default=%d error=%@ keys=%@ model=%@",self.isDefaultVehicle, ((NSKeyedUnarchiver *)coder).error,[coder class], self.modelName);
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder {}
@end

int main(){ @autoreleasepool {
NSDictionary *prefs=[NSDictionary dictionaryWithContentsOfFile:@"/Users/lukesong/Work/Workspace/LukeSONG/fawvw/output/dropdown-preferences.plist"];
NSKeyedUnarchiver *r=[[NSKeyedUnarchiver alloc] initForReadingFromData:prefs[@"com.oneapp.coreentity.vehicles"] error:nil];
r.requiresSecureCoding=NO; [r setClass:CCOVehicleRecord.class forClassName:@"FVVehicle"];
NSArray *records=[r decodeObjectForKey:NSKeyedArchiveRootObjectKey];
for(id v in records) NSLog(@"class=%@ model=%@ default=%@ vinLength=%lu",[v class],[v valueForKey:@"modelName"],[v valueForKey:@"isDefaultVehicle"],(unsigned long)[[v valueForKey:@"vin"] length]);
}}