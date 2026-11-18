#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/stat.h>
#import <CoreLocation/CoreLocation.h>
static NSMutableArray *Events;
static IMP TaskWithHandler,TaskOnly;
static BOOL LocatorOpened;
static void AttachGNSSMetrics(NSURLSessionDataTask *task);
static const void *TraceKey=&TraceKey;
static NSMapTable *Buffers;
static NSString *Directory(void) {
    NSString *p=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/GTILocationProbe"];
    [NSFileManager.defaultManager createDirectoryAtPath:p withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]; return p;
}
static void Save(NSDictionary *entry) {
    @synchronized(Events) {
        [Events addObject:entry];
        NSData *d=[NSJSONSerialization dataWithJSONObject:Events options:0 error:nil];
        NSString *p=[Directory() stringByAppendingPathComponent:@"events.json"];
        [d writeToFile:p options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil]; chmod(p.fileSystemRepresentation,0600);
    }
}
static BOOL Interesting(NSURL *u) {
    NSString *h=u.host.lowercaseString;
    return [h hasSuffix:@"faw-vw.com"] || [h hasSuffix:@"vwg-connect.cn"] || [h containsString:@"mosc"] || [h hasSuffix:@"amap.com"] || [h hasSuffix:@"autonavi.com"];
}
static NSURLRequest *DiagnosticRequest(NSURLRequest *req) {
    BOOL readPOST=[req.URL.path containsString:@"getLastGnss"] || [req.URL.path containsString:@"geocode/regeo"];
    if(!Interesting(req.URL) || (![req.HTTPMethod isEqualToString:@"GET"] && !readPOST)) return req;
    NSMutableURLRequest *copy=[req mutableCopy];
    copy.cachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
    return copy; // URL, nonce, signature and auth headers remain byte-for-byte unchanged.
}
static NSString *Request(NSURLRequest *req) {
    NSString *key=NSUUID.UUID.UUIDString;
    NSMutableDictionary *event=[@{@"event":@"request",@"key":key,@"url":req.URL.absoluteString?:@"",@"method":req.HTTPMethod?:@""} mutableCopy];
    event[@"headerNames"]=[req.allHTTPHeaderFields.allKeys sortedArrayUsingSelector:@selector(compare:)];
    event[@"cachePolicy"]=@(req.cachePolicy);
    event[@"time"]=@([NSDate.date timeIntervalSince1970]);
    if(req.HTTPBody.length) {
        NSString *file=[key stringByAppendingString:@"-request.bin"];
        NSString *path=[Directory() stringByAppendingPathComponent:file];
        [req.HTTPBody writeToFile:path options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil]; chmod(path.fileSystemRepresentation,0600); event[@"bodyFile"]=file;
    }
    Save(event); return key;
}
static id WithHandler(id self,SEL sel,NSURLRequest *req,id handler) {
    req=DiagnosticRequest(req);
    if(!Interesting(req.URL) || !handler) return ((id(*)(id,SEL,id,id))TaskWithHandler)(self,sel,req,handler);
    NSString *key=[Request(req) copy];
    void (^original)(NSData *,NSURLResponse *,NSError *)=[handler copy];
    void (^wrapped)(NSData *,NSURLResponse *,NSError *)=^(NSData *data,NSURLResponse *response,NSError *error){
        NSString *file=[key stringByAppendingString:@"-response.bin"];
        if(data) { NSString *p=[Directory() stringByAppendingPathComponent:file]; [data writeToFile:p options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil]; chmod(p.fileSystemRepresentation,0600); }
        Save(@{@"event":@"response",@"key":key,@"status":@([response isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse *)response statusCode]:0),@"bodyFile":file,@"bytes":@(data.length),@"error":error.localizedDescription?:@""});
        original(data,response,error);
    };
    NSURLSessionDataTask *task=((id(*)(id,SEL,id,id))TaskWithHandler)(self,sel,req,wrapped);
    objc_setAssociatedObject(task,TraceKey,key,OBJC_ASSOCIATION_COPY_NONATOMIC);
    if([req.URL.path hasSuffix:@"/getLastGnss"]) AttachGNSSMetrics(task);
    return task;
}
static id WithoutHandler(id self,SEL sel,NSURLRequest *req) {
    req=DiagnosticRequest(req);
    NSString *key=Interesting(req.URL)?Request(req):nil;
    if(key) Save(@{@"event":@"session-delegate",@"key":key,@"class":NSStringFromClass([[(NSURLSession *)self delegate] class])?:@"<nil>"});
    id task=((id(*)(id,SEL,id))TaskOnly)(self,sel,req);
    if(key) objc_setAssociatedObject(task,TraceKey,key,OBJC_ASSOCIATION_COPY_NONATOMIC);
    return task;
}
static void CaptureDelegateData(NSURLSessionTask *task,NSData *data,BOOL complete,NSError *error) {
    NSURLRequest *req=task.originalRequest;
    if(!Interesting(req.URL)) return;
    NSString *key=objc_getAssociatedObject(task,TraceKey);
    if(!key) { key=Request(req); objc_setAssociatedObject(task,TraceKey,key,OBJC_ASSOCIATION_COPY_NONATOMIC); }
    @synchronized(Buffers) {
        NSMutableData *buffer=[Buffers objectForKey:task];
        if(!buffer) { buffer=[NSMutableData data]; [Buffers setObject:buffer forKey:task]; }
        if(data) [buffer appendData:data];
        NSString *file=[key stringByAppendingString:@"-response.bin"];
        NSString *path=[Directory() stringByAppendingPathComponent:file];
        [buffer writeToFile:path options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil]; chmod(path.fileSystemRepresentation,0600);
        NSInteger status=[task.response isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse *)task.response statusCode]:0;
        Save(@{@"event":complete?@"delegate-complete":@"delegate-data",@"key":key,@"status":@(status),@"bytes":@(buffer.length),@"bodyFile":file,@"error":error.localizedDescription?:@""});
        if(complete) [Buffers removeObjectForKey:task];
    }
}
static void RecordMetrics(NSURLSessionTask *task,NSURLSessionTaskMetrics *metrics) {
    if(!Interesting(task.originalRequest.URL)) return;
    NSString *key=objc_getAssociatedObject(task,TraceKey)?:@"<completion-handler>";
    NSMutableArray *rows=[NSMutableArray array];
    for(NSURLSessionTaskTransactionMetrics *t in metrics.transactionMetrics) {
        NSMutableDictionary *row=[@{@"networkLoad":@(t.resourceFetchType==NSURLSessionTaskMetricsResourceFetchTypeNetworkLoad),@"localCache":@(t.resourceFetchType==NSURLSessionTaskMetricsResourceFetchTypeLocalCache),@"type":@(t.resourceFetchType),@"url":t.request.URL.absoluteString?:@""} mutableCopy];
        if(t.responseEndDate) row[@"responseEnd"]=@([t.responseEndDate timeIntervalSince1970]);
        if([t.response isKindOfClass:NSHTTPURLResponse.class]) {
            NSDictionary *headers=[(NSHTTPURLResponse *)t.response allHeaderFields]; NSMutableDictionary *selected=[NSMutableDictionary dictionary];
            for(id k in headers) if([@[@"date",@"age",@"cache-control",@"expires",@"x-cache"] containsObject:[(NSString *)k lowercaseString]]) selected[k]=[headers[k] description];
            row[@"cacheHeaders"]=selected;
        }
        [rows addObject:row];
    }
    Save(@{@"event":@"network-metrics",@"key":key,@"transactions":rows});
}
@interface GTINetworkVerifier : NSObject <NSURLSessionTaskDelegate>
@end
@implementation GTINetworkVerifier
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics {
    RecordMetrics(task,metrics);
}
@end
static void AttachGNSSMetrics(NSURLSessionDataTask *task) {
    // 原生请求仅增加指标观察；不复制请求，不改变原会话及鉴权。
    if(!task.delegate) {
        task.delegate=[GTINetworkVerifier new];
        Save(@{@"event":@"gnss-task-metrics-attached",@"key":objc_getAssociatedObject(task,TraceKey)?:@""});
    } else Save(@{@"event":@"gnss-task-existing-delegate",@"class":NSStringFromClass([task.delegate class])});
}
static IMP MapAnnotation;
static id HookAnnotation(id self,SEL sel,id map,id annotation) {
    id view=((id(*)(id,SEL,id,id))MapAnnotation)(self,sel,map,annotation);
    NSString *type=NSStringFromClass([view class]);
    if([type containsString:@"VehicleAnnotation"] && [annotation respondsToSelector:@selector(coordinate)]) {
        CLLocationCoordinate2D c=((CLLocationCoordinate2D(*)(id,SEL))objc_msgSend)(annotation,@selector(coordinate));
        Save(@{@"event":@"vehicle-marker",@"latitude":@(c.latitude),@"longitude":@(c.longitude),@"viewClass":type,@"time":@([NSDate.date timeIntervalSince1970])});
    }
    return view;
}
static NSUInteger HookDelegates(void) {
    NSArray *names=@[@"_TtC9Alamofire15SessionDelegate",@"AMapNetworkSessionManager"]; NSUInteger installed=0;
    SEL dataSelector=@selector(URLSession:dataTask:didReceiveData:),doneSelector=@selector(URLSession:task:didCompleteWithError:);
    for(NSString *name in names) {
        Class c=NSClassFromString(name); if(!c) continue;
        Class parent=class_getSuperclass(c);
        Method m=class_getInstanceMethod(c,dataSelector);
        if(m && (!parent || m!=class_getInstanceMethod(parent,dataSelector))) {
            IMP original=method_getImplementation(m);
            IMP hook=imp_implementationWithBlock(^(id delegate,NSURLSession *session,NSURLSessionDataTask *task,NSData *data){
                CaptureDelegateData(task,data,NO,nil);
                ((void(*)(id,SEL,id,id,id))original)(delegate,dataSelector,session,task,data);
            });
            method_setImplementation(m,hook); installed++;
        }
        SEL metricSelector=@selector(URLSession:task:didFinishCollectingMetrics:);
        Method metric=class_getInstanceMethod(c,metricSelector);
        if(metric && (!parent || metric!=class_getInstanceMethod(parent,metricSelector))) {
            IMP original=method_getImplementation(metric);
            IMP hook=imp_implementationWithBlock(^(id delegate,NSURLSession *session,NSURLSessionTask *task,NSURLSessionTaskMetrics *metrics){
                RecordMetrics(task,metrics);
                ((void(*)(id,SEL,id,id,id))original)(delegate,metricSelector,session,task,metrics);
            });
            method_setImplementation(metric,hook); installed++;
        }
        m=class_getInstanceMethod(c,doneSelector);
        if(m && (!parent || m!=class_getInstanceMethod(parent,doneSelector))) {
            IMP original=method_getImplementation(m);
            IMP hook=imp_implementationWithBlock(^(id delegate,NSURLSession *session,NSURLSessionTask *task,NSError *error){
                CaptureDelegateData(task,nil,YES,error);
                ((void(*)(id,SEL,id,id,id))original)(delegate,doneSelector,session,task,error);
            });
            method_setImplementation(m,hook); installed++;
        }
    }
    return installed;
}
static void Visit(UIView *v,void(^block)(UIView *)) { block(v); for(UIView *child in v.subviews.copy) Visit(child,block); }
static void OpenLocator(void) {
    if(LocatorOpened) return;
    __block BOOL gti=NO; __block UILabel *target=nil;
    for(UIWindow *w in UIApplication.sharedApplication.windows) if(!w.hidden) Visit(w,^(UIView *v){
        if(![v isKindOfClass:UILabel.class]) return;
        UILabel *l=(UILabel *)v;
        if([l.text containsString:@"GTI"]) gti=YES;
        if([l.text isEqualToString:@"在线寻车"]) target=l;
    });
    if(!gti || !target) { Save(@{@"event":@"locator-entry-not-ready",@"gtiVisible":@(gti),@"entryFound":@(target!=nil)}); return; }
    UIView *v=target; UICollectionViewCell *cell=nil;
    while(v) { if([v isKindOfClass:UIButton.class]) { LocatorOpened=YES; [(UIButton *)v sendActionsForControlEvents:UIControlEventTouchUpInside]; Save(@{@"event":@"locator-opened-button"}); return; } if([v isKindOfClass:UICollectionViewCell.class]) { cell=(id)v; break; } v=v.superview; }
    v=cell.superview; while(v && ![v isKindOfClass:UICollectionView.class]) v=v.superview;
    UICollectionView *c=(id)v; NSIndexPath *path=[c indexPathForCell:cell];
    if(path && [c.delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
        LocatorOpened=YES; [c.delegate collectionView:c didSelectItemAtIndexPath:path]; Save(@{@"event":@"locator-opened-cell"});
    } else Save(@{@"event":@"locator-entry-no-native-action"});
}
__attribute__((constructor)) static void Install(void) {
    Events=[NSMutableArray array]; Buffers=[NSMapTable weakToStrongObjectsMapTable]; Save(@{@"event":@"installed",@"physicalCommandsSent":@NO});
    Method m=class_getInstanceMethod(NSURLSession.class,@selector(dataTaskWithRequest:completionHandler:)); TaskWithHandler=method_setImplementation(m,(IMP)WithHandler);
    m=class_getInstanceMethod(NSURLSession.class,@selector(dataTaskWithRequest:)); TaskOnly=method_setImplementation(m,(IMP)WithoutHandler);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        Save(@{@"event":@"delegate-hooks-installed",@"count":@(HookDelegates())});
        Class c=NSClassFromString(@"_TtC8VWCarnet33MoscCarnetCarFinderViewController");
        Method m=class_getInstanceMethod(c,@selector(mapView:viewForAnnotation:));
        if(m) MapAnnotation=method_setImplementation(m,(IMP)HookAnnotation);
    });
    for(NSNumber *seconds in @[@15,@30,@45]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,seconds.longLongValue*NSEC_PER_SEC),dispatch_get_main_queue(),^{OpenLocator();});
}
