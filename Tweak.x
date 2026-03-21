#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

// ===== ГЛОБАЛЬНЫЕ =====
static UIWindow *overlay = nil;
static UITextView *logView = nil;
static NSMutableString *logText = nil;
static UIButton *floatButton = nil;
static BOOL isSearching = NO;

// ===== БЕЗОПАСНОЕ ЧТЕНИЕ =====
uintptr_t readPtr(uintptr_t addr) {
    uintptr_t val = 0;
    vm_size_t out = 0;
    vm_read_overwrite(mach_task_self(), addr, sizeof(val), (vm_address_t)&val, &out);
    return val;
}

int readInt(uintptr_t addr) {
    int val = 0;
    vm_size_t out = 0;
    vm_read_overwrite(mach_task_self(), addr, sizeof(val), (vm_address_t)&val, &out);
    return val;
}

void addLog(NSString *msg) {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendString:msg];
    [logText appendString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        logView.text = logText;
        [logView scrollRangeToVisible:NSMakeRange(logView.text.length - 1, 1)];
    });
}

// ===== ПОИСК =====
void startSearch() {
    if (isSearching) {
        addLog(@"⚠️ Уже ищу...");
        return;
    }
    isSearching = YES;
    addLog(@"\n🔍 ПОИСК...");
    
    uintptr_t start = 0x100000000;
    uintptr_t end = 0x180000000;
    uintptr_t nameAddr = 0;
    
    // 1. Ищем строку с именем
    for (uintptr_t addr = start; addr < end; addr += 0x1000) {
        char buf[256] = {0};
        vm_size_t read = 0;
        vm_read_overwrite(mach_task_self(), addr, 128, (vm_address_t)buf, &read);
        if (strstr(buf, "ЯНалимБауров")) {
            nameAddr = addr;
            addLog([NSString stringWithFormat:@"✅ Имя: 0x%lx", addr]);
            break;
        }
    }
    
    if (!nameAddr) {
        addLog(@"❌ Имя не найдено. Зайди в матч!");
        isSearching = NO;
        return;
    }
    
    // 2. Ищем указатель на имя (структура +0x18)
    uintptr_t structStart = 0;
    for (uintptr_t addr = start; addr < end; addr += 8) {
        if (readPtr(addr) == nameAddr) {
            structStart = addr - 0x18;
            addLog([NSString stringWithFormat:@"✅ Структура: 0x%lx", structStart]);
            break;
        }
    }
    
    if (!structStart) {
        addLog(@"❌ Структура не найдена");
        isSearching = NO;
        return;
    }
    
    // 3. Читаем ID и Team
    int playerId = readInt(structStart + 0x10);
    int team = readInt(structStart + 0x34);
    addLog([NSString stringWithFormat:@"   ID: %d  Team: %d", playerId, team]);
    
    // 4. Ищем RoomController (указатель на структуру)
    uintptr_t roomCtrl = 0;
    uintptr_t playersArray = 0;
    
    for (uintptr_t addr = start; addr < start + 0x2000000; addr += 8) {
        if (readPtr(addr) == structStart) {
            uintptr_t arr = readPtr(addr + 0x140);
            if (arr > start && arr < end) {
                roomCtrl = addr;
                playersArray = arr;
                addLog([NSString stringWithFormat:@"✅ RoomController: 0x%lx", roomCtrl]);
                addLog([NSString stringWithFormat:@"✅ Массив игроков: 0x%lx", playersArray]);
                break;
            }
        }
    }
    
    if (!roomCtrl) {
        addLog(@"❌ RoomController не найден");
        isSearching = NO;
        return;
    }
    
    // 5. Выводим всех игроков
    addLog(@"\n📋 ВСЕ ИГРОКИ:");
    for (int i = 0; i < 32; i++) {
        uintptr_t p = readPtr(playersArray + i * 8);
        if (p == 0) break;
        int pid = readInt(p + 0x10);
        int pteam = readInt(p + 0x34);
        addLog([NSString stringWithFormat:@"   [%d] 0x%lx | ID: %d | Team: %d", i, p, pid, pteam]);
    }
    
    addLog(@"\n✅ ГОТОВО!");
    isSearching = NO;
}

// ===== СОЗДАНИЕ ОКНА =====
void createWindow() {
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
    
    CGFloat w = 300, h = 400;
    overlay = [[UIWindow alloc] initWithFrame:CGRectMake((key.bounds.size.width - w)/2, (key.bounds.size.height - h)/2, w, h)];
    overlay.windowLevel = UIWindowLevelAlert + 2;
    overlay.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    overlay.layer.cornerRadius = 15;
    overlay.layer.borderWidth = 1;
    overlay.layer.borderColor = UIColor.systemBlueColor.CGColor;
    overlay.hidden = NO;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, w, 30)];
    title.text = @"ESP FINDER";
    title.textColor = UIColor.systemBlueColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:16];
    [overlay addSubview:title];
    
    logView = [[UITextView alloc] initWithFrame:CGRectMake(10, 45, w-20, 260)];
    logView.backgroundColor = UIColor.blackColor;
    logView.textColor = UIColor.greenColor;
    logView.font = [UIFont fontWithName:@"Courier" size:11];
    logView.editable = NO;
    logView.layer.cornerRadius = 8;
    [overlay addSubview:logView];
    
    UIButton *searchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    searchBtn.frame = CGRectMake(15, 315, (w-40)/2, 40);
    [searchBtn setTitle:@"🔍 НАЙТИ" forState:UIControlStateNormal];
    searchBtn.backgroundColor = UIColor.systemBlueColor;
    [searchBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    searchBtn.layer.cornerRadius = 10;
    [searchBtn addTarget:nil action:@selector(onSearch) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:searchBtn];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(25 + (w-40)/2, 315, (w-40)/2, 40);
    [copyBtn setTitle:@"📋 КОПИ" forState:UIControlStateNormal];
    copyBtn.backgroundColor = UIColor.systemGreenColor;
    [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 10;
    [copyBtn addTarget:nil action:@selector(onCopy) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w/2-40, 365, 80, 30);
    [closeBtn setTitle:@"ЗАКРЫТЬ" forState:UIControlStateNormal];
    closeBtn.backgroundColor = UIColor.systemRedColor;
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 8;
    [closeBtn addTarget:overlay action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:closeBtn];
    
    [overlay makeKeyAndVisible];
}

void onSearch() {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        startSearch();
    });
}

void onCopy() {
    if (logView.text.length > 0) {
        UIPasteboard.generalPasteboard.string = logView.text;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅" message:@"Скопировано" preferredStyle:UIAlertControllerStyleAlert];
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

// ===== ПЛАВАЮЩАЯ КНОПКА =====
@interface FloatButton : UIView
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, assign) CGPoint lastPoint;
@end

@implementation FloatButton
- (instancetype)init {
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;
    self = [super initWithFrame:CGRectMake(sw-70, sh-90, 55, 55)];
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
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:pan];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}
- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) self.lastPoint = self.center;
    CGPoint c = CGPointMake(self.lastPoint.x + t.x, self.lastPoint.y + t.y);
    CGFloat h = self.frame.size.width/2;
    c.x = MAX(h, MIN(self.superview.bounds.size.width - h, c.x));
    c.y = MAX(h+60, MIN(self.superview.bounds.size.height - h-60, c.y));
    self.center = c;
}
- (void)tap { if (self.onTap) self.onTap(); }
@end

@interface OverlayWindow : UIWindow @property (nonatomic, weak) FloatButton *btn; @end
@implementation OverlayWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    if (self.btn && !self.btn.hidden && CGRectContainsPoint(self.btn.frame, p)) return self.btn;
    return nil;
}
@end

@interface App : NSObject @property (nonatomic, strong) OverlayWindow *win; @end
@implementation App
- (instancetype)init {
    self = [super init];
    if (self) {
        self.win = [[OverlayWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.win.windowLevel = UIWindowLevelAlert + 1;
        self.win.backgroundColor = UIColor.clearColor;
        self.win.hidden = NO;
        
        FloatButton *btn = [[FloatButton alloc] init];
        self.win.btn = btn;
        [self.win addSubview:btn];
        
        __weak typeof(self) weak = self;
        btn.onTap = ^{
            logText = nil;
            createWindow();
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
        NSLog(@"[ESP] Загружен");
    });
}
