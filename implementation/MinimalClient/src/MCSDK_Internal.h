// MCSDK_Internal.h — 适配层内部状态（实现文件间共享，不对外）
#import "MCSDK.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>

@interface MCSDK ()
@property (nonatomic, strong, nullable) id stageActions;
@property (nonatomic, strong, nullable) id rawStage;
@property (nonatomic, strong, nullable) id account;
@property (nonatomic, strong, nullable) id accountActions;
@property (nonatomic, strong, nullable) id vehicleActions;
@property (nonatomic, copy, nullable) NSString *pendingVIN;
@end

@interface MCSDK ()
/// SPIN（车机安全码）：仅内存持有，不落盘。nil = 走低安全级路径。
@property (nonatomic, copy, nullable) NSString *spinCode;
@end

// Read only an exposed zero-argument getter, preserving its Objective-C return ABI.
// A non-object Swift enum/BOOL/double must never be returned through an id cast.
static inline id _Nullable MCSafeGet(id _Nullable obj, NSString * _Nonnull prop) {
    if (!obj) return nil;
    SEL sel=NSSelectorFromString(prop);
    Method method=class_getInstanceMethod(object_getClass(obj),sel);
    if (!method || method_getNumberOfArguments(method)!=2) return nil;
    char encoding[128]={0}; method_getReturnType(method,encoding,sizeof(encoding));
    const char *t=encoding; while (*t && strchr("rnNoORV",*t)) t++;
    switch (*t) {
        case '@': case '#': return ((id(*)(id,SEL))objc_msgSend)(obj,sel);
        case 'B': return @(((BOOL(*)(id,SEL))objc_msgSend)(obj,sel));
        case 'c': return @(((signed char(*)(id,SEL))objc_msgSend)(obj,sel));
        case 'C': return @(((unsigned char(*)(id,SEL))objc_msgSend)(obj,sel));
        case 's': return @(((short(*)(id,SEL))objc_msgSend)(obj,sel));
        case 'S': return @(((unsigned short(*)(id,SEL))objc_msgSend)(obj,sel));
        case 'i': return @(((int(*)(id,SEL))objc_msgSend)(obj,sel));
        case 'I': return @(((unsigned int(*)(id,SEL))objc_msgSend)(obj,sel));
        case 'l': return @(((long(*)(id,SEL))objc_msgSend)(obj,sel));
        case 'L': return @(((unsigned long(*)(id,SEL))objc_msgSend)(obj,sel));
        case 'q': return @(((long long(*)(id,SEL))objc_msgSend)(obj,sel));
        case 'Q': return @(((unsigned long long(*)(id,SEL))objc_msgSend)(obj,sel));
        case 'f': return @(((float(*)(id,SEL))objc_msgSend)(obj,sel));
        case 'd': return @(((double(*)(id,SEL))objc_msgSend)(obj,sel));
        default: return nil; // Structs, pointers, selectors and void require specific adapters.
    }
}
