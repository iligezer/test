#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== НАСТРОЙКИ ==========
#define MIN_COORD -50.0
#define MAX_COORD 50.0
#define NEARBY_OFFSET 0x50       // смещение для поиска копий (80 байт)
#define VALUE_TOLERANCE 10.0     // погрешность значений координат ±10
#define SCAN_LIMIT 1000000       // ограничение для теста

// ========== RVA ФУНКЦИЙ ==========
#define RVA_Camera_get_main         0x445BAF8
#define RVA_Camera_WorldToScreen    0x445AD5C

// ========== ТИПЫ ФУНКЦИЙ ==========
typedef void *(*t_Camera_get_main)();
typedef void *(*t_Camera_WorldToScreen)(void *camera, void *worldPos);

static t_Camera_get_main Camera_get_main = NULL;
static t_Camera_WorldToScreen Camera_WorldToScreen = NULL;

static NSMutableString *logText = nil;
static UIWindow *logWindow = nil;
static UIWindow *menuWindow = nil;
static UIButton *floatingButton = nil;
static NSMutableArray *players = nil;
static uint64_t baseAddr = 0;

// ========== МОДЕЛЬ ИГРОКА ==========
@interface PlayerCandidate : NSObject
@property (assign) uint64_t address;     // адрес X
@property (assign) float x, y, z;        // координаты
@property (assign) int copyCount;         // сколько копий найдено
@end

@implementation PlayerCandidate
- (NSString *)description {
    return [NSString stringWithFormat:@"📍(%.1f,%.1f,%.1f) @0x%llx [%d копий]",
            self.x, self.y, self.z, self.address, self.copyCount];
}
@end

// ========== ПЛАВАЮЩАЯ КНОПКА ==========
@class ButtonHandler;

@interface FloatingButton : UIButton
@end

@implementation FloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.backgroundColor = [UIColor systemBlueColor];
    self.layer.cornerRadius = frame.size.width/2;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 4);
    self.layer.shadowOpacity = 0.5;
    [self setTitle:@"🔍" forState:UIControlStateNormal];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:28];
    [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self addGestureRecognizer:pan];
    return self;
}

- (void)pan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    CGPoint c = self.center;
    c.x += t.x;
    c.y += t.y;
    c.x = MAX(30, MIN(c.x, UIScreen.mainScreen.bounds.size.width - 30));
    c.y = MAX(100, MIN(c.y, UIScreen.mainScreen.bounds.size.height - 100));
    self.center = c;
    [g setTranslation:CGPointZero inView:self.superview];
}

- (void)tapped {
    Class handler = NSClassFromString(@"ButtonHandler");
    if (handler) {
        [handler performSelector:@selector(showMenu)];
    }
}
@end

// ========== ОСНОВНАЯ ЛОГИКА ==========
@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)closeMenu;
+ (void)findPlayers;
+ (void)showAnalytics;
+ (void)addLog:(NSString*)text;
+ (void)showLog;
+ (void)closeLog;
+ (void)copyLog;
+ (uint64_t)getBaseAddress;
+ (UIWindow*)mainWindow;
+ (BOOL)isValidFloat:(float)f;
+ (BOOL)valuesMatch:(float)a with:(float)b tolerance:(float)tol;
@end

@implementation ButtonHandler

+ (UIWindow*)mainWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            for (UIWindow *w in ((UIWindowScene*)scene).windows)
                if (w.isKeyWindow) return w;
        }
    }
    return nil;
}

+ (uint64_t)getBaseAddress {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && (strstr(name, "ModernStrike") || strstr(name, "GameAssembly"))) {
            return (uint64_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

+ (BOOL)isValidFloat:(float)f {
    if (isnan(f)) return NO;
    if (isinf(f)) return NO;
    return YES;
}

+ (BOOL)valuesMatch:(float)a with:(float)b tolerance:(float)tol {
    return fabs(a - b) <= tol;
}

+ (void)showMenu {
    if (menuWindow) {
        menuWindow.hidden = NO;
        return;
    }
    
    CGFloat w = 280, h = 350;
    menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake((UIScreen.mainScreen.bounds.size.width-w)/2, (UIScreen.mainScreen.bounds.size.height-h)/2, w, h)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
    menuWindow.layer.cornerRadius = 20;
    menuWindow.layer.borderWidth = 2;
    menuWindow.layer.borderColor = UIColor.systemBlueColor.CGColor;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, w, 30)];
    title.text = @"🔍 PLAYER SCANNER";
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:22];
    [menuWindow addSubview:title];
    
    NSArray *btns = @[
        @{@"title":@"🎯 НАЙТИ ИГРОКОВ", @"color":UIColor.systemBlueColor, @"sel":@"findPlayers"},
        @{@"title":@"📊 АНАЛИТИКА", @"color":UIColor.systemPurpleColor, @"sel":@"showAnalytics"},
        @{@"title":@"📋 ПОКАЗАТЬ ЛОГ", @"color":UIColor.systemOrangeColor, @"sel":@"showLog"},
        @{@"title":@"✖️ ЗАКРЫТЬ", @"color":UIColor.systemRedColor, @"sel":@"closeMenu"}
    ];
    
    int y = 70;
    for (NSDictionary *b in btns) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, y, w-40, 45);
        btn.backgroundColor = b[@"color"];
        btn.layer.cornerRadius = 12;
        [btn setTitle:b[@"title"] forState:UIControlStateNormal];
        [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [btn addTarget:self action:NSSelectorFromString(b[@"sel"]) forControlEvents:UIControlEventTouchUpInside];
        [menuWindow addSubview:btn];
        y += 55;
    }
    
    [menuWindow makeKeyAndVisible];
}

+ (void)closeMenu {
    menuWindow.hidden = YES;
}

// ========== АНАЛИТИКА: ЧТЕНИЕ РАЗНЫХ ТИПОВ ВОКРУГ АДРЕСА ==========
+ (void)showAnalytics {
    if (!players || players.count == 0) {
        [self addLog:@"❌ Сначала найди игроков"];
        [self showLog];
        return;
    }
    
    [self addLog:@"\n📊 АНАЛИТИКА СТРУКТУРЫ"];
    [self addLog:@"==================="];
    
    task_t task = mach_task_self();
    
    for (int pIdx = 0; pIdx < MIN(20, players.count); pIdx++) {
        PlayerCandidate *p = players[pIdx];
        uint64_t addr = p.address;
        
        [self addLog:[NSString stringWithFormat:@"\n🔹 ИГРОК %d: 0x%llx (%.1f,%.1f,%.1f)", pIdx+1, addr, p.x, p.y, p.z]];
        [self addLog:@"────────────────────────────────────────────"];
        
        // Сканируем диапазон -200..+200 байт от адреса
        for (int offset = -200; offset <= 200; offset += 4) {
            uint64_t scanAddr = addr + offset;
            uint8_t buffer[32];
            vm_size_t read;
            
            if (vm_read_overwrite(task, scanAddr, 32, (vm_address_t)buffer, &read) != KERN_SUCCESS) continue;
            
            // Пропускаем нулевые значения
            BOOL allZero = YES;
            for (int j = 0; j < 8; j++) if (buffer[j] != 0) { allZero = NO; break; }
            if (allZero) continue;
            
            NSMutableString *line = [NSMutableString stringWithFormat:@"  +0x%03X: ", offset];
            
            // Float
            float *f = (float*)buffer;
            if ([self isValidFloat:*f] && fabs(*f) < 10000 && fabs(*f) > 0.001) {
                [line appendFormat:@"F32=%.2f ", *f];
            }
            
            // Double
            double *d = (double*)buffer;
            if ([self isValidFloat:*d] && fabs(*d) < 10000 && fabs(*d) > 0.001) {
                [line appendFormat:@"F64=%.2f ", *d];
            }
            
            // Int32 (i4)
            int32_t *i4 = (int32_t*)buffer;
            if (*i4 != 0 && *i4 > -100000 && *i4 < 100000) {
                [line appendFormat:@"I4=%d ", *i4];
            }
            
            // UInt32 (u4)
            uint32_t *u4 = (uint32_t*)buffer;
            if (*u4 != 0 && *u4 < 100000) {
                [line appendFormat:@"U4=%u ", *u4];
            }
            
            // Int16 (i2)
            int16_t *i2 = (int16_t*)buffer;
            if (*i2 != 0 && *i2 > -10000 && *i2 < 10000) {
                [line appendFormat:@"I2=%d ", *i2];
            }
            
            // UInt16 (u2)
            uint16_t *u2 = (uint16_t*)buffer;
            if (*u2 != 0 && *u2 < 10000) {
                [line appendFormat:@"U2=%u ", *u2];
            }
            
            // Int8 (i1)
            int8_t *i1 = (int8_t*)buffer;
            if (*i1 != 0 && *i1 > -100 && *i1 < 100) {
                [line appendFormat:@"I1=%d ", *i1];
            }
            
            // UInt8 (u1)
            uint8_t *u1 = (uint8_t*)buffer;
            if (*u1 != 0 && *u1 < 100) {
                [line appendFormat:@"U1=%u ", *u1];
            }
            
            if (line.length > 10) {
                [self addLog:line];
            }
        }
    }
    
    [self showLog];
}

// ========== ПОИСК ИГРОКОВ ==========
+ (void)findPlayers {
    players = [NSMutableArray array];
    baseAddr = [self getBaseAddress];
    
    [self addLog:@"\n🎯 ПОИСК ИГРОКОВ"];
    [self addLog:@"================"];
    [self addLog:[NSString stringWithFormat:@"📌 База: 0x%llx", baseAddr]];
    [self addLog:[NSString stringWithFormat:@"📌 Диапазон координат: %.0f..%.0f", MIN_COORD, MAX_COORD]];
    [self addLog:[NSString stringWithFormat:@"📌 Поиск копий на смещении 0x%x (погрешность ±%.0f)", NEARBY_OFFSET, VALUE_TOLERANCE]];
    
    task_t task = mach_task_self();
    vm_address_t addr = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    int scanned = 0;
    int found = 0;
    NSMutableArray *candidates = [NSMutableArray array];
    
    while (vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS && scanned < SCAN_LIMIT) {
        
        if (size > 4096 && size < 5*1024*1024 && (info.protection & VM_PROT_READ)) {
            
            uint8_t *buffer = malloc(size);
            vm_size_t read;
            
            if (vm_read_overwrite(task, addr, size, (vm_address_t)buffer, &read) == KERN_SUCCESS) {
                
                for (int i = 0; i < size - 0x100; i += 4) {
                    scanned++;
                    
                    // Читаем X, Y, Z
                    float *x = (float*)(buffer + i);
                    float *y = (float*)(buffer + i + 4);
                    float *z = (float*)(buffer + i + 8);
                    
                    // Фильтр: валидные числа
                    if (![self isValidFloat:*x] || ![self isValidFloat:*y] || ![self isValidFloat:*z]) continue;
                    
                    // Фильтр: не (0,0,0)
                    if (fabs(*x) < 0.01 && fabs(*y) < 0.01 && fabs(*z) < 0.01) continue;
                    
                    // Фильтр: диапазон координат
                    if (*x < MIN_COORD || *x > MAX_COORD) continue;
                    if (*y < MIN_COORD || *y > MAX_COORD) continue;
                    if (*z < MIN_COORD || *z > MAX_COORD) continue;
                    
                    // Ищем копии на смещении NEARBY_OFFSET
                    int copies = 1;
                    for (int off = NEARBY_OFFSET; off <= NEARBY_OFFSET * 2; off += NEARBY_OFFSET) {
                        if (i + off + 12 >= size) break;
                        
                        float *x2 = (float*)(buffer + i + off);
                        float *y2 = (float*)(buffer + i + off + 4);
                        float *z2 = (float*)(buffer + i + off + 8);
                        
                        if ([self valuesMatch:*x with:*x2 tolerance:VALUE_TOLERANCE] &&
                            [self valuesMatch:*y with:*y2 tolerance:VALUE_TOLERANCE] &&
                            [self valuesMatch:*z with:*z2 tolerance:VALUE_TOLERANCE]) {
                            copies++;
                        }
                    }
                    
                    if (copies >= 2) { // Нашли минимум 2 копии — вероятно игрок
                        PlayerCandidate *p = [[PlayerCandidate alloc] init];
                        p.address = addr + i;
                        p.x = *x;
                        p.y = *y;
                        p.z = *z;
                        p.copyCount = copies;
                        
                        [candidates addObject:p];
                        found++;
                        
                        [self addLog:[NSString stringWithFormat:@"✅ Кандидат %d: (%.1f,%.1f,%.1f) @0x%llx [%d копий]",
                                      found, p.x, p.y, p.z, p.address, p.copyCount]];
                        
                        i += 0x100;
                        if (found >= 50) break;
                    }
                }
            }
            free(buffer);
        }
        addr += size;
        if (scanned % 100000 == 0) usleep(1000);
    }
    
    // Фильтруем дубликаты (похожие координаты)
    NSMutableArray *uniquePlayers = [NSMutableArray array];
    for (PlayerCandidate *p in candidates) {
        BOOL duplicate = NO;
        for (PlayerCandidate *existing in uniquePlayers) {
            if ([self valuesMatch:p.x with:existing.x tolerance:5.0] &&
                [self valuesMatch:p.y with:existing.y tolerance:5.0] &&
                [self valuesMatch:p.z with:existing.z tolerance:5.0]) {
                duplicate = YES;
                break;
            }
        }
        if (!duplicate) {
            [uniquePlayers addObject:p];
        }
    }
    
    players = uniquePlayers;
    
    [self addLog:@"\n📊 СТАТИСТИКА:"];
    [self addLog:[NSString stringWithFormat:@"📁 Проверено адресов: %d", scanned]];
    [self addLog:[NSString stringWithFormat:@"🎯 Кандидатов (с копиями): %d", found]];
    [self addLog:[NSString stringWithFormat:@"👥 Уникальных игроков: %lu", (unsigned long)players.count]];
    
    // Выводим топ-20
    [self addLog:@"\n🎯 ТОП-20 ИГРОКОВ:"];
    for (int i = 0; i < MIN(20, players.count); i++) {
        PlayerCandidate *p = players[i];
        [self addLog:[NSString stringWithFormat:@"%d. %@", i+1, p]];
    }
    
    [self showLog];
}

+ (void)addLog:(NSString*)t {
    if (!logText) logText = [NSMutableString new];
    [logText appendFormat:@"%@\n", t];
    NSLog(@"%@", t);
}

+ (void)showLog {
    if (!logWindow) {
        CGFloat w = 350;
        CGFloat h = 500;
        CGFloat x = (UIScreen.mainScreen.bounds.size.width - w) / 2;
        CGFloat y = (UIScreen.mainScreen.bounds.size.height - h) / 2;
        
        // Убедимся, что окно не уходит за экран
        if (y < 50) y = 50;
        if (y + h > UIScreen.mainScreen.bounds.size.height - 50) {
            y = UIScreen.mainScreen.bounds.size.height - h - 50;
        }
        
        logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, w, h)];
        logWindow.windowLevel = UIWindowLevelAlert + 2;
        logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
        logWindow.layer.cornerRadius = 15;
        logWindow.layer.borderWidth = 2;
        logWindow.layer.borderColor = UIColor.systemGreenColor.CGColor;
        logWindow.layer.masksToBounds = YES;
        
        // Текстовая область
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, w-10, h-80)];
        tv.backgroundColor = UIColor.blackColor;
        tv.textColor = UIColor.greenColor;
        tv.font = [UIFont fontWithName:@"Courier" size:10];
        tv.editable = NO;
        tv.showsVerticalScrollIndicator = YES;
        [logWindow addSubview:tv];
        
        // Кнопка копировать (левая)
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(20, h-65, 120, 40);
        copyBtn.backgroundColor = UIColor.systemBlueColor;
        copyBtn.layer.cornerRadius = 10;
        [copyBtn setTitle:@"📋 КОПИРОВАТЬ" forState:UIControlStateNormal];
        [copyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:copyBtn];
        
        // Кнопка закрыть (правая)
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(w-140, h-65, 120, 40);
        closeBtn.backgroundColor = UIColor.systemRedColor;
        closeBtn.layer.cornerRadius = 10;
        [closeBtn setTitle:@"✖️ ЗАКРЫТЬ" forState:UIControlStateNormal];
        [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [closeBtn addTarget:self action:@selector(closeLog) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:closeBtn];
        
        // Запоминаем текстовое поле
        objc_setAssociatedObject(logWindow, "textView", tv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    UITextView *tv = objc_getAssociatedObject(logWindow, "textView");
    tv.text = logText;
    
    // Скроллим вниз
    if (tv.text.length > 0) {
        NSRange bottom = NSMakeRange(tv.text.length - 1, 1);
        [tv scrollRangeToVisible:bottom];
    }
    
    logWindow.hidden = NO;
    [logWindow makeKeyAndVisible];
}

+ (void)closeLog { logWindow.hidden = YES; }
+ (void)copyLog { UIPasteboard.generalPasteboard.string = logText; }

@end

// ========== ИНИЦИАЛИЗАЦИЯ ==========
__attribute__((constructor))
static void init() {
    @autoreleasepool {
        logText = [NSMutableString new];
        
        uint64_t base = [ButtonHandler getBaseAddress];
        Camera_get_main = (t_Camera_get_main)(base + RVA_Camera_get_main);
        Camera_WorldToScreen = (t_Camera_WorldToScreen)(base + RVA_Camera_WorldToScreen);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIWindow *w = [ButtonHandler mainWindow];
            if (!w) return;
            
            floatingButton = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 150, 55, 55)];
            [w addSubview:floatingButton];
            
            [ButtonHandler addLog:@"✅ СКАНЕР ЗАГРУЖЕН"];
            [ButtonHandler addLog:@"⚡ НАЖМИ КНОПКУ"];
        });
    }
}
