#import <UIKit/UIKit.h>
#import <mach/mach.h>

// ===== ГЛОБАЛЬНЫЕ =====
static UIWindow *win = nil;
static UITextView *logView = nil;
static NSMutableString *logText = nil;
static BOOL isSearching = NO;
static NSDate *searchStartTime = nil;
static uintptr_t g_foundStructs[200];
static int g_structCount = 0;

void addLog(NSString *msg) {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendString:msg];
    [logText appendString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (logView) logView.text = logText;
    });
}

void clearLog() {
    logText = nil;
    addLog(@"🗑 Лог очищен");
}

int safeReadInt(uintptr_t addr) {
    if (addr == 0) return 0;
    @try {
        int val = 0;
        vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, NULL);
        return val;
    } @catch (NSException *e) {
        return 0;
    }
}

uintptr_t safeReadPtr(uintptr_t addr) {
    if (addr == 0) return 0;
    @try {
        uintptr_t val = 0;
        vm_read_overwrite(mach_task_self(), addr, 8, (vm_address_t)&val, NULL);
        return val;
    } @catch (NSException *e) {
        return 0;
    }
}

float safeReadFloat(uintptr_t addr) {
    if (addr == 0) return 0;
    @try {
        float val = 0;
        vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, NULL);
        return val;
    } @catch (NSException *e) {
        return 0;
    }
}

// ===== АВТОПОИСК КООРДИНАТ (ДИАПАЗОН 0x20 - 0x200) =====
void findPositionOffset(uintptr_t transform) {
    if (transform == 0) return;
    
    addLog([NSString stringWithFormat:@"\n🔍 Поиск координат в Transform 0x%lx:", transform]);
    
    int found = 0;
    for (int offset = 0x20; offset <= 0x200 && found < 10; offset += 4) {
        float x = safeReadFloat(transform + offset);
        float y = safeReadFloat(transform + offset + 4);
        float z = safeReadFloat(transform + offset + 8);
        
        // Координаты в диапазоне -100..100 и не нулевые
        if (x > -100 && x < 100 && y > -100 && y < 100 && z > -100 && z < 100 &&
            (fabs(x) > 0.01 || fabs(y) > 0.01 || fabs(z) > 0.01)) {
            addLog([NSString stringWithFormat:@"   ✅ 0x%02X: X=%.2f Y=%.2f Z=%.2f", offset, x, y, z]);
            found++;
        }
    }
    
    if (found == 0) {
        addLog(@"   ⚠️ Не найдено координат в диапазоне -100..100");
    }
}

// ===== АНАЛИЗ НАЙДЕННЫХ СТРУКТУР =====
void analyzeStructures() {
    if (g_structCount == 0) {
        addLog(@"⚠️ Нет структур. Сначала нажмите СКАН");
        return;
    }
    
    addLog(@"\n📊 АНАЛИЗ КООРДИНАТ");
    addLog(@"=================================");
    
    int validCount = 0;
    
    for (int i = 0; i < g_structCount; i++) {
        uintptr_t s = g_foundStructs[i];
        if (s == 0) continue;
        
        int id = safeReadInt(s + 0x10);
        int team = safeReadInt(s + 0x34);
        int dead = safeReadInt(s + 0x7A);
        
        if (id == 0) continue;
        if (team != 0 && team != 1) continue;
        if (dead < 0 || dead > 100) continue;
        
        validCount++;
        addLog([NSString stringWithFormat:@"\n🔹 ИГРОК %d", validCount]);
        addLog([NSString stringWithFormat:@"   Структура: 0x%lx", s]);
        addLog([NSString stringWithFormat:@"   ID: %d", id]);
        addLog([NSString stringWithFormat:@"   Team: %d %@", team, team == 0 ? @"(СВОЙ)" : @"(ВРАГ)"]);
        addLog([NSString stringWithFormat:@"   Dead: %d %@", dead, dead == 0 ? @"(ЖИВ)" : @"(МЕРТВ)"]);
        
        uintptr_t transform = safeReadPtr(s + 0x38);
        
        if (transform != 0) {
            addLog([NSString stringWithFormat:@"   Transform: 0x%lx", transform]);
            
            // Проверяем стандартное смещение
            float x = safeReadFloat(transform + 0x20);
            float y = safeReadFloat(transform + 0x24);
            float z = safeReadFloat(transform + 0x28);
            
            if (x > -100 && x < 100 && y > -100 && y < 100 && z > -100 && z < 100 &&
                (fabs(x) > 0.01 || fabs(y) > 0.01 || fabs(z) > 0.01)) {
                addLog([NSString stringWithFormat:@"   📍 ПОЗИЦИЯ (0x20): X=%.2f Y=%.2f Z=%.2f", x, y, z]);
            } else {
                addLog(@"   ⚠️ Смещение 0x20: координаты некорректны, ищу другие...");
                findPositionOffset(transform);
            }
        } else {
            addLog([NSString stringWithFormat:@"   Transform: 0 (не найден)"]);
        }
    }
    
    addLog([NSString stringWithFormat:@"\n✅ Всего игроков: %d", validCount]);
}

// ===== ПОИСК ID (РАБОЧАЯ ВЕРСИЯ) =====
void searchIDs() {
    if (isSearching) {
        addLog(@"⏳ Уже ищу");
        return;
    }
    isSearching = YES;
    searchStartTime = [NSDate date];
    addLog(@"🔍 ПОИСК ID 71068432 И 55471766");
    addLog(@"=================================");
    
    int myID = 71068432;
    int enemyID = 55471766;
    int foundMy = 0, foundEnemy = 0;
    int regionCount = 0;
    g_structCount = 0;
    
    task_t task = mach_task_self();
    vm_address_t addr = 0;
    vm_size_t size = 0;
    struct vm_region_basic_info_64 info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name = MACH_PORT_NULL;
    
    uint8_t *buffer = malloc(0x1000);
    if (!buffer) {
        addLog(@"❌ Ошибка памяти");
        isSearching = NO;
        return;
    }
    
    addLog(@"📊 Сканирование...");
    
    while (1) {
        kern_return_t kr = vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;
        
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE) &&
            addr >= 0x100000000 && addr <= 0x300000000) {
            
            regionCount++;
            
            for (uintptr_t page = addr; page < addr + size; page += 0x1000) {
                uintptr_t pageSize = (page + 0x1000 > addr + size) ? (addr + size - page) : 0x1000;
                if (pageSize < 4) continue;
                
                vm_size_t read = 0;
                kern_return_t kr2 = vm_read_overwrite(task, page, pageSize, (vm_address_t)buffer, &read);
                if (kr2 != KERN_SUCCESS || read < 4) continue;
                
                for (uintptr_t offset = 0; offset + 4 <= pageSize; offset += 8) {
                    int val = *(int*)(buffer + offset);
                    
                    if (val == myID && foundMy < 50) {
                        foundMy++;
                        uintptr_t structStart = (page + offset) - 0x10;
                        int team = safeReadInt(structStart + 0x34);
                        int dead = safeReadInt(structStart + 0x7A);
                        if (team == 0 || team == 1) {
                            addLog([NSString stringWithFormat:@"[СВОЙ %d] 0x%lx Team:%d Dead:%d", foundMy, structStart, team, dead]);
                            g_foundStructs[g_structCount++] = structStart;
                        }
                    }
                    else if (val == enemyID && foundEnemy < 50) {
                        foundEnemy++;
                        uintptr_t structStart = (page + offset) - 0x10;
                        int team = safeReadInt(structStart + 0x34);
                        int dead = safeReadInt(structStart + 0x7A);
                        if (team == 0 || team == 1) {
                            addLog([NSString stringWithFormat:@"[ВРАГ %d] 0x%lx Team:%d Dead:%d", foundEnemy, structStart, team, dead]);
                            g_foundStructs[g_structCount++] = structStart;
                        }
                    }
                }
            }
        }
        
        addr += size;
        if (addr > 0x300000000) break;
    }
    
    free(buffer);
    
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:searchStartTime];
    addLog([NSString stringWithFormat:@"\n✅ Регионов: %d, Время: %.0f сек", regionCount, elapsed]);
    addLog([NSString stringWithFormat:@"✅ СВОИХ: %d, ВРАГОВ: %d", foundMy, foundEnemy]);
    addLog([NSString stringWithFormat:@"✅ Сохранено структур: %d", g_structCount]);
    addLog(@"✅ ГОТОВО");
    isSearching = NO;
}

// ===== КЛАСС-ОБРАБОТЧИК =====
@interface MenuHandler : NSObject
+ (void)onSearch;
+ (void)onAnalyze;
+ (void)onClear;
+ (void)onCopy;
+ (void)onClose;
@end

@implementation MenuHandler
+ (void)onSearch {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        searchIDs();
    });
}
+ (void)onAnalyze {
    analyzeStructures();
}
+ (void)onClear { clearLog(); }
+ (void)onCopy {
    if (logView && logView.text.length > 0) {
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
    
    CGFloat w = 280;
    CGFloat h = 380;
    CGFloat x = (key.bounds.size.width - w) / 2;
    CGFloat y = (key.bounds.size.height - h) / 2;
    
    win = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, w, h)];
    win.windowLevel = UIWindowLevelAlert + 2;
    win.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    win.layer.cornerRadius = 12;
    win.layer.borderWidth = 1;
    win.layer.borderColor = UIColor.systemBlueColor.CGColor;
    win.hidden = NO;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 6, w, 24)];
    title.text = @"🎯 ESP SCANNER";
    title.textColor = UIColor.systemBlueColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [win addSubview:title];
    
    logView = [[UITextView alloc] initWithFrame:CGRectMake(6, 36, w-12, 230)];
    logView.backgroundColor = UIColor.blackColor;
    logView.textColor = UIColor.greenColor;
    logView.font = [UIFont fontWithName:@"Courier" size:10];
    logView.editable = NO;
    logView.layer.cornerRadius = 6;
    [win addSubview:logView];
    
    CGFloat btnW = (w - 30) / 2;
    
    UIButton *searchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    searchBtn.frame = CGRectMake(10, 275, btnW, 34);
    [searchBtn setTitle:@"🔍 СКАН" forState:UIControlStateNormal];
    searchBtn.backgroundColor = UIColor.systemBlueColor;
    [searchBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    searchBtn.layer.cornerRadius = 6;
    [searchBtn addTarget:[MenuHandler class] action:@selector(onSearch) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:searchBtn];
    
    UIButton *analyzeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    analyzeBtn.frame = CGRectMake(20 + btnW, 275, btnW, 34);
    [analyzeBtn setTitle:@"📍 АНАЛИЗ" forState:UIControlStateNormal];
    analyzeBtn.backgroundColor = UIColor.systemPurpleColor;
    [analyzeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    analyzeBtn.layer.cornerRadius = 6;
    [analyzeBtn addTarget:[MenuHandler class] action:@selector(onAnalyze) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:analyzeBtn];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(10, 315, btnW, 34);
    [copyBtn setTitle:@"📋 КОПИ" forState:UIControlStateNormal];
    copyBtn.backgroundColor = UIColor.systemGreenColor;
    [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 6;
    [copyBtn addTarget:[MenuHandler class] action:@selector(onCopy) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:copyBtn];
    
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(20 + btnW, 315, btnW, 34);
    [clearBtn setTitle:@"🗑 ОЧИСТИТЬ" forState:UIControlStateNormal];
    clearBtn.backgroundColor = UIColor.systemOrangeColor;
    [clearBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    clearBtn.layer.cornerRadius = 6;
    [clearBtn addTarget:[MenuHandler class] action:@selector(onClear) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:clearBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w/2-40, 355, 80, 28);
    [closeBtn setTitle:@"ЗАКРЫТЬ" forState:UIControlStateNormal];
    closeBtn.backgroundColor = UIColor.systemRedColor;
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 6;
    [closeBtn addTarget:[MenuHandler class] action:@selector(onClose) forControlEvents:UIControlEventTouchUpInside];
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
    self = [super initWithFrame:CGRectMake(sw-65, sh-85, 50, 50)];
    if (self) {
        self.backgroundColor = UIColor.systemBlueColor;
        self.layer.cornerRadius = 25;
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
    CGFloat h = 25;
    c.x = MAX(h, MIN(self.superview.bounds.size.width - h, c.x));
    c.y = MAX(h+50, MIN(self.superview.bounds.size.height - h-50, c.y));
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
        
        __weak typeof(self) weak = self;
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
        NSLog(@"[ESP] Ready");
    });
}
