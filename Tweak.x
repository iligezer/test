#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

// ===== ГЛОБАЛЬНЫЕ =====
static UIWindow *g_win = nil;
static UITextView *g_txt = nil;
static NSMutableString *g_log = nil;
static UIButton *g_floatBtn = nil;
static BOOL g_searching = NO;

// ID игроков (твои данные)
#define MY_ID 71068432
#define ENEMY_ID 55471766

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
    if (!g_log) g_log = [[NSMutableString alloc] init];
    [g_log appendString:msg];
    [g_log appendString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        g_txt.text = g_log;
        [g_txt scrollRangeToVisible:NSMakeRange(g_txt.text.length - 1, 1)];
    });
}

// ===== ПОИСК ПО ID =====
uintptr_t findIdAddress(int targetId, uintptr_t start, uintptr_t end) {
    for (uintptr_t addr = start; addr < end; addr += 4) {
        int val = readInt(addr);
        if (val == targetId) {
            return addr;
        }
    }
    return 0;
}

// ===== ГЛАВНЫЙ ПОИСК =====
void findRoomController() {
    if (g_searching) {
        addLog(@"⚠️ Уже ищу...");
        return;
    }
    g_searching = YES;
    addLog(@"\n🔍 ПОИСК ПО ID...");
    
    uintptr_t start = 0x100000000;
    uintptr_t end = 0x200000000;
    
    // 1. Находим свой ID
    uintptr_t myIdAddr = findIdAddress(MY_ID, start, end);
    if (!myIdAddr) {
        addLog(@"❌ Свой ID не найден!");
        g_searching = NO;
        return;
    }
    addLog([NSString stringWithFormat:@"✅ Свой ID: 0x%lx", myIdAddr]);
    
    // 2. Находим ID врага
    uintptr_t enemyIdAddr = findIdAddress(ENEMY_ID, start, end);
    if (!enemyIdAddr) {
        addLog(@"❌ ID врага не найден!");
        g_searching = NO;
        return;
    }
    addLog([NSString stringWithFormat:@"✅ Враг ID: 0x%lx", enemyIdAddr]);
    
    // 3. Начало структур
    uintptr_t myStruct = myIdAddr - 0x10;
    uintptr_t enemyStruct = enemyIdAddr - 0x10;
    addLog([NSString stringWithFormat:@"📦 Структура игрока: 0x%lx", myStruct]);
    addLog([NSString stringWithFormat:@"📦 Структура врага: 0x%lx", enemyStruct]);
    
    // 4. Читаем Team
    int myTeam = readInt(myStruct + 0x34);
    int enemyTeam = readInt(enemyStruct + 0x34);
    addLog([NSString stringWithFormat:@"   Team игрока: %d", myTeam]);
    addLog([NSString stringWithFormat:@"   Team врага: %d", enemyTeam]);
    
    // 5. Ищем RoomController (указатель на структуру игрока)
    uintptr_t roomCtrl = 0;
    uintptr_t playersArray = 0;
    
    for (uintptr_t addr = start; addr < start + 0x2000000; addr += 8) {
        if (readPtr(addr) == myStruct) {
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
        g_searching = NO;
        return;
    }
    
    // 6. Выводим всех игроков
    addLog(@"\n📋 ВСЕ ИГРОКИ В МАТЧЕ:");
    for (int i = 0; i < 32; i++) {
        uintptr_t p = readPtr(playersArray + i * 8);
        if (p == 0) break;
        int pid = readInt(p + 0x10);
        int pteam = readInt(p + 0x34);
        int pdead = readInt(p + 0x7A);
        NSString *marker = @"";
        if (pid == MY_ID) marker = @" ★ СВОЙ";
        if (pid == ENEMY_ID) marker = @" 👿 ВРАГ";
        addLog([NSString stringWithFormat:@"   [%d] 0x%lx | ID: %d | Team: %d | Dead: %d%@", i, p, pid, pteam, pdead, marker]);
    }
    
    // 7. Координаты (если найдем Transform)
    addLog(@"\n🔍 ИЩУ ПОЗИЦИИ...");
    
    // Ищем Transform через NetworkPlayer
    // NetworkPlayer находится по указателю из RoomController или из Players
    // Обычно NetworkPlayer + 0x38 = Transform, Transform + 0x20 = Vector3
    
    for (int i = 0; i < 32; i++) {
        uintptr_t p = readPtr(playersArray + i * 8);
        if (p == 0) break;
        
        // Пробуем найти NetworkPlayer для этого игрока
        // Поиск указателя на структуру игрока (QuarkRoomPlayer) в NetworkPlayer
        for (uintptr_t addr = start; addr < start + 0x2000000; addr += 8) {
            if (readPtr(addr + 0x1A8) == p) { // NetworkPlayer._quarkPlayer
                uintptr_t transform = readPtr(addr + 0x38); // NetworkPlayer._thisTransform
                if (transform > start && transform < end) {
                    float x = 0, y = 0, z = 0;
                    vm_size_t out = 0;
                    vm_read_overwrite(mach_task_self(), transform + 0x20, 12, (vm_address_t)&x, &out);
                    int pid = readInt(p + 0x10);
                    addLog([NSString stringWithFormat:@"   Игрок %d | X:%.1f Y:%.1f Z:%.1f", pid, x, y, z]);
                    break;
                }
            }
        }
    }
    
    addLog(@"\n✅ ГОТОВО!");
    g_searching = NO;
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
    
    CGFloat w = 340, h = 520;
    g_win = [[UIWindow alloc] initWithFrame:CGRectMake((key.bounds.size.width-w)/2, (key.bounds.size.height-h)/2, w, h)];
    g_win.windowLevel = UIWindowLevelAlert + 2;
    g_win.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    g_win.layer.cornerRadius = 20;
    g_win.layer.borderWidth = 2;
    g_win.layer.borderColor = UIColor.systemBlueColor.CGColor;
    g_win.hidden = NO;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 12, w, 30)];
    title.text = @"🎯 ESP FINDER";
    title.textColor = UIColor.systemBlueColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:18];
    [g_win addSubview:title];
    
    g_txt = [[UITextView alloc] initWithFrame:CGRectMake(12, 50, w-24, 360)];
    g_txt.backgroundColor = UIColor.blackColor;
    g_txt.textColor = UIColor.greenColor;
    g_txt.font = [UIFont fontWithName:@"Courier" size:11];
    g_txt.editable = NO;
    g_txt.selectable = YES;
    g_txt.layer.cornerRadius = 10;
    [g_win addSubview:g_txt];
    
    UIButton *searchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    searchBtn.frame = CGRectMake(15, 420, (w-45)/2, 42);
    [searchBtn setTitle:@"🔍 НАЙТИ" forState:UIControlStateNormal];
    searchBtn.backgroundColor = UIColor.systemBlueColor;
    [searchBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    searchBtn.layer.cornerRadius = 12;
    [searchBtn addTarget:nil action:@selector(onSearch) forControlEvents:UIControlEventTouchUpInside];
    [g_win addSubview:searchBtn];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(25 + (w-45)/2, 420, (w-45)/2, 42);
    [copyBtn setTitle:@"📋 КОПИ" forState:UIControlStateNormal];
    copyBtn.backgroundColor = UIColor.systemGreenColor;
    [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 12;
    [copyBtn addTarget:nil action:@selector(onCopy) forControlEvents:UIControlEventTouchUpInside];
    [g_win addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w/2-50, 472, 100, 32);
    [closeBtn setTitle:@"ЗАКРЫТЬ" forState:UIControlStateNormal];
    closeBtn.backgroundColor = UIColor.systemRedColor;
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 8;
    [closeBtn addTarget:g_win action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
    [g_win addSubview:closeBtn];
    
    [g_win makeKeyAndVisible];
}

void onSearch() {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        findRoomController();
    });
}

void onCopy() {
    if (g_txt.text.length) {
        UIPasteboard.generalPasteboard.string = g_txt.text;
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
            g_log = nil;
            createWindow();
        };
    }
    return self;
}
@end

static App *g_app = nil;

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_app = [[App alloc] init];
        NSLog(@"[ESP] Загружен");
    });
}
