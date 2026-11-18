#import <Foundation/Foundation.h>
#define MCSDK MCSDKFixture
#import "../src/MCSDKRawData.m"
@implementation MCSDKFixture
@end
int main(void) { @autoreleasepool {
    NSString *xml=@"<report xmlns:a='urn:test'><field id='fuel' tsCarSentUtc='2026-11-17T00:00:00Z'><value>90</value><unit>%</unit><textId>fuel_level_ok</textId></field><field id='unknown'><value/></field><a:operation a:id='LOCK'/></report>";
    NSArray *fields=[[MCSDKFixture new] parseRawXML:xml];
    NSCAssert(fields.count==3,@"Expected both signal fields and permission operation");
    NSCAssert([fields[0][@"value"] isEqual:@"90"] && [fields[0][@"unit"] isEqual:@"%"],@"Signal values and units must survive parsing");
    NSCAssert([fields[0][@"textId"] isEqual:@"fuel_level_ok"],@"Signal meaning must survive parsing");
    NSCAssert(fields[1][@"value"]==nil,@"Empty measurements must not become zero");
    NSCAssert([fields[2][@"id"] isEqual:@"LOCK"],@"Namespace-qualified permission IDs must be normalized");
    puts("Raw XML signal and namespace tests passed");
}}
