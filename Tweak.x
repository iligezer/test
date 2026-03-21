#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

static UIWindow *g_logWindow = nil;
static UITextView *g_logTextView = nil;
static NSMutableString *g_logText = nil;
static BOOL g_isSearching = NO;

size_t safeRead(uintptr_t addr, void *buf, size_t size) {
    @try {
        vm_size_t read = 0;
        kern_return_t kr = vm_read_overwrite(current_task(), (vm_address_t)addr, size, (vm_address_t)buf, &read);
        return (kr == KERN_SUCCESS) ? read : 0;
    } @catch (NSException *e) {
        return 0;
    }
}

void addLog(NSString *format, ...) {
    if (!g_logText) g_logText = [[NSMutableString alloc] init];
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [g_logText appendString:msg];
    [g_logText appendString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        g_logTextView.text = g_logText;
        [g_logTextView scrollRangeToVisible:NSMakeRange(g_logTextView.text.length - 1, 1)];
    });
}

void findRoomController() {
    if (g_isSearching) { addLog(@"⏳ Жди..."); return; }
    g_isSearching = YES;
    
    addLog(@"\n🔍 ПОИСК ROOMCONTROLLER");
    addLog(@"======================");
    
    uintptr_t start = 0x100000000;
    uintptr_t end = 0x180000000;
    uintptr_t players[50];
    int playerCount = 0;
    
    addLog(@"📊 Сканирую...");
    
    // Ищем игроков по ID (не нулевой, не гигантский мусор) и Team (0 или 1)
    for (uintptr_t addr = start; addr < end && playerCount < 30; addr += 0x1000) {
        for (int off = 0; off < 0x1000 && playerCount < 30; off += 16) {
            uintptr_t ptr = 0;
            if (safeRead(addr + off, &ptr, 8) != 8) continue;
            if (ptr < start || ptr > end) continue;
            
            int team = 0, id = 0;
            if (safeRead(ptr + 0x34, &team, 4) == 4 &&
                safeRead(ptr + 0x10, &id, 4) == 4) {
                
                // ID: не 0, не мусор (> 10 млн), но не гигантский (< 200 млн)
                if ((team == 0 || team == 1) && id > 10000000 && id < 200000000) {
                    BOOL dup = NO;
                    for (int i = 0; i < playerCount; i++) if (players[i] == ptr) { dup = YES; break; }
                    if (!dup) {
                        players[playerCount++] = ptr;
                        addLog(@"   🎮 0x%lx | ID: %d | Team: %d", ptr, id, team);
                    }
                }
            }
        }
    }
    
    addLog(@"\n📊 Игроков: %d", playerCount);
    if (playerCount < 2) {
        addLog(@"❌ Мало игроков. Ты в матче?");
        g_isSearching = NO;
        return;
    }
    
    addLog(@"\n🔍 Ищу RoomController...");
    
    for (int i = 0; i < playerCount && i < 5; i++) {
        uintptr_t target = players[i];
        addLog(@"\n📌 Проверяю 0x%lx", target);
        
        for (uintptr_t addr = start; addr < start + 0x2000000; addr += 8) {
            uintptr_t ptr = 0;
            if (safeRead(addr, &ptr, 8) != 8) continue;
            if (ptr == target) {
                addLog(@"   🔗 Указатель: 0x%lx", addr);
                
                uintptr_t arr = 0;
                if (safeRead(addr + 0x140, &arr, 8) == 8 && arr > start) {
                    addLog(@"   📦 Массив +0x140: 0x%lx", arr);
                    
                    int cnt = 0;
                    for (int j = 0; j < 20; j++) {
                        uintptr_t p = 0;
                        if (safeRead(arr + j * 8, &p, 8) == 8 && p != 0) cnt++;
                        else break;
                    }
                    
                    if (cnt >= playerCount - 2) {
                        addLog(@"\n🎯 ROOMCONTROLLER: 0x%lx", addr);
                        addLog(@"🎯 МАССИВ: 0x%lx", arr);
                        addLog(@"🎯 ИГРОКОВ: %d", cnt);
                        
                        addLog(@"\n📋 ВСЕ ИГРОКИ:");
                        for (int j = 0; j < cnt; j++) {
                            uintptr_t p = 0;
                            safeRead(arr + j * 8, &p, 8);
                            int pid = 0, pteam = 0;
                            safeRead(p + 0x10, &pid, 4);
                            safeRead(p + 0x34, &pteam, 4);
                            addLog(@"   [%d] 0x%lx | ID: %d | Team: %d", j, p, pid, pteam);
                        }
                        g_isSearching = NO;
                        return;
                    }
                }
            }
        }
    }
    
    addLog(@"\n❌ RoomController не найден");
    addLog(@"💡 Зайди в матч и нажми снова");
    g_isSearching = NO;
}

void createWindow() {
    UIWindow *key = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class]) {
            UIWindowScene *ws = (UIWindowScene *)s;
            for (UIWindow *w in ws.windows) if (w.isKeyWindow) { key = w; break; }
        }
        if (key) break;
    }
    if (!key) return;
    
    CGFloat w = 300, h = 380;
    CGFloat x = (key.frame.size.width - w) / 2;
    CGFloat y = (key.frame.size.height - h) / 2;
    
    g_logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, w, h)];
    g_logWindow.windowLevel = UIWindowLevelAlert + 2;
    g_logWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
    g_logWindow.layer.cornerRadius = 15;
    g_logWindow.layer.borderWidth = 2;
    g_logWindow.layer.borderColor = UIColor.systemBlueColor.CGColor;
    g_logWindow.hidden = NO;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, w, 28)];
    title.text = @"🎯 ESP";
    title.textColor = UIColor.systemBlueColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:16];
    [g_logWindow addSubview:title];
    
    g_logTextView = [[UITextView alloc] initWithFrame:CGRectMake(8, 40, w - 16, 260)];
    g_logTextView.backgroundColor = UIColor.blackColor;
    g_logTextView.textColor = UIColor.greenColor;
    g_logTextView.font = [UIFont fontWithName:@"Courier" size:10];
    g_logTextView.editable = NO;
    g_logTextView.selectable = YES;
    g_logTextView.layer.cornerRadius = 8;
    [g_logWindow addSubview:g_logTextView];
    
    UIButton *search = [UIButton buttonWithType:UIButtonTypeSystem];
    search.frame = CGRectMake(12, 310, (w - 35) / 2, 36);
    [search setTitle:@"🔍 НАЙТИ" forState:UIControlStateNormal];
    search.backgroundColor = UIColor.systemBlueColor;
    [search setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    search.layer.cornerRadius = 8;
    [search addTarget:nil action:@selector(startSearch) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:search];
    
    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    copy.frame = CGRectMake(20 + (w - 35) / 2, 310, (w - 35) / 2, 36);
    [copy setTitle:@"📋 КОПИ" forState:UIControlStateNormal];
    copy.backgroundColor = UIColor.systemGreenColor;
    [copy setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    copy.layer.cornerRadius = 8;
    [copy addTarget:nil action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:copy];
    
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(w/2 - 45, 352, 90, 28);
    [close setTitle:@"ЗАКРЫТЬ" forState:UIControlStateNormal];
    close.backgroundColor = UIColor.systemRedColor;
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.layer.cornerRadius = 6;
    [close addTarget:g_logWindow action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:close];
    
    [g_logWindow makeKeyAndVisible];
}

void startSearch() {
    if (g_isSearching) { addLog(@"⏳ Жди..."); return; }
    addLog(@"\n🔍 СТАРТ");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        findRoomController();
    });
}

void copyLog() {
    if (g_logTextView && g_logTextView.text.length) {
        UIPasteboard.generalPasteboard.string = g_logTextView.text;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅" message:@"Скопировано" preferredStyle:UIAlertControllerStyleAlert];
        UIWindow *key = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class]) {
                UIWindowScene *ws = (UIWindowScene *)s;
                for (UIWindow *w in ws.windows) if (w.isKeyWindow) { key = w; break; }
            }
            if (key) break;
        }
        [key.rootViewController presentViewController:alert animated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }
}

@interface FloatButton : UIImageView
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, assign) CGPoint last;
@end

@implementation FloatButton
- (instancetype)init {
    CGFloat w = UIScreen.mainScreen.bounds.size.width;
    CGFloat h = UIScreen.mainScreen.bounds.size.height;
    self = [super initWithFrame:CGRectMake(w - 70, h - 90, 55, 55)];
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
    CGFloat r = 27.5;
    c.x = MAX(r, MIN(self.superview.bounds.size.width - r, c.x));
    c.y = MAX(r + 60, MIN(self.superview.bounds.size.height - r - 60, c.y));
    self.center = c;
}
- (void)tap { if (self.onTap) self.onTap(); }
@end

@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *btn;
@end

@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    if (self.btn && !self.btn.hidden) {
        CGPoint bp = [self convertPoint:p toView:self.btn];
        if ([self.btn pointInside:bp withEvent:e]) return self.btn;
    }
    return nil;
}
@end

@interface App : NSObject
@property (nonatomic, strong) PassthroughWindow *win;
@end

@implementation App
- (instancetype)init {
    self = [super init];
    if (self) {
        self.win = [[PassthroughWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.win.windowLevel = UIWindowLevelAlert + 1;
        self.win.backgroundColor = UIColor.clearColor;
        self.win.hidden = NO;
        FloatButton *btn = [[FloatButton alloc] init];
        self.win.btn = btn;
        [self.win addSubview:btn];
        __weak typeof(self) weak = self;
        [btn setOnTap:^{
            g_logText = nil;
            createWindow();
        }];
    }
    return self;
}
@end

static App *g_app = nil;

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_app = [[App alloc] init];
    });
}
