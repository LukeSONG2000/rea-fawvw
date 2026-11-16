#import "MCReadonlyVerification.h"
#import "MCSDK.h"
#import <sys/stat.h>

@implementation MCReadonlyVerification
+ (void)save:(NSDictionary *)result {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/p0-readonly-result.plist"];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [result writeToFile:path atomically:YES]; chmod(path.fileSystemRepresentation,0600);
}
+ (void)runWithProgress:(void (^)(NSString *))progress {
    NSMutableDictionary *result = [@{@"stage":@"initializing",@"physicalCommandsSent":@NO} mutableCopy];
    [self save:result];
    NSString *token = [NSUserDefaults.standardUserDefaults stringForKey:@"imported.idToken"];
    if (!token.length) { result[@"stage"]=@"missing-identity-token"; [self save:result]; progress(@"缺少本机诊断身份令牌"); return; }
    [[MCSDK shared] initializeSDK:^(NSError *error) {
        if (error) { result[@"stage"]=@"initialization-failed"; result[@"error"]=error.localizedDescription; [self save:result]; return; }
        result[@"stage"]=@"authenticating"; [self save:result];
        [[MCSDK shared] loginMBBWithIdentityToken:token completion:^(NSError *authError) {
            if (authError) { result[@"stage"]=@"authentication-failed"; result[@"error"]=authError.localizedDescription; [self save:result]; progress(@"MBB 认证失败"); return; }
            result[@"authenticated"]=@YES; result[@"stage"]=@"listing-vehicles"; [self save:result]; progress(@"MBB 认证成功，读取车辆列表…");
            [[MCSDK shared] vehicleVinsWithCompletion:^(NSArray<NSString *> *vins, NSError *listError) {
                if (listError) { result[@"stage"]=@"vehicle-list-failed"; result[@"error"]=listError.localizedDescription; [self save:result]; return; }
                result[@"vehicleCount"]=@(vins.count);
                if (!vins.count) { result[@"stage"]=@"no-vehicles"; [self save:result]; return; }
                result[@"stage"]=@"querying-status"; [self save:result];
                [self readVehicle:vins index:0 result:result records:[NSMutableArray array] progress:progress];
            }];
        }];
    }];
}
+ (void)readVehicle:(NSArray<NSString *> *)vins index:(NSUInteger)index result:(NSMutableDictionary *)result records:(NSMutableArray *)records progress:(void (^)(NSString *))progress {
    if (index >= vins.count) {
        result[@"stage"]=@"complete"; result[@"vehicles"]=records; [self save:result]; progress(@"只读验证完成，未发送车辆控制指令"); return;
    }
    [[MCSDK shared] selectVehicleWithVIN:vins[index] completion:^(NSError *selectionError) {
        if (selectionError) {
            [records addObject:@{@"index":@(index),@"selected":@NO,@"error":selectionError.localizedDescription}];
            [self readVehicle:vins index:index+1 result:result records:records progress:progress]; return;
        }
        [[MCSDK shared] statusOfCurrentVehicleWithCompletion:^(NSString *summary, NSError *statusError) {
            NSMutableDictionary *row=[@{@"index":@(index),@"selected":@YES,@"statusReceived":@(!statusError)} mutableCopy];
            if (statusError) row[@"error"]=statusError.localizedDescription;
            else {
                NSData *data=[summary dataUsingEncoding:NSUTF8StringEncoding];
                id decoded=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
                if ([decoded isKindOfClass:NSDictionary.class]) row[@"status"]=decoded;
            }
            [records addObject:row]; result[@"vehicles"]=records; [self save:result];
            progress([NSString stringWithFormat:@"第 %lu 辆车：%@",(unsigned long)index+1,statusError?@"状态返回错误":@"状态回调成功"]);
            [self readVehicle:vins index:index+1 result:result records:records progress:progress];
        }];
    }];
}
@end
