// MCKeychainForensics.m
#import "MCKeychainForensics.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>

static NSString *SHA256Prefix(NSData *data) {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < 4; i++) [s appendFormat:@"%02x", hash[i]];
    return s;
}

@implementation MCKeychainForensics

+ (NSArray<NSDictionary *> *)dumpGenericPasswordSummary {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccessGroup: @"KC9H2N4239.com.fawvw.aftermarket",
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
        (__bridge id)kSecReturnAttributes: @YES,
        (__bridge id)kSecReturnData: @YES,
    };
    CFTypeRef out = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)query, &out);
    if (st != errSecSuccess) {
        NSLog(@"[MCKeychain] 枚举失败 status=%d（组未授权或空）", (int)st);
        return @[];
    }
    NSArray *items = CFBridgingRelease(out);
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *item in items) {
        NSData *value = item[(__bridge id)kSecValueData];
        NSDictionary *summary = @{
            @"service": item[(__bridge id)kSecAttrService] ?: @"<nil>",
            @"account": item[(__bridge id)kSecAttrAccount] ?: @"<nil>",
            @"group": item[(__bridge id)kSecAttrAccessGroup] ?: @"<nil>",
            @"bytes": @(value.length),
            @"sha256-8": value ? SHA256Prefix(value) : @"<nil>",
        };
        [list addObject:summary];
        NSLog(@"[MCKeychain] %@ | %@ | %@ | %luB | %@",
              summary[@"service"], summary[@"account"], summary[@"group"],
              (unsigned long)value.length, summary[@"sha256-8"]);
    }
    NSLog(@"[MCKeychain] 共 %lu 条", (unsigned long)list.count);
    return list;
}

+ (void)findIdentityTokenCandidates {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccessGroup: @"KC9H2N4239.com.fawvw.aftermarket",
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
        (__bridge id)kSecReturnAttributes: @YES,
        (__bridge id)kSecReturnData: @YES,
    };
    CFTypeRef out = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &out) != errSecSuccess) return;
    NSArray *items = CFBridgingRelease(out);
    NSUInteger found = 0;
    for (NSDictionary *item in items) {
        NSData *value = item[(__bridge id)kSecValueData];
        if (value.length < 200) continue;
        NSString *s = [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
        if (!s) continue;
        NSArray *parts = [s componentsSeparatedByString:@"."];
        if (parts.count != 3) continue;
        // JWT 候选：只输出位置与 typ 声明，不输出本体
        found++;
        NSLog(@"[MCKeychain] JWT 候选: service=%@ account=%@ group=%@ len=%lu",
              item[(__bridge id)kSecAttrService], item[(__bridge id)kSecAttrAccount],
              item[(__bridge id)kSecAttrAccessGroup], (unsigned long)s.length);
        NSRange r = [s rangeOfString:@"\"typ\":\"identity\""];
        if (r.length) NSLog(@"[MCKeychain]   ↳ typ=identity ✅（identity token 实锤）");
    }
    if (!found) NSLog(@"[MCKeychain] 无 JWT 形态候选（identity token 可能不在 GenericPassword）");
}

@end
