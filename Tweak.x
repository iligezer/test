#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

// ===== ГЛОБАЛЬНЫЕ =====
static UIWindow *g_window = nil;
static UITextView *g_textView = nil;
static NSMutableString *g_log = nil;
static BOOL g_searching = NO;

// ===== БЕЗОПАСНОЕ ЧТЕНИЕ =====
size_t safeRead(uintptr_t addr, void *buf, size_t size) {
    @try {
        vm_size_t read = 0;
        vm_read_overwrite(mach_task_self(), addr, size, (vm_address_t)buf, &read);
        return read;
    } @catch (NSException *e) {
        return 0;
    }
}

void addLog(NSString *fmt, ...) {
    if (!g_log) g_log = [[NSMutableString alloc] init];
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    [g_log appendString:msg];
    [g_log appendString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_textView) g_textView.text = g_log;
    });
}

// ===== ПОИСК =====
void findEverything() {
    if (g_searching) { addLog(@"⏳ УЖЕ ИЩУ..."); return; }
    g_searching = YES;
    addLog(@"\n🔍 ИЩУ ЯНалимБауров...\n");
    
    uintptr_t start = 0x100000000;
    uintptr_t end = 0x180000000;
    uintptr_t playerAddr = 0;
    uintptr_t namePtr = 0;
    
    // 1. Находим указатель на имя "ЯНалимБауров"
    for (uintptr_t addr = start; addr < end && !namePtr; addr += 0x1000) {
        char buf[256] = {0};
        if (safeRead(addr, buf, 64) < 10) continue;
        if (strstr(buf, "ЯНалимБауров")) {
            namePtr = addr;
            addLog(@"✅ Имя найдено: 0x%lx", addr);
        }
    }
    
    if (!namePtr) {
        addLog(@"❌ Имя не найдено. Зайди в матч и нажми снова.");
        g_searching = NO;
        return;
    }
    
    // 2. Ищем указатель на это имя (начало структуры + 0x18)
    for (uintptr_t addr = start; addr < end && !playerAddr; addr += 8) {
        uintptr_t val = 0;
        if (safeRead(addr, &val, 8) == 8 && val == namePtr) {
            playerAddr = addr - 0x18; // начало структуры
            addLog(@"✅ Структура игрока: 0x%lx", playerAddr);
        }
    }
    
    if (!playerAddr) {
        addLog(@"❌ Не найден указатель на имя");
        g_searching = NO;
        return;
    }
    
    // 3. Проверяем ID
    int id = 0;
    safeRead(playerAddr + 0x10, &id, 4);
    int team = 0;
    safeRead(playerAddr + 0x34, &team, 4);
    addLog(@"   ID: %d, Team: %d", id, team);
    
    // 4. Ищем RoomController (указатель на эту структуру)
    uintptr_t roomCtrl = 0;
    uintptr_t playersArray = 0;
    
    for (uintptr_t addr = start; addr < start + 0x2000000 && !roomCtrl; addr += 8) {
        uintptr_t val = 0;
        if (safeRead(addr, &val, 8) == 8 && val == playerAddr) {
            // Проверяем, есть ли массив по +0x140
            uintptr_t arr = 0;
            if (safeRead(addr + 0x140, &arr, 8) == 8 && arr > start) {
                roomCtrl = addr;
                playersArray = arr;
                addLog(@"✅ RoomController: 0x%lx", roomCtrl);
                addLog(@"✅ Массив игроков: 0x%lx", playersArray);
            }
        }
    }
    
    if (!roomCtrl) {
        addLog(@"❌ RoomController не найден");
        g_searching = NO;
        return;
    }
    
    // 5. Выводим всех игроков
    addLog(@"\n📋 ВСЕ ИГРОКИ:");
    for (int i = 0; i < 32; i++) {
        uintptr_t p = 0;
        if (safeRead(playersArray + i * 8, &p, 8) != 8 || p == 0) break;
        int pid = 0, pteam = 0;
        safeRead(p + 0x10, &pid, 4);
        safeRead(p + 0x34, &pteam, 4);
        addLog(@"   [%d] 0x%lx | ID: %d | Team: %d", i, p, pid, pteam);
    }
    
    addLog(@"\n🎯 ГОТОВО! Адреса скопированы.");
    g_searching = NO;
}

// ===== СОЗДАНИЕ ОКНА =====
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
    
    CGFloat w = 340, h = 480;
    g_window = [[UIWindow alloc] initWithFrame:CGRectMake((key.frame.size.width-w)/2, (key.frame.size.height-h)/2, w, h)];
    g_window.windowLevel = UIWindowLevelAlert + 2;
    g_window.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    g_window.layer.cornerRadius = 20;
    g_window.layer.borderWidth = 2;
    g_window.layer.borderColor = UIColor.systemBlueColor.CGColor;
    g_window.hidden = NO;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 12, w, 30)];
    title.text = @"🎯 ESP FINDER";
    title.textColor = UIColor.systemBlueColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:18];
    [g_window addSubview:title];
    
    g_textView = [[UITextView alloc] initWithFrame:CGRectMake(12, 50, w-24, 330)];
    g_textView.backgroundColor = UIColor.blackColor;
    g_textView.textColor = UIColor.greenColor;
    g_textView.font = [UIFont fontWithName:@"Courier" size:11];
    g_textView.editable = NO;
    g_textView.selectable = YES;
    g_textView.layer.cornerRadius = 10;
    [g_window addSubview:g_textView];
    
    UIButton *search = [UIButton buttonWithType:UIButtonTypeSystem];
    search.frame = CGRectMake(15, 395, (w-45)/2, 42);
    [search setTitle:@"🔍 НАЙТИ" forState:UIControlStateNormal];
    search.backgroundColor = UIColor.systemBlueColor;
    [search setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    search.layer.cornerRadius = 12;
    [search addTarget:nil action:@selector(startSearch) forControlEvents:UIControlEventTouchUpInside];
    [g_window addSubview:search];
    
    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    copy.frame = CGRectMake(25 + (w-45)/2, 395, (w-45)/2, 42);
    [copy setTitle:@"📋 КОПИ" forState:UIControlStateNormal];
    copy.backgroundColor = UIColor.systemGreenColor;
    [copy setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    copy.layer.cornerRadius = 12;
    [copy addTarget:nil action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [g_window addSubview:copy];
    
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(w/2-50, 445, 100, 32);
    [close setTitle:@"ЗАКРЫТЬ" forState:UIControlStateNormal];
    close.backgroundColor = UIColor.systemRedColor;
    [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    close.layer.cornerRadius = 8;
    [close addTarget:g_window action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
    [g_window addSubview:close];
    
    [g_window makeKeyAndVisible];
}

void startSearch() {
    if (g_searching) { addLog(@"⚠️ УЖЕ ИЩУ"); return; }
    addLog(@"✅ НАЧАЛО ПОИСКА...\n");
    dispatch_async(dispatch_get_global_queue(0, 0), ^{ findEverything(); });
}

void copyLog() {
    if (g_textView.text.length) {
        UIPasteboard.generalPasteboard.string = g_textView.text;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅" message:@"Скопировано" preferredStyle:UIAlertControllerStyleAlert];
        UIWindow *k = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class]) {
                for (UIWindow *w in ((UIWindowScene *)s).windows) if (w.isKeyWindow) { k = w; break; }
            }
            if (k) break;
        }
        [k.rootViewController presentViewController:alert animated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1e9), dispatch_get_main_queue(), ^{ [alert dismissViewControllerAnimated:YES completion:nil]; });
    }
}

// ===== КНОПКА =====
@interface FloatButton : UIImageView
@property (nonatomic, copy) void (^action)(void);
@property (nonatomic, assign) CGPoint last;
@end

@implementation FloatButton
- (instancetype)init {
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;
    self = [super initWithFrame:CGRectMake(sw-75, sh-95, 60, 60)];
    if (self) {
        self.backgroundColor = UIColor.systemBlueColor;
        self.layer.cornerRadius = 30;
        self.layer.borderWidth = 2;
        self.layer.borderColor = UIColor.whiteColor.CGColor;
        self.userInteractionEnabled = YES;
        UILabel *l = [[UILabel alloc] initWithFrame:self.bounds];
        l.text = @"🎯";
        l.textColor = UIColor.whiteColor;
        l.textAlignment = NSTextAlignmentCenter;
        l.font = [UIFont boldSystemFontOfSize:28];
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
    CGFloat h = self.frame.size.width/2;
    c.x = MAX(h, MIN(self.superview.bounds.size.width - h, c.x));
    c.y = MAX(h+60, MIN(self.superview.bounds.size.height - h-60, c.y));
    self.center = c;
}
- (void)tap { if (self.action) self.action(); }
@end

@interface Passthrough : UIWindow @property (nonatomic, weak) FloatButton *btn; @end
@implementation Passthrough
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    if (self.btn && !self.btn.hidden && CGRectContainsPoint(self.btn.frame, p)) return self.btn;
    return nil;
}
@end

@interface App : NSObject @property (nonatomic, strong) Passthrough *w; @end
@implementation App
- (instancetype)init {
    self = [super init];
    if (self) {
        self.w = [[Passthrough alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.w.windowLevel = UIWindowLevelAlert + 1;
        self.w.backgroundColor = UIColor.clearColor;
        self.w.hidden = NO;
        FloatButton *b = [[FloatButton alloc] init];
        self.w.btn = b;
        [self.w addSubview:b];
        __weak typeof(self) weak = self;
        [b setAction:^{
            g_log = nil;
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
        NSLog(@"[ESP] Готов");
    });
}
