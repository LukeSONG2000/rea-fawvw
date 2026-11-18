#import "MCInformationViewController.h"
#import "MCUI.h"

typedef void (^MCInfoCompletion)(id,NSError *);
static NSDictionary *Entry(NSString *title,NSString *icon,NSString *query) {return @{@"title":title,@"icon":icon,@"query":query};}
static NSDictionary *Group(NSString *title,NSString *icon,NSArray *children) {return @{@"title":title,@"icon":icon,@"children":children};}
static NSDictionary *Field(NSString *title,id value) {return @{@"title":title,@"value":value?:NSNull.null};}
// 保留档案/权限 XML 的全部层级、叶子文字及属性，避免旧字段解析器遗漏无属性叶子。
@interface MCInfoXMLParser : NSObject <NSXMLParserDelegate>
@property(nonatomic,strong) NSMutableArray *stack;
@property(nonatomic,strong) NSMutableDictionary *root;
@end
@implementation MCInfoXMLParser
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified attributes:(NSDictionary *)attributes {
    NSMutableDictionary *node=[@{@"tag":element,@"attributes":attributes,@"children":[NSMutableArray array],@"text":[NSMutableString string]} mutableCopy];
    if(self.stack.count) [self.stack.lastObject[@"children"] addObject:node];else self.root=node;
    [self.stack addObject:node];
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)text {[self.stack.lastObject[@"text"] appendString:text];}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified {[self.stack removeLastObject];}
@end
static id XMLValue(NSDictionary *node) {
    NSMutableDictionary *value=[node[@"attributes"] mutableCopy];
    NSString *text=[node[@"text"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray *children=node[@"children"];
    if(!value.count && !children.count) return text;
    if(text.length) value[@"_text"]=text;
    for(NSDictionary *child in children) {
        NSString *tag=child[@"tag"];id v=XMLValue(child);
        if(!value[tag]) value[tag]=v;
        else if([value[tag] isKindOfClass:NSMutableArray.class]) [value[tag] addObject:v];
        else value[tag]=[NSMutableArray arrayWithObjects:value[tag],v,nil];
    }return value;
}
static id ParseInfoXML(NSString *xml) {
    MCInfoXMLParser *delegate=[MCInfoXMLParser new];delegate.stack=[NSMutableArray array];
    NSXMLParser *parser=[[NSXMLParser alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
    parser.delegate=delegate;parser.shouldProcessNamespaces=YES;parser.shouldResolveExternalEntities=NO;
    return [parser parse]?XMLValue(delegate.root):nil;
}
static NSDictionary *Signal(NSDictionary *f) {
    NSString *i=f[@"id"]?:@"",*text=f[@"textId"]?:@"",*raw=f[@"value"],*unit=f[@"unit"]?:@"";
    NSDictionary *titles=@{@"0x0101010001":@"总里程",@"0x0203010001":@"换油剩余里程",@"0x0203010002":@"换油剩余天数",@"0x0203010003":@"检查保养剩余里程",@"0x0203010004":@"检查保养剩余天数",@"0x0204040001":@"机油相关容量信号（含义待核对）",@"0x0301030004":@"车速",@"0x0301030006":@"燃油续航",@"0x030103000A":@"燃油余量",@"0x0301010001":@"驻车灯",@"0x0301030001":@"驻车制动"};
    NSString *title=titles[i];
    if(!title) {
        if([text isEqual:@"oil.level"]) title=@"机油液位百分比";
        else if([i hasPrefix:@"0x030104"]) title=[NSString stringWithFormat:@"门锁 / 车身信号 · %@",[i substringFromIndex:8]];
        else if([i hasPrefix:@"0x030105"]) title=[NSString stringWithFormat:@"车窗信号 · %@",[i substringFromIndex:8]];
        else if([text hasPrefix:@"warning."]) title=@"健康提醒信号";
        else title=[NSString stringWithFormat:@"其他信号 · %@",i];
    }
    NSDictionary *terms=@{@"door_locked":@"已锁定",@"door_unlocked":@"未锁定",@"door_closed":@"已关闭",@"door_open":@"已打开",@"window_closed":@"已关闭",@"window_open":@"已打开",@"window_unsupported":@"不支持",@"status_parking_light_off":@"已关闭",@"status_parking_light_on":@"已开启",@"parking_brake_active":@"已驻车",@"parking_brake_inactive":@"未驻车",@"engine_type_gasoline":@"汽油",@"engine_type_unsupported":@"不支持",@"not_supported":@"不支持"};
    NSString *display=raw.length?[NSString stringWithFormat:@"%@%@%@",raw,unit.length?@" ":@"",unit]:@"未提供";
    // door_unsafe 等尚未核实的枚举只展示代码，绝不当作当前告警。
    if(raw.length && terms[text]) display=terms[text];
    if([i hasPrefix:@"0x020301"] && raw.length) {
        NSString *u=([i hasSuffix:@"2"] || [i hasSuffix:@"4"])?@"天":@"km";
        display=[raw doubleValue]<0?[NSString stringWithFormat:@"已超出 %@ %@",@(-raw.doubleValue),u]:[NSString stringWithFormat:@"%@ %@",raw,u];
    }
    NSMutableDictionary *metadata=[f mutableCopy];[metadata removeObjectForKey:@"_element"];
    return @{@"title":title,@"subtitle":display,@"value":metadata,@"signal":@YES};
}

@interface MCInformationViewController ()
@property(nonatomic,strong) MCVehicleInfo *vehicle;
@property(nonatomic,copy) NSString *(^currentVIN)(void);
@property(nonatomic,strong) NSArray<NSDictionary *> *rows;
@property(nonatomic,copy) NSString *query;
@property(nonatomic,strong) id content;
@property(nonatomic,copy) NSString *context;
@property(nonatomic) BOOL loading;
@property(nonatomic) NSUInteger generation;
@end
@implementation MCInformationViewController
- (instancetype)initWithVehicle:(MCVehicleInfo *)vehicle currentVIN:(NSString *(^)(void))currentVIN {
    if((self=[super initWithStyle:UITableViewStyleInsetGrouped])) {
        self.vehicle=vehicle;self.currentVIN=currentVIN;self.title=@"车辆信息";
        self.context=[NSString stringWithFormat:@"%@ · 尾号 %@",MCVehicleName(vehicle.displayName),[vehicle.vin substringFromIndex:MAX(0,(NSInteger)vehicle.vin.length-6)]];
        self.rows=@[
            Group(@"车况与能耗",@"gauge.with.dots.needle.33percent",@[
                Entry(@"车况概览",@"car.side",@"vehicleStatus"),Entry(@"全部车况信号",@"list.bullet.rectangle",@"signals")]),
            Group(@"门窗与安全",@"lock.shield",@[
                Entry(@"门窗与车身状态",@"car.side.rear.open",@"body"),Entry(@"防盗通知",@"bell.badge",@"antiTheftNotifications"),Entry(@"车速提醒设置",@"speedometer",@"speedDefinitions"),Entry(@"车速提醒记录",@"clock",@"speedNotifications"),Entry(@"围栏设置",@"map",@"geofenceDefinitions"),Entry(@"围栏通知",@"bell",@"geofenceNotifications")]),
            Group(@"行程记录",@"point.topleft.down.to.point.bottomright.curvepath",@[
                Entry(@"短期行程",@"steeringwheel",@"tripsShortTerm"),Entry(@"长期统计",@"chart.bar",@"tripsLongTerm"),Entry(@"周期统计",@"calendar",@"tripsCyclic")]),
            Group(@"保养与健康",@"wrench.and.screwdriver",@[
                Entry(@"保养与机油",@"oilcan",@"maintenance"),Entry(@"健康提醒",@"heart.text.square",@"healthWarnings")]),
            Group(@"空调与充电",@"fan",@[
                Entry(@"空调状态",@"fan",@"climateStatus"),Entry(@"行前空调状态",@"thermometer.medium",@"pretripClimateStatus"),Entry(@"辅助加热状态",@"heat.waves",@"auxiliaryHeatingStatus"),Entry(@"出发计划",@"calendar.badge.clock",@"departureConfiguration"),Entry(@"空调定时与档位",@"timer",@"profileTimers"),Entry(@"远程空调定时",@"clock",@"remoteProfileTimer"),Entry(@"充电状态",@"bolt.car",@"chargerStatus"),Entry(@"充电详情",@"bolt.circle",@"chargerStatusV2")]),
            Group(@"位置与寻车",@"location",@[
                Entry(@"车辆位置",@"mappin.and.ellipse",@"location"),Entry(@"鸣笛与闪灯配置",@"light.beacon.max",@"honkFlashConfiguration")]),
            Group(@"车辆档案",@"car.front.waves.up",@[
                Entry(@"车型与配置",@"car.side",@"profile"),Entry(@"全部档案字段",@"doc.text",@"rawVehicleData")]),
            Group(@"服务与设备",@"key.horizontal",@[
                Entry(@"已开通能力",@"checkmark.seal",@"features"),Entry(@"服务权限",@"person.badge.key",@"rights"),Entry(@"车辆用户",@"person.2",@"vehicleUsers"),Entry(@"手机配对状态",@"iphone",@"pairingStatus"),Entry(@"最近配对结果",@"key",@"pairingLastStatus"),Entry(@"发动机操作记录",@"clock.arrow.circlepath",@"engineHistory"),Entry(@"最近发动机操作结果",@"engine.combustion",@"enginePairStatus")])];
    }return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=MCPaper();self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=64;
    self.tableView.tintColor=MCAccent();
    UILabel *header=[UILabel new];header.text=self.context;header.font=MCFont(14,UIFontWeightRegular);header.textColor=UIColor.secondaryLabelColor;header.numberOfLines=0;header.frame=CGRectMake(20,0,300,52);header.textAlignment=NSTextAlignmentCenter;self.tableView.tableHeaderView=header;
    if(self.query) {self.refreshControl=[UIRefreshControl new];[self.refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];[self fetch];}
}
- (void)refresh { MCHapticPress();[self fetch]; }
- (void)viewWillDisappear:(BOOL)animated {[super viewWillDisappear:animated];if(self.isMovingFromParentViewController) MCHapticSelect();}
- (BOOL)vehicleIsCurrent {return !self.currentVIN || [self.currentVIN() isEqual:self.vehicle.vin];}
- (void)finish:(id)value error:(NSError *)error token:(NSUInteger)token {
    if(token!=self.generation) return;
    self.loading=NO;[self.refreshControl endRefreshing];
    if(![self vehicleIsCurrent]) {self.rows=@[Field(@"车辆已切换",@"请返回主页，重新打开当前车辆的信息")];}
    else if(error) {self.rows=@[Field(@"暂时无法读取",error.localizedDescription)];MCHapticResult(NO);}
    else {self.content=value;[self buildRows:value];}
    [self.tableView reloadData];
}
- (void)fetch {
    if(![self vehicleIsCurrent]) {[self finish:nil error:nil token:self.generation];return;}
    if(self.loading) {[self.refreshControl endRefreshing];return;}
    self.loading=YES;NSUInteger token=++self.generation;
    if(!self.content) {self.rows=@[Field(@"正在读取",@"请稍候…")];[self.tableView reloadData];}
    NSString *q=self.query;
    if([q isEqual:@"profile"]) {
        MCVehicleInfo *v=self.vehicle;
        [self finish:@{@"modelName":v.modelName?:@"",@"modelYear":v.modelYear?:@"",@"vin":v.vin?:@"",@"engine":v.engine?:@"",@"transmission":v.transmission?:@"",@"color":v.color?:@"",@"mmi":v.mmi?:@"",@"modelCode":v.modelCode?:@"",@"countryCode":v.countryCode?:@"",@"brand":v.brand?:@""} error:nil token:token];return;
    }
    if([q isEqual:@"features"]) {
        NSMutableArray *rows=[NSMutableArray array];for(NSString *f in self.vehicle.features) [rows addObject:Field([MCSDK featureDescriptions][f]?:MCFriendlyName(f),@"已开通")];
        self.loading=NO;self.rows=rows.count?rows:@[Field(@"服务能力",@"未提供已开通能力")];[self.refreshControl endRefreshing];[self.tableView reloadData];return;
    }
    if([q isEqual:@"location"]) {
        // 已证实原生 MOSC 可定位，但独立客户端尚未接入认证和签名，不显示旧的 MBB 失败结论。
        self.loading=NO;self.rows=@[Field(@"车辆位置",@"位置查询尚未接入此客户端"),Field(@"位置与地名",@"接入后分别显示经纬度、位置采集时间和地址；地址解析失败时仍保留坐标")];[self.refreshControl endRefreshing];[self.tableView reloadData];return;
    }
    if([@[@"signals",@"body",@"maintenance"] containsObject:q]) {
        [[MCSDK shared] rawStatusReportForVIN:self.vehicle.vin completion:^(NSString *xml,NSError *error){
            NSArray *fields=error?nil:[[[MCSDK shared] parseRawXML:xml] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"_element == 'field'"]];
            NSMutableArray *rows=[NSMutableArray array];
            for(NSDictionary *f in fields) {
                NSString *i=f[@"id"]?:@"";
                if([q isEqual:@"body"] && !([i hasPrefix:@"0x030104"] || [i hasPrefix:@"0x030105"] || [i isEqual:@"0x0301010001"] || [i isEqual:@"0x0301030001"])) continue;
                if([q isEqual:@"maintenance"] && ![i hasPrefix:@"0x0203"] && ![i hasPrefix:@"0x0204"]) continue;
                [rows addObject:Signal(f)];
            }
            if(token!=self.generation) return;
            if(error || ![self vehicleIsCurrent]) {[self finish:nil error:error token:token];return;}
            NSMutableDictionary *groups=[NSMutableDictionary dictionary];NSMutableArray *order=[NSMutableArray array];
            for(NSDictionary *row in rows) {
                NSString *i=row[@"value"][@"id"]?:@"";
                NSString *group=[i hasPrefix:@"0x030104"]?@"门锁与车身":([i hasPrefix:@"0x030105"]?@"车窗与天窗":([i hasPrefix:@"0x0203"]?@"保养周期":([i hasPrefix:@"0x0204"]?@"机油与提醒":@"里程、能耗与其他状态")));
                if(!groups[group]) {groups[group]=[NSMutableArray array];[order addObject:group];}[groups[group] addObject:row];
            }
            NSMutableArray *groupRows=[NSMutableArray array];for(NSString *name in order) [groupRows addObject:Group(name,@"list.bullet",groups[name])];
            self.loading=NO;self.content=rows;self.rows=groupRows.count?groupRows:@[Field(@"暂无数据",@"车辆尚未提供此类信号")];[self.refreshControl endRefreshing];[self.tableView reloadData];
        }];return;
    }
    if([q isEqual:@"rawVehicleData"] || [q isEqual:@"rights"]) {
        void (^receive)(NSString *,NSError *)=^(NSString *xml,NSError *error){
            id fields=error?nil:ParseInfoXML(xml);[self finish:fields error:error token:token];
        };
        if([q isEqual:@"rights"]) [[MCSDK shared] rawOperationListForVIN:self.vehicle.vin completion:receive];
        else [[MCSDK shared] rawVehicleDataForVIN:self.vehicle.vin completion:receive];return;
    }
    [[MCSDK shared] informationForKey:q completion:^(id value,NSError *error){[self finish:value error:error token:token];}];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(self.loading && self.generation==token) {self.generation++;self.loading=NO;[self.refreshControl endRefreshing];self.rows=@[Field(@"读取超时",@"下拉刷新后重试")];[self.tableView reloadData];MCHapticResult(NO);}
    });
}
- (void)buildRows:(id)value {
    NSMutableArray *rows=[NSMutableArray array];
    if([value isKindOfClass:NSArray.class]) {
        if([self.query hasPrefix:@"trips"]) value=[value sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"tripEnd"] compare:a[@"tripEnd"]];}];
        NSUInteger idx=0;for(id item in value) {
            idx++;NSString *title=[NSString stringWithFormat:@"记录 %lu",(unsigned long)idx];NSString *sub=@"";
            if([item isKindOfClass:NSDictionary.class]) {
                if(item[@"tripEnd"]) {title=MCFriendlyValue(item[@"tripEnd"],@"tripEnd");sub=[NSString stringWithFormat:@"%@ · %@",MCFriendlyValue(item[@"mileage"],@"mileage"),MCFriendlyValue(item[@"travelTime"],@"travelTime")];}
                else if(item[@"serviceId"]) title=item[@"serviceId"];
                else if(item[@"operationId"]) title=item[@"operationId"];
                else if(item[@"name"]) title=item[@"name"];
                else if(item[@"_element"]) title=MCFriendlyName(item[@"_element"]);
            }
            [rows addObject:@{@"title":title,@"subtitle":sub,@"value":item?:NSNull.null}];
        }
    } else if([value isKindOfClass:NSDictionary.class]) {
        NSArray *priority=@[@"timestamp",@"mileage",@"fuelLevel",@"primaryEngineRange",@"bodyStatus",@"nextServiceInKm",@"nextServiceInDays",@"nextOilServiceInKm",@"nextOilServiceInDays"];
        NSArray *keys=[[value allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){
            NSUInteger ai=[priority indexOfObject:a],bi=[priority indexOfObject:b];if(ai!=bi) return ai<bi?NSOrderedAscending:NSOrderedDescending;return [a compare:b];
        }];
        for(NSString *key in keys) if(![key hasPrefix:@"_"]) {
            id val=value[key];[rows addObject:@{@"title":MCFriendlyName(key),@"key":key,@"value":val?:NSNull.null}];
        }
    } else if(value && value!=NSNull.null) [rows addObject:Field(@"查询结果",value)];
    if(!rows.count) [rows addObject:Field(@"暂无记录",@"车辆或服务当前未返回记录")];
    self.rows=rows;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return self.rows.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSDictionary *row=self.rows[indexPath.row];id value=row[@"value"];
    BOOL nested=[value isKindOfClass:NSArray.class] || [value isKindOfClass:NSDictionary.class];
    BOOL navigation=row[@"children"] || row[@"query"] || nested;
    cell.textLabel.text=row[@"title"];cell.textLabel.font=MCFont(16,UIFontWeightMedium);cell.textLabel.numberOfLines=0;
    cell.detailTextLabel.font=MCFont(14,UIFontWeightRegular);cell.detailTextLabel.numberOfLines=0;cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    cell.detailTextLabel.text=row[@"subtitle"]?: (value?MCFriendlyValue(value,row[@"key"]?:@""):@"");
    if(row[@"icon"]) {cell.imageView.image=[UIImage systemImageNamed:row[@"icon"]];cell.imageView.tintColor=MCInk();}
    cell.accessoryType=navigation?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone;
    cell.selectionStyle=navigation?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];NSDictionary *row=self.rows[indexPath.row];id value=row[@"value"];
    if(!row[@"children"] && !row[@"query"] && ![value isKindOfClass:NSArray.class] && ![value isKindOfClass:NSDictionary.class]) return;
    MCHapticSelect();MCInformationViewController *next=[[MCInformationViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    next.vehicle=self.vehicle;next.currentVIN=self.currentVIN;next.title=row[@"title"];next.context=self.context;
    if(row[@"children"]) next.rows=row[@"children"];
    else if(row[@"query"]) next.query=row[@"query"];
    else {next.content=value;[next buildRows:value];}
    [self.navigationController pushViewController:next animated:YES];
}
@end
