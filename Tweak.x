#import <UIKit/UIKit.h>
#import <mach/mach.h>

// ===== ГЛОБАЛЬНЫЕ =====
static UIWindow *win = nil;
static UITextView *logView = nil;
static NSMutableString *logText = nil;
static BOOL isSearching = NO;
static NSDate *searchStartTime = nil;

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

// ===== ПРОВЕРКА, ПОХОЖЕ ЛИ НА КООРДИНАТЫ ИГРОКА =====
BOOL isValidPlayerPosition(float x, float y, float z) {
    // Координаты в разумных пределах (-100..100) и не нулевые
    if (x < -100 || x > 100) return NO;
    if (y < -100 || y > 100) return NO;
    if (z < -100 || z > 100) return NO;
    if (fabs(x) < 0.01 && fabs(y) < 0.01 && fabs(z) < 0.01) return NO;
    return YES;
}

// ===== ПОИСК TRANSFORM В СТРУКТУРЕ =====
uintptr_t findTransformInStruct(uintptr_t structStart, int *foundOffset) {
    // Проверяем смещения от +0x20 до +0x80 с шагом 8
    for (int offset = 0x20; offset <= 0x80; offset += 8) {
        uintptr_t transformPtr = safeReadPtr(structStart + offset);
        if (transformPtr == 0) continue;
        if (transformPtr < 0x100000000 || transformPtr > 0x300000000) continue;
        
        // Проверяем координаты по адресу transformPtr + 0x20
        float x = safeReadFloat(transformPtr + 0x20);
        float y = safeReadFloat(transformPtr + 0x24);
        float z = safeReadFloat(transformPtr + 0x28);
        
        if (isValidPlayerPosition(x, y, z)) {
            if (foundOffset) *foundOffset = offset;
            return transformPtr;
        }
    }
    return 0;
}

// ===== АВТОПОИСК ID, СТРУКТУРЫ, TRANSFORM И КООРДИНАТ =====
void autoFindAll() {
    if (isSearching) {
        addLog(@"⏳ Уже ищу");
        return;
    }
    isSearching = YES;
    searchStartTime = [NSDate date];
    addLog(@"🔍 АВТОПОИСК ID, TRANSFORM И КООРДИНАТ");
    addLog(@"=================================");
    
    int myID = 71068432;
    int enemyID = 55471766;
    int foundMy = 0, foundEnemy = 0;
    int regionsChecked = 0;
    
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
    
    addLog(@"📊 Диапазон: 0x140000000 - 0x170000000");
    
    while (1) {
        kern_return_t kr = vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;
        
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE) &&
            addr >= 0x140000000 && addr <= 0x170000000) {
            
            regionsChecked++;
            
            for (uintptr_t page = addr; page < addr + size; page += 0x1000) {
                uintptr_t pageSize = (page + 0x1000 > addr + size) ? (addr + size - page) : 0x1000;
                if (pageSize < 4) continue;
                
                vm_size_t read = 0;
                kern_return_t kr2 = vm_read_overwrite(task, page, pageSize, (vm_address_t)buffer, &read);
                if (kr2 != KERN_SUCCESS || read < 4) continue;
                
                for (uintptr_t offset = 0; offset + 4 <= pageSize; offset += 8) {
                    int val = *(int*)(buffer + offset);
                    
                    if (val == myID && foundMy < 20) {
                        foundMy++;
                        uintptr_t structStart = (page + offset) - 0x10;
                        int team = safeReadInt(structStart + 0x34);
                        int dead = safeReadInt(structStart + 0x7A);
                        
                        if (team == 0 || team == 1) {
                            addLog([NSString stringWithFormat:@"\n🔹 [СВОЙ %d] Структура: 0x%lx", foundMy, structStart]);
                            addLog([NSString stringWithFormat:@"   ID: %d, Team: %d, Dead: %d", myID, team, dead]);
                            
                            // Ищем Transform
                            int transformOffset = 0;
                            uintptr_t transform = findTransformInStruct(structStart, &transformOffset);
                            
                            if (transform != 0) {
                                addLog([NSString stringWithFormat:@"   ✅ Transform найден по смещению +0x%02X: 0x%lx", transformOffset, transform]);
                                
                                float x = safeReadFloat(transform + 0x20);
                                float y = safeReadFloat(transform + 0x24);
                                float z = safeReadFloat(transform + 0x28);
                                addLog([NSString stringWithFormat:@"   📍 КООРДИНАТЫ: X=%.2f Y=%.2f Z=%.2f", x, y, z]);
                            } else {
                                addLog([NSString stringWithFormat:@"   ❌ Transform не найден в структуре"]);
                            }
                        }
                    }
                    else if (val == enemyID && foundEnemy < 20) {
                        foundEnemy++;
                        uintptr_t structStart = (page + offset) - 0x10;
                        int team = safeReadInt(structStart + 0x34);
                        int dead = safeReadInt(structStart + 0x7A);
                        
                        if (team == 0 || team == 1) {
                            addLog([NSString stringWithFormat:@"\n🔹 [ВРАГ %d] Структура: 0x%lx", foundEnemy, structStart]);
                            addLog([NSString stringWithFormat:@"   ID: %d, Team: %d, Dead: %d", enemyID, team, dead]);
                            
                            int transformOffset = 0;
                            uintptr_t transform = findTransformInStruct(structStart, &transformOffset);
                            
                            if (transform != 0) {
                                addLog([NSString stringWithFormat:@"   ✅ Transform найден по смещению +0x%02X: 0x%lx", transformOffset, transform]);
                                
                                float x = safeReadFloat(transform + 0x20);
                                float y = safeReadFloat(transform + 0x24);
                                float z = safeReadFloat(transform + 0x28);
                                addLog([NSString stringWithFormat:@"   📍 КООРДИНАТЫ: X=%.2f Y=%.2f Z=%.2f", x, y, z]);
                            } else {
                                addLog([NSString stringWithFormat:@"   ❌ Transform не найден в структуре"]);
                            }
                        }
                    }
                }
            }
        }
        
        addr += size;
        if (addr > 0x170000000) break;
    }
    
    free(buffer);
    
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:searchStartTime];
    addLog([NSString stringWithFormat:@"\n✅ Регионов: %d, Время: %.0f сек", regionsChecked, elapsed]);
    addLog([NSString stringWithFormat:@"✅ Найдено СВОИХ: %d, ВРАГОВ: %d", foundMy, foundEnemy]);
    addLog(@"✅ ГОТОВО");
    isSearching = NO;
}

// ===== КЛАСС-ОБРАБОТЧИК =====
@interface MenuHandler : NSObject
+ (void)onSearch;
+ (void)onClear;
+ (void)onCopy;
+ (void)onClose;
@end

@implementation MenuHandler
+ (void)onSearch {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        autoFindAll();
    });
}
+ (void)onClear {
    clearLog();
}
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
    
    CGFloat w = 280, h = 380;
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
    title.text = @"🎯 ESP SCANNER";
    title.textColor = UIColor.systemBlueColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [win addSubview:title];
    
    logView = [[UITextView alloc] initWithFrame:CGRectMake(8, 42, w-16, 240)];
    logView.backgroundColor = UIColor.blackColor;
    logView.textColor = UIColor.greenColor;
    logView.font = [UIFont fontWithName:@"Courier" size:10];
    logView.editable = NO;
    logView.layer.cornerRadius = 6;
    [win addSubview:logView];
    
    UIButton *searchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    searchBtn.frame = CGRectMake(15, 295, (w-45)/2, 38);
    [searchBtn setTitle:@"🔍 АВТОПОИСК" forState:UIControlStateNormal];
    searchBtn.backgroundColor = UIColor.systemBlueColor;
    [searchBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    searchBtn.layer.cornerRadius = 8;
    [searchBtn addTarget:[MenuHandler class] action:@selector(onSearch) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:searchBtn];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(25 + (w-45)/2, 295, (w-45)/2, 38);
    [copyBtn setTitle:@"📋 КОПИ" forState:UIControlStateNormal];
    copyBtn.backgroundColor = UIColor.systemGreenColor;
    [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 8;
    [copyBtn addTarget:[MenuHandler class] action:@selector(onCopy) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:copyBtn];
    
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(15, 340, (w-45)/2, 34);
    [clearBtn setTitle:@"🗑 ОЧИСТИТЬ" forState:UIControlStateNormal];
    clearBtn.backgroundColor = UIColor.systemOrangeColor;
    [clearBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    clearBtn.layer.cornerRadius = 6;
    [clearBtn addTarget:[MenuHandler class] action:@selector(onClear) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:clearBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(25 + (w-45)/2, 340, (w-45)/2, 34);
    [closeBtn setTitle:@"❌ ЗАКРЫТЬ" forState:UIControlStateNormal];
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
