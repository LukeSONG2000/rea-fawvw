#import <Foundation/Foundation.h>
@interface MCCapabilitySurvey : NSObject
+ (void)runWithProgress:(void (^)(NSString *))progress;
@end
