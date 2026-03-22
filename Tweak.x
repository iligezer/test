#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <pthread.h>

// ===== ГЛОБАЛЬНЫЕ =====
static UIWindow *win = nil;
static UITextView *logView = nil;
static NSMutableString *logText = nil;
static int serverSocket = -1;
static BOOL serverRunning = NO;
static int g_targetID = 71068432;

void addLog(NSString *msg) {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendString:msg];
    [logText appendString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (logView) logView.text = logText;
    });
}

void addLogF(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    addLog(msg);
}

// ===== БЕЗОПАСНОЕ ЧТЕНИЕ =====
int safeReadInt(uintptr_t addr) {
    if (addr == 0) return 0;
    @try {
        int val = 0;
        vm_size_t read = 0;
        kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, &read);
        if (kr != KERN_SUCCESS || read != 4) return 0;
        return val;
    } @catch (NSException *e) {
        return 0;
    }
}

uintptr_t safeReadPtr(uintptr_t addr) {
    if (addr == 0) return 0;
    @try {
        uintptr_t val = 0;
        vm_size_t read = 0;
        kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, 8, (vm_address_t)&val, &read);
        if (kr != KERN_SUCCESS || read != 8) return 0;
        return val;
    } @catch (NSException *e) {
        return 0;
    }
}

float safeReadFloat(uintptr_t addr) {
    if (addr == 0) return 0;
    @try {
        float val = 0;
        vm_size_t read = 0;
        kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, &read);
        if (kr != KERN_SUCCESS || read != 4) return 0;
        return val;
    } @catch (NSException *e) {
        return 0;
    }
}

// ===== СКАНИРОВАНИЕ ID =====
NSMutableArray* scanIDs() {
    NSMutableArray *results = [NSMutableArray array];
    int found = 0;
    
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
                kern_return_t kr2 = vm_read_overwrite(task, page, pageSize, (vm_address_t)buffer, &read);
                if (kr2 != KERN_SUCCESS || read < 4) continue;
                
                for (uintptr_t offset = 0; offset + 4 <= pageSize; offset += 8) {
                    int val = *(int*)(buffer + offset);
                    if (val == g_targetID && found < 1000) {
                        found++;
                        [results addObject:@(page + offset)];
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

// ===== ОБРАБОТКА КОМАНД =====
NSString* processCommand(NSString *cmd) {
    NSArray *parts = [cmd componentsSeparatedByString:@" "];
    NSString *command = [parts[0] uppercaseString];
    
    if ([command isEqualToString:@"PING"]) {
        return @"PONG";
    }
    else if ([command isEqualToString:@"SCAN_ID"]) {
        NSMutableArray *ids = scanIDs();
        NSMutableString *response = [NSMutableString stringWithFormat:@"COUNT:%lu\n", (unsigned long)ids.count];
        for (NSNumber *addr in ids) {
            [response appendFormat:@"0x%llx\n", [addr unsignedLongLongValue]];
        }
        return response;
    }
    else if ([command isEqualToString:@"READ_INT"] && parts.count >= 2) {
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        int val = safeReadInt(addr);
        return [NSString stringWithFormat:@"%d", val];
    }
    else if ([command isEqualToString:@"READ_PTR"] && parts.count >= 2) {
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        uintptr_t val = safeReadPtr(addr);
        return [NSString stringWithFormat:@"0x%llx", (unsigned long long)val];
    }
    else if ([command isEqualToString:@"READ_FLOAT"] && parts.count >= 2) {
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        float val = safeReadFloat(addr);
        return [NSString stringWithFormat:@"%f", val];
    }
    else if ([command isEqualToString:@"READ_BYTES"] && parts.count >= 3) {
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        int size = [parts[2] intValue];
        if (size > 1024) size = 1024;
        
        uint8_t *buffer = malloc(size);
        vm_size_t read = 0;
        kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, size, (vm_address_t)buffer, &read);
        
        if (kr != KERN_SUCCESS || read < size) {
            free(buffer);
            return @"ERROR: Cannot read";
        }
        
        NSMutableString *hex = [NSMutableString string];
        for (int i = 0; i < read; i++) {
            [hex appendFormat:@"%02X", buffer[i]];
        }
        free(buffer);
        return hex;
    }
    else {
        return @"ERROR: Unknown command";
    }
}

// ===== ПОТОК СЕРВЕРА =====
void* serverThread(void *arg) {
    int sock = (int)(intptr_t)arg;
    
    while (serverRunning) {
        struct sockaddr_in clientAddr;
        socklen_t clientLen = sizeof(clientAddr);
        int clientSock = accept(sock, (struct sockaddr*)&clientAddr, &clientLen);
        
        if (clientSock < 0) continue;
        
        char buffer[4096];
        ssize_t bytes = recv(clientSock, buffer, sizeof(buffer) - 1, 0);
        if (bytes > 0) {
            buffer[bytes] = '\0';
            NSString *cmd = [NSString stringWithUTF8String:buffer];
            cmd = [cmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            
            addLogF(@"📥 Command: %@", cmd);
            NSString *response = processCommand(cmd);
            addLogF(@"📤 Response: %@", [response substringToIndex:MIN(100, response.length)]);
            
            const char *respC = [response UTF8String];
            send(clientSock, respC, strlen(respC), 0);
        }
        close(clientSock);
    }
    return NULL;
}

// ===== ЗАПУСК СЕРВЕРА =====
void startServer() {
    if (serverRunning) {
        addLog(@"⚠️ Server already running");
        return;
    }
    
    serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (serverSocket < 0) {
        addLog(@"❌ Failed to create socket");
        return;
    }
    
    int opt = 1;
    setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    struct sockaddr_in addr;
    addr.sin_family = AF_INET;
    addr.sin_port = htons(12345);
    addr.sin_addr.s_addr = INADDR_ANY;
    
    if (bind(serverSocket, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        addLog(@"❌ Failed to bind port 12345");
        close(serverSocket);
        return;
    }
    
    if (listen(serverSocket, 5) < 0) {
        addLog(@"❌ Failed to listen");
        close(serverSocket);
        return;
    }
    
    serverRunning = YES;
    
    pthread_t thread;
    pthread_create(&thread, NULL, serverThread, (void*)(intptr_t)serverSocket);
    pthread_detach(thread);
    
    addLog(@"✅ Server started on port 12345");
    addLog(@"📱 iPhone IP: 192.168.1.65");
    addLog(@"💻 Connect from PC: telnet 192.168.1.65 12345");
}

// ===== ОСТАНОВКА СЕРВЕРА =====
void stopServer() {
    if (!serverRunning) return;
    serverRunning = NO;
    close(serverSocket);
    addLog(@"🛑 Server stopped");
}

// ===== КЛАСС-ОБРАБОТЧИК =====
@interface MenuHandler : NSObject
+ (void)onStartServer;
+ (void)onStopServer;
+ (void)onClear;
+ (void)onCopy;
+ (void)onClose;
@end

@implementation MenuHandler
+ (void)onStartServer {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        startServer();
    });
}
+ (void)onStopServer {
    stopServer();
}
+ (void)onClear {
    logText = nil;
    addLog(@"🗑 Log cleared");
}
+ (void)onCopy {
    if (logView && logView.text.length > 0) {
        UIPasteboard.generalPasteboard.string = logView.text;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅" message:@"Copied" preferredStyle:UIAlertControllerStyleAlert];
        UIWindow *k = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class]) {
                for (UIWindow *w in ((UIWindowScene *)s).windows) {
                    if (w.isKeyWindow) { k = w; break; }
                }
            }
            if (k) break;
        }
        [k.rootViewController presentViewController:alert animated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }
}
+ (void)onClose {
    if (win) {
        win.hidden = YES;
        win = nil;
    }
}
@end

// ===== МЕНЮ =====
void createMenu() {
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
    
    CGFloat w = 280, h = 300;
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
    title.text = @"🎯 MEMORY SERVER";
    title.textColor = UIColor.systemBlueColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [win addSubview:title];
    
    logView = [[UITextView alloc] initWithFrame:CGRectMake(8, 42, w-16, 150)];
    logView.backgroundColor = UIColor.blackColor;
    logView.textColor = UIColor.greenColor;
    logView.font = [UIFont fontWithName:@"Courier" size:9];
    logView.editable = NO;
    logView.layer.cornerRadius = 6;
    [win addSubview:logView];
    
    CGFloat btnW = (w - 30) / 2;
    
    UIButton *startBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    startBtn.frame = CGRectMake(10, 200, btnW, 38);
    [startBtn setTitle:@"🚀 START" forState:UIControlStateNormal];
    startBtn.backgroundColor = UIColor.systemGreenColor;
    [startBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    startBtn.layer.cornerRadius = 6;
    [startBtn addTarget:[MenuHandler class] action:@selector(onStartServer) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:startBtn];
    
    UIButton *stopBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    stopBtn.frame = CGRectMake(20 + btnW, 200, btnW, 38);
    [stopBtn setTitle:@"🛑 STOP" forState:UIControlStateNormal];
    stopBtn.backgroundColor = UIColor.systemRedColor;
    [stopBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    stopBtn.layer.cornerRadius = 6;
    [stopBtn addTarget:[MenuHandler class] action:@selector(onStopServer) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:stopBtn];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(10, 245, btnW, 34);
    [copyBtn setTitle:@"📋 COPY" forState:UIControlStateNormal];
    copyBtn.backgroundColor = UIColor.systemGrayColor;
    [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 6;
    [copyBtn addTarget:[MenuHandler class] action:@selector(onCopy) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20 + btnW, 245, btnW, 34);
    [closeBtn setTitle:@"❌ CLOSE" forState:UIControlStateNormal];
    closeBtn.backgroundColor = UIColor.systemGrayColor;
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 6;
    [closeBtn addTarget:[MenuHandler class] action:@selector(onClose) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:closeBtn];
    
    [win makeKeyAndVisible];
    addLog(@"✅ Ready! Press START to begin");
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
        l.text = @"🎯";
        l.textColor = UIColor.whiteColor;
        l.textAlignment = NSTextAlignmentCenter;
        l.font = [UIFont boldSystemFontOfSize:26];
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
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        app = [[App alloc] init];
        NSLog(@"[Memory Server] Ready");
    });
}
