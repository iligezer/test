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
int readInt(uintptr_t addr) {
    int val = 0;
    vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, NULL);
    return val;
}

uintptr_t readPtr(uintptr_t addr) {
    uintptr_t val = 0;
    vm_read_overwrite(mach_task_self(), addr, 8, (vm_address_t)&val, NULL);
    return val;
}

float readFloat(uintptr_t addr) {
    float val = 0;
    vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, NULL);
    return val;
}

// ===== АНАЛИЗ НАЙДЕННЫХ ИГРОКОВ =====
void analyzePlayers(uintptr_t *playerAddrs, int playerCount) {
    addLog(@"\n📊 АНАЛИЗ СТРУКТУР ИГРОКОВ");
    addLog(@"=================================");
    
    int validPlayers = 0;
    
    for (int i = 0; i < playerCount; i++) {
        uintptr_t structStart = playerAddrs[i];
        if (structStart == 0) continue;
        
        // Читаем ID
        int id = readInt(structStart + 0x10);
        int team = readInt(structStart + 0x34);
        int dead = readInt(structStart + 0x7A);
        
        // Читаем указатель на имя
        uintptr_t namePtr = readPtr(structStart + 0x18);
        
        // Читаем Transform
        uintptr_t transform = readPtr(structStart + 0x38);
        
        addLog([NSString stringWithFormat:@"\n🔹 ИГРОК %d", i+1]);
        addLog([NSString stringWithFormat:@"   Структура: 0x%lx", structStart]);
        addLog([NSString stringWithFormat:@"   ID: %d", id]);
        addLog([NSString stringWithFormat:@"   Team: %d %@", team, team == 0 ? @"(СВОЙ)" : @"(ВРАГ)"]);
        addLog([NSString stringWithFormat:@"   Dead: %d %@", dead, dead == 0 ? @"(ЖИВ)" : @"(МЕРТВ)"]);
        
        // Пытаемся прочитать имя
        if (namePtr != 0) {
            char nameBuf[64] = {0};
            vm_read_overwrite(mach_task_self(), namePtr, 32, (vm_address_t)nameBuf, NULL);
            NSString *name = [NSString stringWithUTF8String:nameBuf];
            if (name.length > 0) {
                addLog([NSString stringWithFormat:@"   Имя: %@", name]);
            } else {
                addLog([NSString stringWithFormat:@"   Имя: (не читается)"]);
            }
        }
        
        // Анализируем Transform и координаты
        if (transform != 0) {
            addLog([NSString stringWithFormat:@"   Transform: 0x%lx", transform]);
            
            // Читаем позицию (смещение 0x20)
            float x = readFloat(transform + 0x20);
            float y = readFloat(transform + 0x24);
            float z = readFloat(transform + 0x28);
            
            addLog([NSString stringWithFormat:@"   📍 ПОЗИЦИЯ: X=%.2f Y=%.2f Z=%.2f", x, y, z]);
            
            // Проверяем, что координаты похожи на игрока (не нулевые)
            if (fabs(x) > 0.1 || fabs(y) > 0.1 || fabs(z) > 0.1) {
                validPlayers++;
            }
        } else {
            addLog([NSString stringWithFormat:@"   Transform: 0 (не инициализирован)"]);
        }
    }
    
    addLog([NSString stringWithFormat:@"\n✅ Всего игроков: %d, Активных: %d", playerCount, validPlayers]);
}

// ===== ПОЛНЫЙ СКАН + АНАЛИЗ =====
void fullScanAndAnalyze() {
    if (isSearching) {
        addLog(@"⏳ Поиск уже идет...");
        return;
    }
    isSearching = YES;
    searchStartTime = [NSDate date];
    addLog(@"🔍 ПОЛНЫЙ СКАН + АНАЛИЗ");
    addLog(@"=================================");
    
    int myID = 71068432;
    int enemyID = 55471766;
    
    // Массив для хранения найденных структур
    uintptr_t foundStructures[200];
    int foundCount = 0;
    
    task_t task = mach_task_self();
    vm_address_t addr = 0;
    vm_size_t size = 0;
    struct vm_region_basic_info_64 info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name = MACH_PORT_NULL;
    
    uint8_t *buffer = malloc(0x1000);
    if (!buffer) {
        addLog(@"❌ Ошибка выделения памяти");
        isSearching = NO;
        return;
    }
    
    addLog(@"📊 Сканирование памяти...");
    
    while (1) {
        kern_return_t kr = vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;
        
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE) &&
            addr >= 0x100000000 && addr <= 0x300000000) {
            
            uintptr_t regionStart = addr;
            uintptr_t regionEnd = addr + size;
            
            for (uintptr_t page = regionStart; page < regionEnd; page += 0x1000) {
                uintptr_t pageSize = (page + 0x1000 > regionEnd) ? (regionEnd - page) : 0x1000;
                if (pageSize < 4) continue;
                
                vm_size_t read = 0;
                kern_return_t kr2 = vm_read_overwrite(task, page, pageSize, (vm_address_t)buffer, &read);
                if (kr2 != KERN_SUCCESS || read < 4) continue;
                
                for (uintptr_t offset = 0; offset + 4 <= pageSize && foundCount < 200; offset += 8) {
                    int val = *(int*)(buffer + offset);
                    
                    if (val == myID || val == enemyID) {
                        uintptr_t absAddr = page + offset;
                        uintptr_t structStart = absAddr - 0x10;
                        
                        // Проверяем, что Team в пределах 0-1
                        int team = 0;
                        vm_read_overwrite(task, structStart + 0x34, 4, (vm_address_t)&team, &read);
                        
                        if (team == 0 || team == 1) {
                            // Проверяем, что Dead в пределах 0-100
                            int dead = 0;
                            vm_read_overwrite(task, structStart + 0x7A, 4, (vm_address_t)&dead, &read);
                            
                            if (dead >= 0 && dead <= 100) {
                                // Добавляем в массив, если еще нет такого адреса
                                BOOL duplicate = NO;
                                for (int i = 0; i < foundCount; i++) {
                                    if (foundStructures[i] == structStart) {
                                        duplicate = YES;
                                        break;
                                    }
                                }
                                if (!duplicate) {
                                    foundStructures[foundCount++] = structStart;
                                }
                            }
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
    addLog([NSString stringWithFormat:@"\n✅ Найдено структур: %d, Время: %.0f сек", foundCount, elapsed]);
    
    if (foundCount > 0) {
        analyzePlayers(foundStructures, foundCount);
    } else {
        addLog(@"⚠️ Ничего не найдено");
    }
    
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
        fullScanAndAnalyze();
    });
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

// ===== СОЗДАНИЕ МЕНЮ =====
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
    
    CGFloat w = 300, h = 420;
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
    title.text = @"🎯 ESP SCANNER + ANALYZER";
    title.textColor = UIColor.systemBlueColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [win addSubview:title];
    
    logView = [[UITextView alloc] initWithFrame:CGRectMake(8, 42, w-16, 270)];
    logView.backgroundColor = UIColor.blackColor;
    logView.textColor = UIColor.greenColor;
    logView.font = [UIFont fontWithName:@"Courier" size:10];
    logView.editable = NO;
    logView.layer.cornerRadius = 6;
    [win addSubview:logView];
    
    UIButton *searchBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    searchBtn.frame = CGRectMake(8, 325, (w-30)/3, 38);
    [searchBtn setTitle:@"🔍 СКАН" forState:UIControlStateNormal];
    searchBtn.backgroundColor = UIColor.systemBlueColor;
    [searchBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    searchBtn.layer.cornerRadius = 8;
    [searchBtn addTarget:[MenuHandler class] action:@selector(onSearch) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:searchBtn];
    
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(15 + (w-30)/3, 325, (w-30)/3, 38);
    [clearBtn setTitle:@"🗑 ОЧИСТИТЬ" forState:UIControlStateNormal];
    clearBtn.backgroundColor = UIColor.systemOrangeColor;
    [clearBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    clearBtn.layer.cornerRadius = 8;
    [clearBtn addTarget:[MenuHandler class] action:@selector(onClear) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:clearBtn];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(22 + (w-30)/3*2, 325, (w-30)/3, 38);
    [copyBtn setTitle:@"📋 КОПИ" forState:UIControlStateNormal];
    copyBtn.backgroundColor = UIColor.systemGreenColor;
    [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 8;
    [copyBtn addTarget:[MenuHandler class] action:@selector(onCopy) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w/2-40, 375, 80, 32);
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
        NSLog(@"[ESP] Scanner Ready");
    });
}
