#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <ifaddrs.h>
#import <net/if.h>

// ===== ГЛОБАЛЬНЫЕ =====
static int serverSocket = -1;
static BOOL serverRunning = NO;
static NSMutableString *logText = nil;
static UITextView *logView = nil;
static UIWindow *win = nil;

void addLog(NSString *msg) {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendString:msg];
    [logText appendString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (logView) logView.text = logText;
        NSLog(@"[SERVER] %@", msg);
    });
}

NSString* getIPAddress(void) {
    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    
    success = getifaddrs(&interfaces);
    if (success == 0) {
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address;
}

// ===== БЕЗОПАСНОЕ ЧТЕНИЕ ПАМЯТИ =====
int safeReadInt(uintptr_t addr) {
    if (addr == 0) return 0;
    int val = 0;
    vm_size_t read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, &read);
    if (kr != KERN_SUCCESS || read != 4) return 0;
    return val;
}

uintptr_t safeReadPtr(uintptr_t addr) {
    if (addr == 0) return 0;
    uintptr_t val = 0;
    vm_size_t read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, 8, (vm_address_t)&val, &read);
    if (kr != KERN_SUCCESS || read != 8) return 0;
    return val;
}

float safeReadFloat(uintptr_t addr) {
    if (addr == 0) return 0;
    float val = 0;
    vm_size_t read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, &read);
    if (kr != KERN_SUCCESS || read != 4) return 0;
    return val;
}

uint8_t safeReadByte(uintptr_t addr) {
    if (addr == 0) return 0;
    uint8_t val = 0;
    vm_size_t read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, 1, (vm_address_t)&val, &read);
    if (kr != KERN_SUCCESS || read != 1) return 0;
    return val;
}

uint16_t safeReadShort(uintptr_t addr) {
    if (addr == 0) return 0;
    uint16_t val = 0;
    vm_size_t read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, 2, (vm_address_t)&val, &read);
    if (kr != KERN_SUCCESS || read != 2) return 0;
    return val;
}

NSString* safeReadString(uintptr_t addr, int maxLen) {
    if (addr == 0) return @"";
    char buffer[256];
    vm_size_t read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, maxLen, (vm_address_t)buffer, &read);
    if (kr != KERN_SUCCESS) return @"";
    return [NSString stringWithUTF8String:buffer];
}

// ===== ЗАПИСЬ ПАМЯТИ =====
BOOL safeWriteInt(uintptr_t addr, int val) {
    kern_return_t kr = vm_write(mach_task_self(), addr, (vm_address_t)&val, 4);
    return kr == KERN_SUCCESS;
}

BOOL safeWriteFloat(uintptr_t addr, float val) {
    kern_return_t kr = vm_write(mach_task_self(), addr, (vm_address_t)&val, 4);
    return kr == KERN_SUCCESS;
}

BOOL safeWritePtr(uintptr_t addr, uintptr_t val) {
    kern_return_t kr = vm_write(mach_task_self(), addr, (vm_address_t)&val, 8);
    return kr == KERN_SUCCESS;
}

BOOL safeWriteByte(uintptr_t addr, uint8_t val) {
    kern_return_t kr = vm_write(mach_task_self(), addr, (vm_address_t)&val, 1);
    return kr == KERN_SUCCESS;
}

// ===== СКАНИРОВАНИЕ ПАМЯТИ =====
NSArray* scanInt(int targetValue, int maxResults) {
    NSMutableArray *results = [NSMutableArray array];
    task_t task = mach_task_self();
    vm_address_t addr = 0;
    vm_size_t size = 0;
    struct vm_region_basic_info_64 info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name = MACH_PORT_NULL;
    uint8_t *buffer = malloc(0x10000);
    
    if (!buffer) return results;
    
    while (1) {
        kern_return_t kr = vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;
        
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE) &&
            addr >= 0x100000000 && addr <= 0x300000000) {
            
            for (uintptr_t page = addr; page < addr + size; page += 0x10000) {
                uintptr_t pageSize = (page + 0x10000 > addr + size) ? (addr + size - page) : 0x10000;
                if (pageSize < 4) continue;
                
                vm_size_t read = 0;
                kr = vm_read_overwrite(task, page, pageSize, (vm_address_t)buffer, &read);
                if (kr != KERN_SUCCESS || read < 4) continue;
                
                for (uintptr_t offset = 0; offset + 4 <= pageSize; offset += 4) {
                    int val = *(int*)(buffer + offset);
                    if (val == targetValue) {
                        [results addObject:@(page + offset)];
                        if (results.count >= maxResults) {
                            free(buffer);
                            return results;
                        }
                    }
                }
            }
        }
        addr += size;
        if (addr > 0x300000000) break;
    }
    free(buffer);
    return results;
}

NSArray* scanFloat(float targetValue, float tolerance, int maxResults) {
    NSMutableArray *results = [NSMutableArray array];
    task_t task = mach_task_self();
    vm_address_t addr = 0;
    vm_size_t size = 0;
    struct vm_region_basic_info_64 info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name = MACH_PORT_NULL;
    uint8_t *buffer = malloc(0x10000);
    
    if (!buffer) return results;
    
    while (1) {
        kern_return_t kr = vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;
        
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE) &&
            addr >= 0x100000000 && addr <= 0x300000000) {
            
            for (uintptr_t page = addr; page < addr + size; page += 0x10000) {
                uintptr_t pageSize = (page + 0x10000 > addr + size) ? (addr + size - page) : 0x10000;
                if (pageSize < 4) continue;
                
                vm_size_t read = 0;
                kr = vm_read_overwrite(task, page, pageSize, (vm_address_t)buffer, &read);
                if (kr != KERN_SUCCESS || read < 4) continue;
                
                for (uintptr_t offset = 0; offset + 4 <= pageSize; offset += 4) {
                    float val = *(float*)(buffer + offset);
                    if (fabs(val - targetValue) <= tolerance) {
                        [results addObject:@(page + offset)];
                        if (results.count >= maxResults) {
                            free(buffer);
                            return results;
                        }
                    }
                }
            }
        }
        addr += size;
        if (addr > 0x300000000) break;
    }
    free(buffer);
    return results;
}

NSData* memoryDump(uintptr_t addr, int size) {
    if (size > 1024 * 1024) size = 1024 * 1024;
    uint8_t *buffer = malloc(size);
    if (!buffer) {
        addLog(@"❌ malloc failed");
        return nil;
    }
    
    vm_size_t read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, size, (vm_address_t)buffer, &read);
    
    if (kr != KERN_SUCCESS) {
        addLog([NSString stringWithFormat:@"❌ vm_read_overwrite error: %d", kr]);
        free(buffer);
        return nil;
    }
    
    NSData *data = [NSData dataWithBytes:buffer length:read];
    free(buffer);
    return data;
}

// ===== ОБРАБОТКА КОМАНД =====
NSString* handleCommand(NSString *cmd) {
    NSArray *parts = [cmd componentsSeparatedByString:@" "];
    NSString *command = [parts[0] uppercaseString];
    
    if ([command isEqualToString:@"PING"]) {
        return @"PONG";
    }
    else if ([command isEqualToString:@"SCAN_INT"]) {
        if (parts.count < 2) return @"ERROR: need value";
        int value = [parts[1] intValue];
        int max = (parts.count > 2) ? [parts[2] intValue] : 500;
        NSArray *results = scanInt(value, max);
        NSMutableString *response = [NSMutableString stringWithFormat:@"RESULTS %lu", (unsigned long)results.count];
        for (NSNumber *addr in results) {
            [response appendFormat:@"\n0x%lx", [addr unsignedLongValue]];
        }
        return response;
    }
    else if ([command isEqualToString:@"SCAN_FLOAT"]) {
        if (parts.count < 2) return @"ERROR: need value";
        float value = [parts[1] floatValue];
        float tolerance = (parts.count > 2) ? [parts[2] floatValue] : 0.001;
        int max = (parts.count > 3) ? [parts[3] intValue] : 500;
        NSArray *results = scanFloat(value, tolerance, max);
        NSMutableString *response = [NSMutableString stringWithFormat:@"RESULTS %lu", (unsigned long)results.count];
        for (NSNumber *addr in results) {
            [response appendFormat:@"\n0x%lx", [addr unsignedLongValue]];
        }
        return response;
    }
    else if ([command isEqualToString:@"READ_INT"]) {
        if (parts.count < 2) return @"ERROR: need addr";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        int val = safeReadInt(addr);
        return [NSString stringWithFormat:@"INT %d", val];
    }
    else if ([command isEqualToString:@"READ_FLOAT"]) {
        if (parts.count < 2) return @"ERROR: need addr";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        float val = safeReadFloat(addr);
        return [NSString stringWithFormat:@"FLOAT %f", val];
    }
    else if ([command isEqualToString:@"READ_PTR"]) {
        if (parts.count < 2) return @"ERROR: need addr";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        uintptr_t val = safeReadPtr(addr);
        return [NSString stringWithFormat:@"PTR 0x%lx", val];
    }
    else if ([command isEqualToString:@"READ_BYTE"]) {
        if (parts.count < 2) return @"ERROR: need addr";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        uint8_t val = safeReadByte(addr);
        return [NSString stringWithFormat:@"BYTE %d", val];
    }
    else if ([command isEqualToString:@"READ_SHORT"]) {
        if (parts.count < 2) return @"ERROR: need addr";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        uint16_t val = safeReadShort(addr);
        return [NSString stringWithFormat:@"SHORT %d", val];
    }
    else if ([command isEqualToString:@"READ_STRING"]) {
        if (parts.count < 2) return @"ERROR: need addr";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        int maxLen = (parts.count > 2) ? [parts[2] intValue] : 64;
        NSString *str = safeReadString(addr, maxLen);
        return [NSString stringWithFormat:@"STRING %@", str];
    }
    else if ([command isEqualToString:@"WRITE_INT"]) {
        if (parts.count < 3) return @"ERROR: need addr and value";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        int val = [parts[2] intValue];
        BOOL success = safeWriteInt(addr, val);
        return success ? @"OK" : @"ERROR: write failed";
    }
    else if ([command isEqualToString:@"WRITE_FLOAT"]) {
        if (parts.count < 3) return @"ERROR: need addr and value";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        float val = [parts[2] floatValue];
        BOOL success = safeWriteFloat(addr, val);
        return success ? @"OK" : @"ERROR: write failed";
    }
    else if ([command isEqualToString:@"WRITE_PTR"]) {
        if (parts.count < 3) return @"ERROR: need addr and value";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        uintptr_t val = strtoull([parts[2] UTF8String], NULL, 16);
        BOOL success = safeWritePtr(addr, val);
        return success ? @"OK" : @"ERROR: write failed";
    }
    else if ([command isEqualToString:@"WRITE_BYTE"]) {
        if (parts.count < 3) return @"ERROR: need addr and value";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        uint8_t val = [parts[2] intValue];
        BOOL success = safeWriteByte(addr, val);
        return success ? @"OK" : @"ERROR: write failed";
    }
    else if ([command isEqualToString:@"DUMP"]) {
        if (parts.count < 3) return @"ERROR: need addr and size";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        int size = [parts[2] intValue];
        if (size > 1048576) size = 1048576;
        
        NSData *data = memoryDump(addr, size);
        if (!data) return @"ERROR: dump failed";
        
        NSString *b64 = [data base64EncodedStringWithOptions:0];
        return [NSString stringWithFormat:@"DUMP_DATA %@", b64];
    }
    
    return @"ERROR: unknown command";
}

// ===== TCP СЕРВЕР =====
void startServer(void) {
    if (serverRunning) {
        addLog(@"⚠️ Сервер уже запущен");
        return;
    }
    
    serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (serverSocket < 0) {
        addLog(@"❌ Не удалось создать сокет");
        return;
    }
    
    int reuse = 1;
    setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(12345);
    
    if (bind(serverSocket, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        addLog(@"❌ Не удалось привязать порт 12345");
        close(serverSocket);
        serverSocket = -1;
        return;
    }
    
    if (listen(serverSocket, 5) < 0) {
        addLog(@"❌ Ошибка listen");
        close(serverSocket);
        serverSocket = -1;
        return;
    }
    
    serverRunning = YES;
    
    NSString *ip = getIPAddress();
    addLog(@"✅ Сервер запущен на порту 12345");
    addLog([NSString stringWithFormat:@"📡 IP: %@", ip]);
    addLog(@"💡 Подключитесь с ПК");
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (serverRunning) {
            struct sockaddr_in clientAddr;
            socklen_t clientLen = sizeof(clientAddr);
            int clientSocket = accept(serverSocket, (struct sockaddr*)&clientAddr, &clientLen);
            if (clientSocket < 0) continue;
            
            char clientIP[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &clientAddr.sin_addr, clientIP, sizeof(clientIP));
            addLog([NSString stringWithFormat:@"🔌 Подключён клиент: %s", clientIP]);
            
            char buffer[65536];
            while (serverRunning) {
                memset(buffer, 0, sizeof(buffer));
                ssize_t received = recv(clientSocket, buffer, sizeof(buffer) - 1, 0);
                if (received <= 0) break;
                
                NSString *cmd = [NSString stringWithUTF8String:buffer];
                cmd = [cmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                
                NSString *response = handleCommand(cmd);
                response = [response stringByAppendingString:@"\n"];
                const char *respData = [response UTF8String];
                send(clientSocket, respData, strlen(respData), 0);
            }
            close(clientSocket);
            addLog(@"🔌 Клиент отключён");
        }
    });
}

void stopServer(void) {
    serverRunning = NO;
    if (serverSocket >= 0) {
        close(serverSocket);
        serverSocket = -1;
    }
    addLog(@"🛑 Сервер остановлен");
}

// ===== ОБРАБОТЧИК КНОПОК =====
@interface ServerController : NSObject
+ (void)startServer;
+ (void)stopServer;
+ (void)closeMenu;
@end

@implementation ServerController
+ (void)startServer { startServer(); }
+ (void)stopServer { stopServer(); }
+ (void)closeMenu {
    if (win) {
        win.hidden = YES;
        win = nil;
    }
}
@end

// ===== МЕНЮ =====
void createMenu(void) {
    UIWindow *key = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class]) {
            UIWindowScene *ws = (UIWindowScene *)s;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) { key = w; break; }
            }
        }
        if (key) break;
    }
    if (!key) return;
    
    CGFloat w = 260, h = 220;
    CGFloat x = (key.bounds.size.width - w) / 2;
    CGFloat y = (key.bounds.size.height - h) / 2;
    
    win = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, w, h)];
    win.windowLevel = UIWindowLevelAlert + 2;
    win.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    win.layer.cornerRadius = 12;
    win.layer.borderWidth = 1;
    win.layer.borderColor = UIColor.systemBlueColor.CGColor;
    win.hidden = NO;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, w, 28)];
    title.text = @"📡 MEMORY SERVER";
    title.textColor = UIColor.systemBlueColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [win addSubview:title];
    
    logView = [[UITextView alloc] initWithFrame:CGRectMake(6, 42, w-12, 100)];
    logView.backgroundColor = UIColor.blackColor;
    logView.textColor = UIColor.greenColor;
    logView.font = [UIFont fontWithName:@"Courier" size:9];
    logView.editable = NO;
    logView.layer.cornerRadius = 6;
    [win addSubview:logView];
    
    CGFloat btnW = (w - 30) / 2;
    
    UIButton *startBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    startBtn.frame = CGRectMake(10, 150, btnW, 32);
    [startBtn setTitle:@"▶️ СТАРТ" forState:UIControlStateNormal];
    startBtn.backgroundColor = UIColor.systemGreenColor;
    [startBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    startBtn.layer.cornerRadius = 6;
    [startBtn addTarget:[ServerController class] action:@selector(startServer) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:startBtn];
    
    UIButton *stopBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    stopBtn.frame = CGRectMake(20 + btnW, 150, btnW, 32);
    [stopBtn setTitle:@"⏹️ СТОП" forState:UIControlStateNormal];
    stopBtn.backgroundColor = UIColor.systemRedColor;
    [stopBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    stopBtn.layer.cornerRadius = 6;
    [stopBtn addTarget:[ServerController class] action:@selector(stopServer) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:stopBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w/2-35, 190, 70, 26);
    [closeBtn setTitle:@"❌ ЗАКРЫТЬ" forState:UIControlStateNormal];
    closeBtn.backgroundColor = UIColor.systemGrayColor;
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 5;
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [closeBtn addTarget:[ServerController class] action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:closeBtn];
    
    [win makeKeyAndVisible];
}

// ===== ПЛАВАЮЩАЯ КНОПКА =====
@interface FloatBtn : UIView
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, assign) CGPoint last;
@end

@implementation FloatBtn
- (instancetype)init {
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;
    self = [super initWithFrame:CGRectMake(sw-65, sh-85, 55, 55)];
    if (self) {
        self.backgroundColor = UIColor.systemBlueColor;
        self.layer.cornerRadius = 27.5;
        self.layer.borderWidth = 2;
        self.layer.borderColor = UIColor.whiteColor.CGColor;
        self.userInteractionEnabled = YES;
        
        UILabel *l = [[UILabel alloc] initWithFrame:self.bounds];
        l.text = @"📡";
        l.textColor = UIColor.whiteColor;
        l.textAlignment = NSTextAlignmentCenter;
        l.font = [UIFont boldSystemFontOfSize:24];
        [self addSubview:l];
        
        UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:p];
        UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap)];
        [self addGestureRecognizer:t];
    }
    return self;
}
- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) self.last = self.center;
    CGPoint c = CGPointMake(self.last.x + t.x, self.last.y + t.y);
    CGFloat h = 30;
    c.x = MAX(h, MIN(self.superview.bounds.size.width - h, c.x));
    c.y = MAX(h+60, MIN(self.superview.bounds.size.height - h-60, c.y));
    self.center = c;
}
- (void)tap { if (self.onTap) self.onTap(); }
@end

@interface OverlayWin : UIWindow @property (nonatomic, weak) FloatBtn *btn; @end
@implementation OverlayWin
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    if (self.btn && !self.btn.hidden && CGRectContainsPoint(self.btn.frame, p)) return self.btn;
    return nil;
}
@end

@interface App : NSObject @property (nonatomic, strong) OverlayWin *w; @end
@implementation App
- (instancetype)init {
    self = [super init];
    if (self) {
        self.w = [[OverlayWin alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.w.windowLevel = UIWindowLevelAlert + 1;
        self.w.backgroundColor = UIColor.clearColor;
        self.w.hidden = NO;
        
        FloatBtn *b = [[FloatBtn alloc] init];
        self.w.btn = b;
        [self.w addSubview:b];
        
        b.onTap = ^{
            logText = nil;
            createMenu();
        };
    }
    return self;
}
@end

static App *app = nil;

__attribute__((constructor))
static void init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        app = [[App alloc] init];
        NSLog(@"[Memory Server] Ready");
    });
}
