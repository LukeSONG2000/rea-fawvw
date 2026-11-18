#import <Foundation/Foundation.h>
#import "../src/MCSDK_Internal.h"
@interface MCGetterFixture:NSObject
@property(nonatomic) BOOL enabled;
@property(nonatomic) NSInteger code;
@property(nonatomic) double temperature;
@property(nonatomic,copy) NSString *title;
@property(nonatomic) NSRange range;
@end
@implementation MCGetterFixture
@end
int main(void) { @autoreleasepool {
    MCGetterFixture *f=[MCGetterFixture new]; f.enabled=YES; f.code=0x123456789LL; f.temperature=22.5; f.title=@"GTI"; f.range=NSMakeRange(1,3);
    NSCAssert([MCSafeGet(f,@"enabled") isEqual:@YES],@"BOOL must be boxed, not interpreted as a pointer");
    f.enabled=NO; NSCAssert([MCSafeGet(f,@"enabled") isEqual:@NO],@"False is a value, not nil");
    NSCAssert([MCSafeGet(f,@"code") longLongValue]==0x123456789LL,@"NSInteger ABI mismatch");
    NSCAssert([MCSafeGet(f,@"temperature") doubleValue]==22.5,@"Floating-point ABI mismatch");
    NSCAssert([MCSafeGet(f,@"title") isEqual:@"GTI"],@"Object getter mismatch");
    NSCAssert(MCSafeGet(f,@"missing")==nil,@"Missing selectors must not be invoked");
    NSCAssert(MCSafeGet(f,@"range")==nil,@"Struct returns require an explicit adapter");
    NSCAssert(MCSafeGet(f,@"setTitle:")==nil,@"Setters must not be invoked");
    puts("Safe getter ABI tests passed");
}}
