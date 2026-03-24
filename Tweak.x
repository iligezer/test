#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <ifaddrs.h>
#import <net/if.h>

// ===== СТРУКТУРЫ =====
typedef struct {
    float x;
    float y;
    float z;
} Vector3;

// ===== ГЛОБАЛЬНЫЕ =====
static int serverSocket = -1;
static BOOL serverRunning = NO;
static NSMutableString *logText = nil;
static UITextView *logView = nil;
static UIWindow *win = nil;
static uintptr_t g_baseAddress = 0;
static uintptr_t g_localPlayer = 0;
static uintptr_t g_transform = 0;

// ===== ЛОГИРОВАНИЕ =====
void addLog(NSString *msg) {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendString:msg];
    [logText appendString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (logView) logView.text = logText;
        NSLog(@"[ESP] %@", msg);
    });
}

void addLogF(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    addLog(msg);
}

// ===== ПОЛУЧЕНИЕ IP АДРЕСА =====
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

// ===== ПОЛУЧЕНИЕ БАЗОВОГО АДРЕСА =====
uintptr_t getBaseAddress(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework") != NULL) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

// ===== БЕЗОПАСНОЕ ЧТЕНИЕ ПАМЯТИ =====
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

// ===== ВЫЗОВ ФУНКЦИИ ПО АДРЕСУ =====
uintptr_t callFunction(uintptr_t addr) {
    if (addr == 0) return 0;
    @try {
        uintptr_t (*func)() = (uintptr_t(*)())addr;
        return func();
    } @catch (NSException *e) {
        return 0;
    }
}

uintptr_t callFunctionWithArg(uintptr_t addr, uintptr_t arg) {
    if (addr == 0) return 0;
    @try {
        uintptr_t (*func)(uintptr_t) = (uintptr_t(*)(uintptr_t))addr;
        return func(arg);
    } @catch (NSException *e) {
        return 0;
    }
}

Vector3 callGetPosition(uintptr_t addr, uintptr_t transform) {
    Vector3 result = {0, 0, 0};
    if (addr == 0 || transform == 0) return result;
    @try {
        void (*func)(uintptr_t, Vector3*) = (void(*)(uintptr_t, Vector3*))addr;
        func(transform, &result);
    } @catch (NSException *e) {
        result.x = 0; result.y = 0; result.z = 0;
    }
    return result;
}

// ===== ПОЛУЧЕНИЕ КООРДИНАТ =====
Vector3 getLocalPlayerPosition(void) {
    Vector3 result = {0, 0, 0};
    
    // 1. Получить базовый адрес
    if (g_baseAddress == 0) {
        g_baseAddress = getBaseAddress();
        if (g_baseAddress == 0) {
            addLog(@"❌ Не удалось найти UnityFramework");
            return result;
        }
        addLogF(@"✅ Базовый адрес: 0x%lx", g_baseAddress);
    }
    
    // 2. Смещения из script.json
    uintptr_t addrGetPlayerController = g_baseAddress + 0x32494CC;
    uintptr_t addrGetTransform = g_baseAddress + 0x44B9D00;
    uintptr_t addrGetPosition = g_baseAddress + 0x44CEED0;
    
    // 3. Получить локального игрока
    uintptr_t localPlayer = callFunction(addrGetPlayerController);
    if (localPlayer == 0) {
        addLog(@"⚠️ get_PlayerController вернул 0");
        return result;
    }
    g_localPlayer = localPlayer;
    
    // 4. Получить Transform
    uintptr_t transform = callFunctionWithArg(addrGetTransform, localPlayer);
    if (transform == 0) {
        addLog(@"⚠️ get_transform вернул 0");
        return result;
    }
    g_transform = transform;
    
    // 5. Получить координаты
    result = callGetPosition(addrGetPosition, transform);
    
    return result;
}

// ===== ОТПРАВКА КООРДИНАТ НА ПК =====
void sendCoordinatesToPC(int clientSocket) {
    Vector3 pos = getLocalPlayerPosition();
    NSString *response = [NSString stringWithFormat:@"COORDS %.2f %.2f %.2f\n", pos.x, pos.y, pos.z];
    const char *data = [response UTF8String];
    send(clientSocket, data, strlen(data), 0);
    addLogF(@"📤 Отправлено: X=%.2f Y=%.2f Z=%.2f", pos.x, pos.y, pos.z);
}

// ===== ОБРАБОТКА КОМАНД =====
NSString* handleCommand(NSString *cmd) {
    NSArray *parts = [cmd componentsSeparatedByString:@" "];
    NSString *command = [parts[0] uppercaseString];
    
    addLogF(@"📥 CMD: %@", cmd);
    
    if ([command isEqualToString:@"PING"]) {
        return @"PONG";
    }
    else if ([command isEqualToString:@"GET_POS"]) {
        Vector3 pos = getLocalPlayerPosition();
        return [NSString stringWithFormat:@"POS %.2f %.2f %.2f", pos.x, pos.y, pos.z];
    }
    else if ([command isEqualToString:@"GET_BASE"]) {
        if (g_baseAddress == 0) g_baseAddress = getBaseAddress();
        return [NSString stringWithFormat:@"BASE 0x%lx", g_baseAddress];
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
    addLogF(@"📡 IP: %@", ip);
    addLog(@"💡 Подключитесь с ПК");
    addLog(@"📡 Команды: GET_POS, GET_BASE, PING");
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (serverRunning) {
            struct sockaddr_in clientAddr;
            socklen_t clientLen = sizeof(clientAddr);
            int clientSocket = accept(serverSocket, (struct sockaddr*)&clientAddr, &clientLen);
            if (clientSocket < 0) continue;
            
            char clientIP[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &clientAddr.sin_addr, clientIP, sizeof(clientIP));
            addLogF(@"🔌 Подключён клиент: %s", clientIP);
            
            char buffer[4096];
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
+ (void)testESP;
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
+ (void)testESP {
    Vector3 pos = getLocalPlayerPosition();
    NSString *msg = [NSString stringWithFormat:@"X: %.2f\nY: %.2f\nZ: %.2f\n\nBase: 0x%lx\nPlayer: 0x%lx\nTransform: 0x%lx", 
                     pos.x, pos.y, pos.z, g_baseAddress, g_localPlayer, g_transform];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎯 ESP TEST" 
                                                                   message:msg 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    UIWindow *key = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *w in ((UIWindowScene *)s).windows) {
                if (w.isKeyWindow) { key = w; break; }
            }
        }
        if (key) break;
    }
    [key.rootViewController presentViewController:alert animated:YES completion:nil];
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
    
    CGFloat w = 280, h = 280;
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
    title.text = @"🎯 ESP SERVER";
    title.textColor = UIColor.systemBlueColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [win addSubview:title];
    
    logView = [[UITextView alloc] initWithFrame:CGRectMake(6, 42, w-12, 120)];
    logView.backgroundColor = UIColor.blackColor;
    logView.textColor = UIColor.greenColor;
    logView.font = [UIFont fontWithName:@"Courier" size:9];
    logView.editable = NO;
    logView.layer.cornerRadius = 6;
    [win addSubview:logView];
    
    CGFloat btnW = (w - 30) / 2;
    
    UIButton *testBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    testBtn.frame = CGRectMake(10, 170, btnW, 38);
    [testBtn setTitle:@"🎯 TEST ESP" forState:UIControlStateNormal];
    testBtn.backgroundColor = UIColor.systemPurpleColor;
    [testBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    testBtn.layer.cornerRadius = 6;
    [testBtn addTarget:[ServerController class] action:@selector(testESP) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:testBtn];
    
    UIButton *startBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    startBtn.frame = CGRectMake(20 + btnW, 170, btnW, 38);
    [startBtn setTitle:@"▶️ СТАРТ" forState:UIControlStateNormal];
    startBtn.backgroundColor = UIColor.systemGreenColor;
    [startBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    startBtn.layer.cornerRadius = 6;
    [startBtn addTarget:[ServerController class] action:@selector(startServer) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:startBtn];
    
    UIButton *stopBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    stopBtn.frame = CGRectMake(10, 215, btnW, 38);
    [stopBtn setTitle:@"⏹️ СТОП" forState:UIControlStateNormal];
    stopBtn.backgroundColor = UIColor.systemRedColor;
    [stopBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    stopBtn.layer.cornerRadius = 6;
    [stopBtn addTarget:[ServerController class] action:@selector(stopServer) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:stopBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20 + btnW, 215, btnW, 38);
    [closeBtn setTitle:@"❌ ЗАКРЫТЬ" forState:UIControlStateNormal];
    closeBtn.backgroundColor = UIColor.systemGrayColor;
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 6;
    [closeBtn addTarget:[ServerController class] action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:closeBtn];
    
    [win makeKeyAndVisible];
    
    // Предварительная инициализация
    g_baseAddress = getBaseAddress();
    if (g_baseAddress != 0) {
        addLogF(@"✅ Base: 0x%lx", g_baseAddress);
    } else {
        addLog(@"⚠️ Base address not found");
    }
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
        NSLog(@"[ESP] Ready");
    });
}
