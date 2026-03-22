#import <UIKit/UIKit.h>
#import <mach/mach.h>

// ===== ГЛОБАЛЬНЫЕ =====
static UIWindow *win = nil;
static UITextView *logView = nil;
static NSMutableString *logText = nil;
static BOOL isSearching = NO;
static NSMutableArray *g_idAddresses = nil;
static NSMutableArray *g_idValues = nil;
static NSMutableArray *g_candidates = nil;
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

void clearLog() {
    logText = nil;
    addLog(@"🗑 Лог очищен");
}

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

BOOL isValidPosition(float x, float y, float z) {
    if (x < -100 || x > 100) return NO;
    if (y < -100 || y > 100) return NO;
    if (z < -100 || z > 100) return NO;
    if (fabs(x) < 0.01 && fabs(y) < 0.01 && fabs(z) < 0.01) return NO;
    return YES;
}

// ===== БЫСТРЫЙ ПОИСК TRANSFORM (БЕЗ РЕКУРСИИ, ТОЛЬКО ПРЯМЫЕ УКАЗАТЕЛИ) =====
void findDirectTransforms(uintptr_t structStart) {
    g_candidates = [NSMutableArray array];
    
    addLogF(@"\n📊 ПОИСК TRANSFORM В СТРУКТУРЕ 0x%lx", structStart);
    addLog(@"=================================");
    
    int found = 0;
    // Проверяем только прямые указатели в структуре (от +0x20 до +0x100)
    for (int offset = 0x20; offset <= 0x100; offset += 8) {
        uintptr_t ptr = safeReadPtr(structStart + offset);
        if (ptr == 0) continue;
        if (ptr < 0x100000000 || ptr > 0x200000000) continue;
        
        // Проверяем координаты по адресу ptr + 0x20
        float x = safeReadFloat(ptr + 0x20);
        float y = safeReadFloat(ptr + 0x24);
        float z = safeReadFloat(ptr + 0x28);
        
        if (isValidPosition(x, y, z)) {
            found++;
            addLogF(@"\n🔹 TRANSFORM %d: 0x%lx (смещение +0x%02X)", found, ptr, offset);
            addLogF(@"   📍 Координаты: X=%.2f Y=%.2f Z=%.2f", x, y, z);
            
            [g_candidates addObject:@{
                @"transform": @(ptr),
                @"coordAddr": @(ptr + 0x20),
                @"x": @(x),
                @"y": @(y),
                @"z": @(z),
                @"offset": @(offset)
            }];
        }
    }
    
    if (found == 0) {
        addLog(@"❌ Transform не найден в прямых указателях структуры");
    } else {
        addLogF(@"\n✅ Найдено Transform: %d", found);
    }
}

// ===== ПРОВЕРКА КАНДИДАТОВ =====
void checkCandidates() {
    if (g_candidates.count == 0) {
        addLog(@"⚠️ Нет кандидатов. Сначала нажмите ОТСЕЯТЬ");
        return;
    }
    
    addLog(@"\n🔍 ПРОВЕРКА (ПОСЛЕ ДВИЖЕНИЯ)");
    addLog(@"=================================");
    
    int changedCount = 0;
    
    for (int i = 0; i < g_candidates.count; i++) {
        NSDictionary *c = g_candidates[i];
        uintptr_t coordAddr = [c[@"coordAddr"] unsignedLongLongValue];
        float oldX = [c[@"x"] floatValue];
        float oldY = [c[@"y"] floatValue];
        float oldZ = [c[@"z"] floatValue];
        
        float newX = safeReadFloat(coordAddr);
        float newY = safeReadFloat(coordAddr + 4);
        float newZ = safeReadFloat(coordAddr + 8);
        
        addLogF(@"\n📍 КАНДИДАТ %d:", i+1);
        addLogF(@"   Transform: 0x%lx", [c[@"transform"] unsignedLongLongValue]);
        addLogF(@"   Было: X=%.2f Y=%.2f Z=%.2f", oldX, oldY, oldZ);
        addLogF(@"   Стало: X=%.2f Y=%.2f Z=%.2f", newX, newY, newZ);
        
        if (fabs(newX - oldX) > 0.1 || fabs(newY - oldY) > 0.1 || fabs(newZ - oldZ) > 0.1) {
            addLog(@"   ✅ ИЗМЕНИЛИСЬ! Это координаты игрока.");
            changedCount++;
        } else {
            addLog(@"   ⚠️ НЕ ИЗМЕНИЛИСЬ.");
        }
    }
    
    addLogF(@"\n✅ Изменилось: %d из %lu", changedCount, (unsigned long)g_candidates.count);
    
    if (changedCount == 1) {
        for (NSDictionary *c in g_candidates) {
            uintptr_t coordAddr = [c[@"coordAddr"] unsignedLongLongValue];
            float newX = safeReadFloat(coordAddr);
            float newY = safeReadFloat(coordAddr + 4);
            float newZ = safeReadFloat(coordAddr + 8);
            float oldX = [c[@"x"] floatValue];
            if (fabs(newX - oldX) > 0.1) {
                addLogF(@"\n🎯 НАЙДЕНЫ КООРДИНАТЫ ИГРОКА!");
                addLogF(@"   Transform: 0x%lx", [c[@"transform"] unsignedLongLongValue]);
                addLogF(@"   Координаты: X=%.2f Y=%.2f Z=%.2f", newX, newY, newZ);
                break;
            }
        }
    }
}

// ===== ПОИСК ID =====
void findStructure() {
    if (isSearching) {
        addLog(@"⏳ Уже ищу");
        return;
    }
    isSearching = YES;
    addLog(@"🔍 ПОИСК ID");
    addLog(@"=================================");
    
    g_idAddresses = [NSMutableArray array];
    g_idValues = [NSMutableArray array];
    int foundMy = 0;
    
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
    
    addLog(@"📊 Диапазон: 0x100000000 - 0x200000000");
    
    while (1) {
        kern_return_t kr = vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;
        
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE) &&
            addr >= 0x100000000 && addr <= 0x200000000) {
            
            for (uintptr_t page = addr; page < addr + size; page += 0x1000) {
                uintptr_t pageSize = (page + 0x1000 > addr + size) ? (addr + size - page) : 0x1000;
                if (pageSize < 4) continue;
                
                vm_size_t read = 0;
                kern_return_t kr2 = vm_read_overwrite(task, page, pageSize, (vm_address_t)buffer, &read);
                if (kr2 != KERN_SUCCESS || read < 4) continue;
                
                for (uintptr_t offset = 0; offset + 4 <= pageSize; offset += 8) {
                    int val = *(int*)(buffer + offset);
                    
                    if (val == g_targetID && foundMy < 200) {
                        foundMy++;
                        uintptr_t idAddr = page + offset;
                        [g_idAddresses addObject:@(idAddr)];
                        [g_idValues addObject:@(val)];
                        addLogF(@"[%d] 0x%lx", foundMy, idAddr);
                    }
                }
            }
        }
        
        addr += size;
        if (addr > 0x200000000) break;
    }
    
    free(buffer);
    
    addLogF(@"\n✅ Найдено ID: %lu", (unsigned long)g_idAddresses.count);
    addLog(@"✅ ГОТОВО");
    isSearching = NO;
}

// ===== ОТСЕИВАНИЕ =====
void filterByDeath() {
    if (g_idAddresses.count == 0) {
        addLog(@"⚠️ Нет ID. Сначала нажмите ПОИСК");
        return;
    }
    
    addLog(@"🔍 ОТСЕИВАНИЕ (ИЩЕМ -1)");
    addLog(@"=================================");
    
    NSMutableArray *newAddresses = [NSMutableArray array];
    int foundMinusOne = 0;
    uintptr_t foundStruct = 0;
    
    for (int i = 0; i < g_idAddresses.count; i++) {
        uintptr_t addr = [g_idAddresses[i] unsignedLongLongValue];
        int newVal = safeReadInt(addr);
        
        if (newVal == -1) {
            [newAddresses addObject:@(addr)];
            foundMinusOne++;
            foundStruct = addr - 0x10;
            addLogF(@"   ✅ -1: 0x%lx", addr);
            break; // Нашли первый -1, выходим
        }
    }
    
    g_idAddresses = newAddresses;
    
    addLogF(@"\n✅ Найдено -1: %d", foundMinusOne);
    
    if (foundMinusOne == 1 && foundStruct != 0) {
        addLogF(@"\n🎯 СТРУКТУРА: 0x%lx", foundStruct);
        findDirectTransforms(foundStruct);
    } else {
        addLog(@"⚠️ Нет адресов, ставших -1.");
    }
    
    addLog(@"✅ ГОТОВО");
}

// ===== КЛАСС-ОБРАБОТЧИК =====
@interface MenuHandler : NSObject
+ (void)onSearch;
+ (void)onFilter;
+ (void)onCheck;
+ (void)onClear;
+ (void)onCopy;
+ (void)onClose;
@end

@implementation MenuHandler
+ (void)onSearch {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        findStructure();
    });
}
+ (void)onFilter {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        filterByDeath();
    });
}
+ (void)onCheck {
    checkCandidates();
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

// ===== МЕНЮ (УМЕНЬШЕННОЕ) =====
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
    
    CGFloat w = 260, h = 280;
    CGFloat x = (key.bounds.size.width - w) / 2;
    CGFloat y = (key.bounds.size.height - h) / 2;
    
    win = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, w, h)];
    win.windowLevel = UIWindowLevelAlert + 2;
    win.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    win.layer.cornerRadius = 12;
    win.layer.borderWidth = 1;
    win.layer.borderColor = UIColor.systemBlueColor.CGColor;
    win.hidden = NO;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, w, 24)];
    title.text = @"🎯 ESP SCANNER";
    title.textColor = UIColor.systemBlueColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [win addSubview:title];
    
    logView = [[UITextView alloc] initWithFrame:CGRectMake(6, 38, w-12, 150)];
    logView.backgroundColor = UIColor.blackColor;
    logView.textColor = UIColor.greenColor;
    logView.font = [UIFont fontWithName:@"Courier" size:9];
    logView.editable = NO;
    logView.layer.cornerRadius = 6;
    [win addSubview:logView];
    
    CGFloat btnW = (w - 25) / 2;
    
    UIButton *searchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    searchBtn.frame = CGRectMake(10, 195, btnW, 32);
    [searchBtn setTitle:@"🔍 ПОИСК" forState:UIControlStateNormal];
    searchBtn.backgroundColor = UIColor.systemBlueColor;
    [searchBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    searchBtn.layer.cornerRadius = 6;
    [searchBtn addTarget:[MenuHandler class] action:@selector(onSearch) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:searchBtn];
    
    UIButton *filterBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    filterBtn.frame = CGRectMake(15 + btnW, 195, btnW, 32);
    [filterBtn setTitle:@"💀 ОТСЕЯТЬ" forState:UIControlStateNormal];
    filterBtn.backgroundColor = UIColor.systemRedColor;
    [filterBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    filterBtn.layer.cornerRadius = 6;
    [filterBtn addTarget:[MenuHandler class] action:@selector(onFilter) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:filterBtn];
    
    UIButton *checkBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    checkBtn.frame = CGRectMake(10, 232, btnW, 30);
    [checkBtn setTitle:@"📍 ПРОВЕРИТЬ" forState:UIControlStateNormal];
    checkBtn.backgroundColor = UIColor.systemPurpleColor;
    [checkBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    checkBtn.layer.cornerRadius = 6;
    [checkBtn addTarget:[MenuHandler class] action:@selector(onCheck) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:checkBtn];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(15 + btnW, 232, btnW, 30);
    [copyBtn setTitle:@"📋 КОПИ" forState:UIControlStateNormal];
    copyBtn.backgroundColor = UIColor.systemGreenColor;
    [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 6;
    [copyBtn addTarget:[MenuHandler class] action:@selector(onCopy) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w/2-35, 267, 70, 26);
    [closeBtn setTitle:@"❌ ЗАКРЫТЬ" forState:UIControlStateNormal];
    closeBtn.backgroundColor = UIColor.systemGrayColor;
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 5;
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:12];
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
