#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== ТВОИ АДРЕСА (из скриншота) ==========
#define RVA_Camera_get_main         0x10871faf8
#define RVA_Camera_WorldToScreen    0x10871ed5c
#define RVA_Transform_get_position   0x108792ed0
#define BASE_ADDR 0x1042c4000

// ========== ТИПЫ ФУНКЦИЙ ==========
typedef void *(*t_get_main_camera)();
typedef void *(*t_world_to_screen)(void *camera, void *worldPos);
typedef void *(*t_get_position)(void *transform);

// ========== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ==========
static t_get_main_camera Camera_main = NULL;
static t_world_to_screen Camera_WorldToScreen = NULL;
static t_get_position Transform_get_position = NULL;

static BOOL espEnabled = NO;
static NSMutableString *logText = nil;
static UIWindow *overlayWindow = nil;
static UIWindow *logWindow = nil;
static UIButton *floatingButton = nil;
static NSMutableArray *foundPlayers = nil;
static NSMutableDictionary *scanStats = nil;

// ========== МОДЕЛЬ ИГРОКА ==========
@interface PlayerData : NSObject
@property (assign) float health;
@property (assign) float x, y, z;
@property (assign) unsigned long address;
@property (strong) NSString *name;
@property (assign) BOOL isLocal;
@property (assign) int confidence;
@end

@implementation PlayerData
- (NSString *)description {
    return [NSString stringWithFormat:@"[%d%%] %@ [%.1f] (%.1f, %.1f, %.1f) 0x%lx",
            self.confidence,
            self.name ?: @"???",
            self.health,
            self.x, self.y, self.z,
            self.address];
}
@end

// ========== ОБЪЯВЛЕНИЕ КЛАССОВ ==========
@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)copyLog;
+ (void)closeLogWindow;
+ (void)deepScanMemory;
+ (void)showLogWindow;
+ (UIViewController*)topViewController;
+ (UIWindow*)mainWindow;
+ (void)handlePan:(UIPanGestureRecognizer*)gesture;
+ (void)addLog:(NSString*)text;
+ (void)toggleESP;
+ (void)closeMenu:(UIButton*)sender;
+ (void)checkAddresses;
+ (void)showStats;
+ (BOOL)findNameNearAddress:(uint8_t*)buffer withBase:(unsigned long)baseAddr candidate:(int*)totalCandidates nameCount:(int*)nameCount;
@end

@interface ESPView : UIView
@end

@interface FloatingButton : UIButton
@end

// ========== ESP VIEW ==========
@implementation ESPView
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];

    if (!espEnabled || !foundPlayers.count) return;
    if (!Camera_main || !Camera_WorldToScreen || !Transform_get_position) return;

    void *cam = Camera_main();
    if (!cam) return;

    CGContextRef ctx = UIGraphicsGetCurrentContext();

    for (PlayerData *player in foundPlayers) {
        if (player.isLocal) continue;
        if (player.confidence < 60) continue; // Только уверенные

        float position[3] = {player.x, player.y, player.z};
        void *screenPos = Camera_WorldToScreen(cam, position);

        if (screenPos) {
            float *screen = (float*)screenPos;
            float screenX = screen[0] * rect.size.width;
            float screenY = screen[1] * rect.size.height;

            if (screenX < 0 || screenX > rect.size.width ||
                screenY < 0 || screenY > rect.size.height) continue;

            // Цвет в зависимости от уверенности
            UIColor *color = player.confidence > 80 ? [UIColor redColor] :
                            (player.confidence > 60 ? [UIColor orangeColor] : [UIColor yellowColor]);
            CGContextSetFillColorWithColor(ctx, color.CGColor);
            CGContextFillEllipseInRect(ctx, CGRectMake(screenX - 5, screenY - 5, 10, 10));

            // Имя и здоровье
            NSString *displayText = [NSString stringWithFormat:@"%@ [%.0f] %d%%",
                                      player.name ?: @"Enemy", player.health, player.confidence];
            [displayText drawAtPoint:CGPointMake(screenX + 10, screenY - 10) withAttributes:@{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:12],
                NSForegroundColorAttributeName: [UIColor whiteColor],
                NSStrokeColorAttributeName: [UIColor blackColor],
                NSStrokeWidthAttributeName: @-2
            }];
        }
    }
}
@end

// ========== ПЛАВАЮЩАЯ КНОПКА ==========
@implementation FloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = frame.size.width / 2;
        self.layer.masksToBounds = YES;
        [self setTitle:@"⚡" forState:UIControlStateNormal];
        [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:24];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[ButtonHandler class] action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];

        [self addTarget:[ButtonHandler class] action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
@end

// ========== РЕАЛИЗАЦИЯ ButtonHandler ==========
@implementation ButtonHandler

+ (void)showMenu {
    CGFloat menuWidth = 300;
    CGFloat menuHeight = 500;
    CGFloat menuX = ([UIScreen mainScreen].bounds.size.width - menuWidth) / 2;
    CGFloat menuY = ([UIScreen mainScreen].bounds.size.height - menuHeight) / 2;

    UIWindow *menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(menuX, menuY, menuWidth, menuHeight)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    menuWindow.layer.cornerRadius = 15;
    menuWindow.layer.borderWidth = 2;
    menuWindow.layer.borderColor = [UIColor systemBlueColor].CGColor;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, menuWidth, 40)];
    titleLabel.text = @"⚡ DEEP SCANNER";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [menuWindow addSubview:titleLabel];

    // Кнопка ESP
    UIButton *espBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    espBtn.frame = CGRectMake(20, 60, menuWidth-40, 45);
    espBtn.backgroundColor = espEnabled ? [UIColor systemGreenColor] : [UIColor systemGrayColor];
    espBtn.layer.cornerRadius = 10;
    [espBtn setTitle:[NSString stringWithFormat:@"🎯 ESP %@", espEnabled ? @"ON" : @"OFF"] forState:UIControlStateNormal];
    [espBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [espBtn addTarget:self action:@selector(toggleESP) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:espBtn];

    // Кнопка глубокого сканирования
    UIButton *scanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    scanBtn.frame = CGRectMake(20, 115, menuWidth-40, 45);
    scanBtn.backgroundColor = [UIColor systemPurpleColor];
    scanBtn.layer.cornerRadius = 10;
    [scanBtn setTitle:@"🔍 ГЛУБОКОЕ СКАНИРОВАНИЕ" forState:UIControlStateNormal];
    [scanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [scanBtn addTarget:self action:@selector(deepScanMemory) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:scanBtn];

    // Кнопка проверки адресов
    UIButton *checkBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    checkBtn.frame = CGRectMake(20, 170, menuWidth-40, 45);
    checkBtn.backgroundColor = [UIColor systemOrangeColor];
    checkBtn.layer.cornerRadius = 10;
    [checkBtn setTitle:@"🔎 ПРОВЕРИТЬ АДРЕСА" forState:UIControlStateNormal];
    [checkBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [checkBtn addTarget:self action:@selector(checkAddresses) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:checkBtn];

    // Кнопка лога
    UIButton *logBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    logBtn.frame = CGRectMake(20, 225, menuWidth-40, 45);
    logBtn.backgroundColor = [UIColor systemBlueColor];
    logBtn.layer.cornerRadius = 10;
    [logBtn setTitle:@"📋 ПОКАЗАТЬ ЛОГ" forState:UIControlStateNormal];
    [logBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [logBtn addTarget:self action:@selector(showLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:logBtn];

    // Кнопка статистики
    UIButton *statsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    statsBtn.frame = CGRectMake(20, 280, menuWidth-40, 45);
    statsBtn.backgroundColor = [UIColor systemTealColor];
    statsBtn.layer.cornerRadius = 10;
    [statsBtn setTitle:@"📊 ПОКАЗАТЬ СТАТИСТИКУ" forState:UIControlStateNormal];
    [statsBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [statsBtn addTarget:self action:@selector(showStats) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:statsBtn];

    // Кнопка закрыть
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 335, menuWidth-40, 45);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 10;
    [closeBtn setTitle:@"✖️ ЗАКРЫТЬ" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(closeMenu:) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:closeBtn];

    [menuWindow makeKeyAndVisible];
    objc_setAssociatedObject(self, @selector(closeMenu:), menuWindow, OBJC_ASSOCIATION_RETAIN);
}

+ (void)toggleESP {
    espEnabled = !espEnabled;
    [self showMenu];
}

+ (void)closeMenu:(UIButton*)sender {
    UIWindow *menuWindow = (UIWindow*)sender.superview;
    if ([menuWindow isKindOfClass:[UIWindow class]]) {
        menuWindow.hidden = YES;
        [menuWindow resignKeyWindow];
    }
}

+ (void)handlePan:(UIPanGestureRecognizer*)gesture {
    if (!floatingButton) return;
    CGPoint translation = [gesture translationInView:floatingButton.superview];
    CGPoint center = floatingButton.center;
    center.x += translation.x;
    center.y += translation.y;
    floatingButton.center = center;
    [gesture setTranslation:CGPointZero inView:floatingButton.superview];
}

+ (void)checkAddresses {
    [logText setString:@""];
    [self addLog:@"🔍 ПРОВЕРКА АДРЕСОВ"];
    [self addLog:@"==================="];
    [self addLog:[NSString stringWithFormat:@"Camera.main: %p", Camera_main]];
    [self addLog:[NSString stringWithFormat:@"WorldToScreen: %p", Camera_WorldToScreen]];
    [self addLog:[NSString stringWithFormat:@"get_position: %p", Transform_get_position]];

    if (Camera_main) {
        void *cam = Camera_main();
        [self addLog:[NSString stringWithFormat:@"Camera instance: %p", cam]];
    }

    [self showLogWindow];
}

+ (void)showStats {
    [logText setString:@""];
    [self addLog:@"📊 СТАТИСТИКА СКАНИРОВАНИЯ"];
    [self addLog:@"========================"];

    if (scanStats) {
        for (NSString *key in scanStats) {
            [self addLog:[NSString stringWithFormat:@"%@: %@", key, scanStats[key]]];
        }
    } else {
        [self addLog:@"Нет данных. Запустите сканирование."];
    }

    [self showLogWindow];
}

// ========== ПОИСК ИМЕНИ РЯДОМ С АДРЕСОМ ==========
+ (BOOL)findNameNearAddress:(uint8_t*)buffer withBase:(unsigned long)baseAddr candidate:(int*)totalCandidates nameCount:(int*)nameCount {
    
    // Ищем в диапазоне -0x80 до +0x80 от адреса
    for (int offset = -0x80; offset < 0x80; offset += 4) {
        char *namePtr = (char*)(buffer + offset);
        
        // Проверяем, похоже ли на имя (печатные символы)
        if (namePtr[0] > 32 && namePtr[0] < 127 &&
            namePtr[1] > 32 && namePtr[1] < 127 &&
            namePtr[2] > 32 && namePtr[2] < 127) {
            
            NSString *candidate = @(namePtr);
            if (candidate.length > 3 && candidate.length < 20) {
                NSRange letterRange = [candidate rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]];
                if (letterRange.location != NSNotFound) {
                    (*nameCount)++;
                    
                    PlayerData *player = [[PlayerData alloc] init];
                    player.address = baseAddr;
                    player.name = candidate;
                    player.confidence = 70; // Базовая уверенность для имени
                    
                    // Пробуем найти здоровье рядом
                    for (int j = -0x20; j < 0x20; j += 4) {
                        float *healthPtr = (float*)(buffer + j);
                        if (*healthPtr > 0 && *healthPtr < 200) {
                            player.health = *healthPtr;
                            player.confidence += 20;
                            
                            // Ищем координаты рядом со здоровьем
                            float *x = (float*)(buffer + j + 0x10);
                            float *y = (float*)(buffer + j + 0x14);
                            float *z = (float*)(buffer + j + 0x18);
                            
                            if (*x > -10000 && *x < 10000 && 
                                *y > -10000 && *y < 10000 && 
                                *z > -10000 && *z < 10000) {
                                player.x = *x;
                                player.y = *y;
                                player.z = *z;
                                player.confidence += 20;
                            }
                            break;
                        }
                    }
                    
                    [foundPlayers addObject:player];
                    (*totalCandidates)++;
                    
                    return YES;
                }
            }
        }
    }
    return NO;
}

// ========== ГЛУБОКОЕ СКАНИРОВАНИЕ ==========
+ (void)deepScanMemory {
    [logText setString:@""];
    [self addLog:@"🔍 ГЛУБОКОЕ СКАНИРОВАНИЕ ПАМЯТИ"];
    [self addLog:@"================================="];
    
    foundPlayers = [NSMutableArray array];
    scanStats = [NSMutableDictionary dictionary];
    
    task_t task = mach_task_self();
    vm_address_t address = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    int regionCount = 0;
    int totalCandidates = 0;
    int healthFloatCandidates = 0;
    int healthIntCandidates = 0;
    int nameCandidates = 0;
    int structCandidates = 0;
    
    NSMutableDictionary *healthFloatDist = [NSMutableDictionary dictionary];
    NSMutableDictionary *healthIntDist = [NSMutableDictionary dictionary];
    
    [self addLog:[NSString stringWithFormat:@"Базовый адрес: 0x%llx", BASE_ADDR]];
    
    int lastPercent = -1;
    vm_address_t totalScanned = 0;
    vm_address_t lastAddress = 0;
    
    while (vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS) {
        
        regionCount++;
        totalScanned += size;
        
        // Показываем прогресс
        int percent = (totalScanned / (1024 * 1024)) % 100;
        if (percent != lastPercent && percent % 10 == 0) {
            [self addLog:[NSString stringWithFormat:@"📊 Сканировано: %d MB, регионов: %d", 
                          (int)(totalScanned / (1024 * 1024)), regionCount]];
            lastPercent = percent;
        }
        
        // Пропускаем слишком маленькие или огромные регионы
        if (size < 4096 || size > 50 * 1024 * 1024) {
            address += size;
            continue;
        }
        
        // Читаем регион
        uint8_t *buffer = malloc(size);
        vm_size_t data_read;
        
        if (vm_read_overwrite(task, address, size, (vm_address_t)buffer, &data_read) == KERN_SUCCESS) {
            
            // Проходим по памяти с шагом 4 байта (для float/int)
            for (int i = 0; i < data_read - 256; i += 4) {
                
                // ------------------------------------------------------------
                // ПРИЗНАК 1: Здоровье (float 1-200)
                // ------------------------------------------------------------
                float *healthFloat = (float*)(buffer + i);
                if (*healthFloat >= 1 && *healthFloat <= 200) {
                    
                    // Проверяем координаты (смещение 0x10, 0x14, 0x18)
                    float *x = (float*)(buffer + i + 0x10);
                    float *y = (float*)(buffer + i + 0x14);
                    float *z = (float*)(buffer + i + 0x18);
                    
                    BOOL hasValidCoords = (*x > -10000 && *x < 10000 && 
                                           *y > -10000 && *y < 10000 && 
                                           *z > -10000 && *z < 10000);
                    
                    if (hasValidCoords) {
                        healthFloatCandidates++;
                        NSString *healthKey = [NSString stringWithFormat:@"float_%.0f", *healthFloat];
                        healthFloatDist[healthKey] = @([healthFloatDist[healthKey] intValue] + 1);
                        
                        // Создаем кандидата
                        PlayerData *player = [[PlayerData alloc] init];
                        player.health = *healthFloat;
                        player.x = *x;
                        player.y = *y;
                        player.z = *z;
                        player.address = (unsigned long)(address + i);
                        player.confidence = 60; // Базовая уверенность
                        
                        // Ищем имя рядом
                        unsigned long nameAddr = address + i;
                        uint8_t *nameBuffer = buffer + i;
                        
                        for (int offset = -0x80; offset < 0x80; offset += 4) {
                            char *namePtr = (char*)(nameBuffer + offset);
                            if (namePtr[0] > 32 && namePtr[0] < 127 &&
                                namePtr[1] > 32 && namePtr[1] < 127) {
                                NSString *candidate = @(namePtr);
                                if (candidate.length > 3 && candidate.length < 20) {
                                    player.name = candidate;
                                    player.confidence += 30;
                                    nameCandidates++;
                                    break;
                                }
                            }
                        }
                        
                        [foundPlayers addObject:player];
                        totalCandidates++;
                    }
                }
                
                // ------------------------------------------------------------
                // ПРИЗНАК 2: Здоровье (int 1-200)
                // ------------------------------------------------------------
                int *healthInt = (int*)(buffer + i);
                if (*healthInt >= 1 && *healthInt <= 200) {
                    
                    // Проверяем координаты (int версия)
                    int *xInt = (int*)(buffer + i + 0x10);
                    int *yInt = (int*)(buffer + i + 0x14);
                    int *zInt = (int*)(buffer + i + 0x18);
                    
                    BOOL hasValidIntCoords = (*xInt > -10000 && *xInt < 10000 && 
                                              *yInt > -10000 && *yInt < 10000 && 
                                              *zInt > -10000 && *zInt < 10000);
                    
                    if (hasValidIntCoords) {
                        healthIntCandidates++;
                        NSString *healthKey = [NSString stringWithFormat:@"int_%d", *healthInt];
                        healthIntDist[healthKey] = @([healthIntDist[healthKey] intValue] + 1);
                        
                        // Конвертируем int координаты в float для единообразия
                        PlayerData *player = [[PlayerData alloc] init];
                        player.health = (float)*healthInt;
                        player.x = (float)*xInt;
                        player.y = (float)*yInt;
                        player.z = (float)*zInt;
                        player.address = (unsigned long)(address + i);
                        player.confidence = 50; // Чуть ниже, т.к. int менее характерен
                        
                        [foundPlayers addObject:player];
                        totalCandidates++;
                    }
                }
                
                // ------------------------------------------------------------
                // ПРИЗНАК 3: Поиск структур (проверка связности)
                // ------------------------------------------------------------
                if (i % 256 == 0) { // Проверяем каждые 256 байт на наличие структуры
                    int validPointers = 0;
                    for (int j = 0; j < 32; j += 8) {
                        uint64_t *ptr = (uint64_t*)(buffer + i + j);
                        if (*ptr > 0x100000000 && *ptr < 0x200000000) { // Похоже на указатель
                            validPointers++;
                        }
                    }
                    if (validPointers > 2) {
                        structCandidates++;
                    }
                }
            }
        }
        free(buffer);
        
        address += size;
        address = (address + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);
    }
    
    // Сохраняем статистику
    scanStats[@"Просканировано регионов"] = @(regionCount);
    scanStats[@"Объем памяти"] = [NSString stringWithFormat:@"%d MB", (int)(totalScanned / (1024 * 1024))];
    scanStats[@"Кандидатов (float)"] = @(healthFloatCandidates);
    scanStats[@"Кандидатов (int)"] = @(healthIntCandidates);
    scanStats[@"Найдено имен"] = @(nameCandidates);
    scanStats[@"Структур найдено"] = @(structCandidates);
    scanStats[@"Всего кандидатов"] = @(totalCandidates);
    scanStats[@"Уникальных игроков"] = @(foundPlayers.count);
    
    [self addLog:@"\n📊 СТАТИСТИКА СКАНИРОВАНИЯ:"];
    [self addLog:[NSString stringWithFormat:@"📁 Регионов: %d", regionCount]];
    [self addLog:[NSString stringWithFormat:@"💾 Объем: %d MB", (int)(totalScanned / (1024 * 1024))]];
    [self addLog:[NSString stringWithFormat:@"🎯 Кандидатов (float): %d", healthFloatCandidates]];
    [self addLog:[NSString stringWithFormat:@"🎯 Кандидатов (int): %d", healthIntCandidates]];
    [self addLog:[NSString stringWithFormat:@"📛 Найдено имен: %d", nameCandidates]];
    [self addLog:[NSString stringWithFormat:@"🏗️ Структур: %d", structCandidates]];
    [self addLog:[NSString stringWithFormat:@"📊 Всего кандидатов: %d", totalCandidates]];
    [self addLog:[NSString stringWithFormat:@"👥 Уникальных игроков: %lu", (unsigned long)foundPlayers.count]];
    
    // Показываем распределение здоровья
    if (healthFloatDist.count > 0) {
        [self addLog:@"\n📈 Распределение float здоровья:"];
        NSArray *sortedKeys = [healthFloatDist.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        for (NSString *key in sortedKeys) {
            [self addLog:[NSString stringWithFormat:@"  %@: %@", key, healthFloatDist[key]]];
        }
    }
    
    if (healthIntDist.count > 0) {
        [self addLog:@"\n📈 Распределение int здоровья:"];
        NSArray *sortedKeys = [healthIntDist.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        for (NSString *key in sortedKeys) {
            [self addLog:[NSString stringWithFormat:@"  %@: %@", key, healthIntDist[key]]];
        }
    }
    
    // Сортируем по уверенности
    NSArray *sortedPlayers = [foundPlayers sortedArrayUsingComparator:^NSComparisonResult(PlayerData *p1, PlayerData *p2) {
        return p2.confidence - p1.confidence;
    }];
    
    [self addLog:@"\n🏆 ТОП-20 КАНДИДАТОВ:"];
    for (int i = 0; i < MIN(20, sortedPlayers.count); i++) {
        PlayerData *p = sortedPlayers[i];
        [self addLog:[NSString stringWithFormat:@"%d. %@", i+1, p]];
    }
    
    [self showLogWindow];
}

+ (void)copyLog {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = logText;

    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(100, 300, 120, 40)];
    toast.backgroundColor = [UIColor blackColor];
    toast.textColor = [UIColor whiteColor];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.text = @"✅ Скопировано";
    toast.layer.cornerRadius = 10;
    toast.layer.masksToBounds = YES;
    [[self mainWindow] addSubview:toast];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [toast removeFromSuperview];
    });
}

+ (void)closeLogWindow {
    logWindow.hidden = YES;
}

+ (void)showLogWindow {
    if (logWindow) {
        logWindow.hidden = NO;
        [logWindow makeKeyAndVisible];
        return;
    }

    CGFloat logWidth = [UIScreen mainScreen].bounds.size.width - 40;
    CGFloat logHeight = [UIScreen mainScreen].bounds.size.height - 100;
    CGFloat logX = 20;
    CGFloat logY = 50;

    logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(logX, logY, logWidth, logHeight)];
    logWindow.windowLevel = UIWindowLevelAlert + 2;
    logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
    logWindow.layer.cornerRadius = 15;
    logWindow.layer.borderWidth = 2;
    logWindow.layer.borderColor = [UIColor greenColor].CGColor;

    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(10, 10, logWidth-20, logHeight-80)];
    textView.backgroundColor = [UIColor blackColor];
    textView.textColor = [UIColor greenColor];
    textView.font = [UIFont fontWithName:@"Courier" size:12];
    textView.text = logText;
    textView.editable = NO;
    textView.layer.cornerRadius = 10;
    [logWindow addSubview:textView];

    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(20, logHeight-60, 100, 40);
    copyBtn.backgroundColor = [UIColor systemBlueColor];
    copyBtn.layer.cornerRadius = 10;
    [copyBtn setTitle:@"📋 Копировать" forState:UIControlStateNormal];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:copyBtn];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(logWidth-120, logHeight-60, 100, 40);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 10;
    [closeBtn setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(closeLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:closeBtn];

    [logWindow makeKeyAndVisible];
}

+ (void)addLog:(NSString *)text {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendFormat:@"%@\n", text];
    NSLog(@"%@", text);
}

+ (UIViewController*)topViewController {
    UIWindow *window = [self mainWindow];
    if (!window) return nil;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
}

+ (UIWindow*)mainWindow {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *window in ((UIWindowScene*)scene).windows) {
                if (window.isKeyWindow) return window;
            }
        }
    }
    return nil;
}

@end

// ========== ИНИЦИАЛИЗАЦИЯ ==========
__attribute__((constructor))
static void init() {
    @autoreleasepool {
        logText = [[NSMutableString alloc] init];

        uint64_t base = BASE_ADDR;

        Camera_main = (t_get_main_camera)(base + (RVA_Camera_get_main - 0x1042c4000));
        Camera_WorldToScreen = (t_world_to_screen)(base + (RVA_Camera_WorldToScreen - 0x1042c4000));
        Transform_get_position = (t_get_position)(base + (RVA_Transform_get_position - 0x1042c4000));

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIWindow *mainWindow = [ButtonHandler mainWindow];
            if (!mainWindow) return;

            floatingButton = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 150, 60, 60)];
            [mainWindow addSubview:floatingButton];

            overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            overlayWindow.windowLevel = UIWindowLevelAlert + 1;
            overlayWindow.backgroundColor = [UIColor clearColor];
            overlayWindow.userInteractionEnabled = NO;

            ESPView *espView = [[ESPView alloc] initWithFrame:[UIScreen mainScreen].bounds];
            espView.backgroundColor = [UIColor clearColor];
            [overlayWindow addSubview:espView];

            [overlayWindow makeKeyAndVisible];

            [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t){
                if (espEnabled) {
                    [espView setNeedsDisplay];
                }
            }];

            [ButtonHandler addLog:@"✅ Твик загружен"];
        });
    }
}
