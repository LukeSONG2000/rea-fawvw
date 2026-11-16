#import <Foundation/Foundation.h>
@interface MCReadonlyVerification : NSObject
+ (void)runWithProgress:(void (^)(NSString *))progress;
@end
