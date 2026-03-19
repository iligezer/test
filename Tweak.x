#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== АДРЕСА ==========
#define RVA_Camera_get_main         0x10871faf8
#define RVA_Camera_WorldToScreen    0x10871ed5c
#define RVA_Transform_get_position   0x108792ed0
#define BASE_ADDR 0x1042c4000

typedef void *(*t_get_main_camera)();
typedef void *(*t_world_to_screen)(void *camera, void *worldPos);
typedef void *(*t_get_position)(void *transform);

static t_get_main_camera Camera_main = NULL;
static t_world_to_screen Camera_WorldToScreen = NULL;
static t_get_position Transform_get_position = NULL;

static NSMutableString *logText = nil;
static UIWindow *logWindow = nil;
static UIButton *floatingButton = nil;
static NSMutableArray *trackedAddresses = nil;
static NSMutableArray *currentValues = nil;

// ========== ОБЪЯВЛЕНИЕ ==========
@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)closeMenu;
+ (void)copyLog;
+ (void)showLogWindow;
+ (void)updateLogWindow;
+ (void)addLog:(NSString*)text;
+ (void)pasteAddress;
+ (void)showAddresses;
+ (void)clearAddresses;
+ (void)startScan;
+ (void)refreshChanged;
+ (void)refreshUnchanged;
+ (void)showCandidates;
+ (UIViewController*)topViewController;
+ (UIWindow*)mainWindow;
+ (void)handlePan:(UIPanGestureRecognizer*)gesture;
@end

@interface FloatingButton : UIButton
@end

@implementation FloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = frame.size.width/2;
        [self setTitle:@"⚡" forState:UIControlStateNormal];
        [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[ButtonHandler class] action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
        [self addTarget:[ButtonHandler class] action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
@end

@implementation ButtonHandler

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

+ (UIViewController*)topViewController {
    UIWindow *window = [self mainWindow];
    if (!window) return nil;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
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

+ (void)showMenu {
    CGFloat menuWidth = 300;
    CGFloat menuHeight = 550;
    CGFloat menuX = ([UIScreen mainScreen].bounds.size.width - menuWidth) / 2;
    CGFloat menuY = ([UIScreen mainScreen].bounds.size.height - menuHeight) / 2;
    
    UIWindow *menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(menuX, menuY, menuWidth, menuHeight)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    menuWindow.layer.cornerRadius = 15;
    menuWindow.layer.borderWidth = 2;
    menuWindow.layer.borderColor = [UIColor systemBlueColor].CGColor;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, menuWidth, 30)];
    title.text = @"⚡ COORD FINDER";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:20];
    [menuWindow addSubview:title];
    
    int yPos = 60;
    int btnHeight = 45;
    int btnSpacing = 5;
    
    // Кнопка: ВСТАВИТЬ АДРЕС
    UIButton *pasteBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    pasteBtn.frame = CGRectMake(20, yPos, menuWidth-40, btnHeight);
    pasteBtn.backgroundColor = [UIColor systemBlueColor];
    pasteBtn.layer.cornerRadius = 10;
    [pasteBtn setTitle:@"📋 ВСТАВИТЬ АДРЕС" forState:UIControlStateNormal];
    [pasteBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    pasteBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [pasteBtn addTarget:self action:@selector(pasteAddress) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:pasteBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: ПОКАЗАТЬ АДРЕСА
    UIButton *showBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    showBtn.frame = CGRectMake(20, yPos, menuWidth-40, btnHeight);
    showBtn.backgroundColor = [UIColor systemPurpleColor];
    showBtn.layer.cornerRadius = 10;
    [showBtn setTitle:@"📋 ПОКАЗАТЬ АДРЕСА" forState:UIControlStateNormal];
    [showBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    showBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [showBtn addTarget:self action:@selector(showAddresses) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:showBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: НАЧАТЬ СКАНИРОВАНИЕ
    UIButton *startBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    startBtn.frame = CGRectMake(20, yPos, menuWidth-40, btnHeight);
    startBtn.backgroundColor = [UIColor systemGreenColor];
    startBtn.layer.cornerRadius = 10;
    [startBtn setTitle:@"🔍 НАЧАТЬ СКАНИРОВАНИЕ" forState:UIControlStateNormal];
    [startBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    startBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [startBtn addTarget:self action:@selector(startScan) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:startBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: ИЗМЕНИЛОСЬ
    UIButton *changedBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    changedBtn.frame = CGRectMake(20, yPos, menuWidth-40, btnHeight);
    changedBtn.backgroundColor = [UIColor systemOrangeColor];
    changedBtn.layer.cornerRadius = 10;
    [changedBtn setTitle:@"📈 ИЗМЕНИЛОСЬ" forState:UIControlStateNormal];
    [changedBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    changedBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [changedBtn addTarget:self action:@selector(refreshChanged) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:changedBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: НЕ ИЗМЕНИЛОСЬ
    UIButton *unchangedBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    unchangedBtn.frame = CGRectMake(20, yPos, menuWidth-40, btnHeight);
    unchangedBtn.backgroundColor = [UIColor systemRedColor];
    unchangedBtn.layer.cornerRadius = 10;
    [unchangedBtn setTitle:@"📉 НЕ ИЗМЕНИЛОСЬ" forState:UIControlStateNormal];
    [unchangedBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    unchangedBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [unchangedBtn addTarget:self action:@selector(refreshUnchanged) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:unchangedBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: КАНДИДАТЫ
    UIButton *candidatesBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    candidatesBtn.frame = CGRectMake(20, yPos, menuWidth-40, btnHeight);
    candidatesBtn.backgroundColor = [UIColor systemIndigoColor];
    candidatesBtn.layer.cornerRadius = 10;
    [candidatesBtn setTitle:@"🎯 ПОКАЗАТЬ КАНДИДАТОВ" forState:UIControlStateNormal];
    [candidatesBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    candidatesBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [candidatesBtn addTarget:self action:@selector(showCandidates) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:candidatesBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: ОЧИСТИТЬ
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(20, yPos, menuWidth-40, btnHeight);
    clearBtn.backgroundColor = [UIColor systemGrayColor];
    clearBtn.layer.cornerRadius = 10;
    [clearBtn setTitle:@"🗑️ ОЧИСТИТЬ ВСЕ" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    clearBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [clearBtn addTarget:self action:@selector(clearAddresses) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:clearBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: ЗАКРЫТЬ
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, yPos, menuWidth-40, btnHeight);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 10;
    [closeBtn setTitle:@"✖️ ЗАКРЫТЬ" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [closeBtn addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:closeBtn];
    
    [menuWindow makeKeyAndVisible];
    objc_setAssociatedObject(self, @selector(closeMenu), menuWindow, OBJC_ASSOCIATION_RETAIN);
}

+ (void)closeMenu {
    UIWindow *menuWindow = objc_getAssociatedObject(self, @selector(closeMenu));
    menuWindow.hidden = YES;
    [menuWindow resignKeyWindow];
}

// ========== ВСТАВИТЬ АДРЕС ИЗ БУФЕРА ==========
+ (void)pasteAddress {
    if (!trackedAddresses) {
        trackedAddresses = [NSMutableArray array];
    }
    
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSString *addrStr = pasteboard.string;
    
    if (addrStr.length > 0) {
        addrStr = [addrStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        addrStr = [addrStr stringByReplacingOccurrencesOfString:@"\"" withString:@""];
        addrStr = [addrStr stringByReplacingOccurrencesOfString:@"'" withString:@""];
        addrStr = [addrStr stringByReplacingOccurrencesOfString:@" " withString:@""];
        
        unsigned long long addr = 0;
        NSScanner *scanner = [NSScanner scannerWithString:addrStr];
        
        if ([addrStr hasPrefix:@"0x"] || [addrStr hasPrefix:@"0X"]) {
            [scanner scanHexLongLong:&addr];
        } else {
            addr = [addrStr longLongValue];
        }
        
        if (addr > 0) {
            [trackedAddresses addObject:@(addr)];
            [self addLog:[NSString stringWithFormat:@"✅ Вставлен: 0x%llx", addr]];
            [self addLog:[NSString stringWithFormat:@"📊 Всего: %lu", (unsigned long)trackedAddresses.count]];
        } else {
            [self addLog:[NSString stringWithFormat:@"❌ Ошибка: %@", addrStr]];
        }
    } else {
        [self addLog:@"❌ Буфер пуст"];
    }
    [self updateLogWindow];
}

// ========== ПОКАЗАТЬ АДРЕСА ==========
+ (void)showAddresses {
    [self addLog:@"\n📋 СОХРАНЕННЫЕ АДРЕСА:"];
    
    if (!trackedAddresses || trackedAddresses.count == 0) {
        [self addLog:@"❌ Нет адресов"];
    } else {
        for (int i = 0; i < trackedAddresses.count; i++) {
            NSNumber *addrNum = trackedAddresses[i];
            [self addLog:[NSString stringWithFormat:@"%d. 0x%llx", i+1, (unsigned long long)[addrNum unsignedLongLongValue]]];
        }
    }
    [self showLogWindow];
}

// ========== ОЧИСТИТЬ ВСЕ ==========
+ (void)clearAddresses {
    [trackedAddresses removeAllObjects];
    [currentValues removeAllObjects];
    [self addLog:@"🗑️ Все адреса очищены"];
    [self updateLogWindow];
}

// ========== НАЧАТЬ СКАНИРОВАНИЕ (С РАСШИРЕНИЕМ) ==========
+ (void)startScan {
    if (!trackedAddresses || trackedAddresses.count == 0) {
        [self addLog:@"❌ Нет адресов для сканирования"];
        [self updateLogWindow];
        return;
    }
    
    // Расширяем массив адресами выше и ниже (шаг 4 байта, диапазон 0x800)
    NSMutableArray *expandedAddresses = [NSMutableArray array];
    int range = 0x800; // 2048 байт вверх и вниз
    int step = 4;      // шаг 4 байта (для float)
    
    for (NSNumber *addrNum in trackedAddresses) {
        unsigned long long baseAddr = [addrNum unsignedLongLongValue];
        
        for (int offset = -range; offset <= range; offset += step) {
            unsigned long long newAddr = baseAddr + offset;
            [expandedAddresses addObject:@(newAddr)];
        }
    }
    
    trackedAddresses = expandedAddresses;
    currentValues = [NSMutableArray array];
    
    task_t task = mach_task_self();
    
    [self addLog:[NSString stringWithFormat:@"\n🔍 РАСШИРЕННОЕ СКАНИРОВАНИЕ"]];
    [self addLog:[NSString stringWithFormat:@"📊 Диапазон: ±0x%x байт", range]];
    [self addLog:[NSString stringWithFormat:@"📊 Шаг: %d байта", step]];
    [self addLog:[NSString stringWithFormat:@"📊 Всего адресов: %lu", (unsigned long)trackedAddresses.count]];
    
    int success = 0;
    for (NSNumber *addrNum in trackedAddresses) {
        vm_address_t addr = [addrNum unsignedLongLongValue];
        float value = 0;
        vm_size_t data_read = 0;
        kern_return_t kr = vm_read_overwrite(task, addr, 4, (vm_address_t)&value, &data_read);
        
        if (kr == KERN_SUCCESS) {
            [currentValues addObject:@(value)];
            success++;
        } else {
            [currentValues addObject:@(0.0f)];
        }
    }
    
    [self addLog:[NSString stringWithFormat:@"✅ Успешно прочитано: %d", success]];
    [self addLog:@"✅ Начальные значения сохранены"];
    [self addLog:@"📊 Двигайся и нажимай ИЗМЕНИЛОСЬ/НЕ ИЗМЕНИЛОСЬ"];
    [self updateLogWindow];
}

// ========== ИЗМЕНИЛОСЬ ==========
+ (void)refreshChanged {
    if (!trackedAddresses || trackedAddresses.count == 0 || !currentValues) {
        [self addLog:@"❌ Сначала начни сканирование"];
        [self updateLogWindow];
        return;
    }
    
    NSMutableArray *newAddresses = [NSMutableArray array];
    NSMutableArray *newValues = [NSMutableArray array];
    task_t task = mach_task_self();
    
    [self addLog:@"\n📈 ПОИСК ИЗМЕНИВШИХСЯ..."];
    int changed = 0;
    
    for (int i = 0; i < trackedAddresses.count; i++) {
        NSNumber *addrNum = trackedAddresses[i];
        vm_address_t addr = [addrNum unsignedLongLongValue];
        
        float value = 0;
        vm_size_t data_read = 0;
        kern_return_t kr = vm_read_overwrite(task, addr, 4, (vm_address_t)&value, &data_read);
        
        if (kr == KERN_SUCCESS) {
            float oldValue = [currentValues[i] floatValue];
            if (fabs(value - oldValue) > 0.001f) {
                [newAddresses addObject:addrNum];
                [newValues addObject:@(value)];
                changed++;
            }
        }
    }
    
    trackedAddresses = newAddresses;
    currentValues = newValues;
    
    [self addLog:[NSString stringWithFormat:@"✅ Найдено изменившихся: %d", changed]];
    [self addLog:[NSString stringWithFormat:@"📊 Осталось адресов: %lu", (unsigned long)trackedAddresses.count]];
    [self updateLogWindow];
}

// ========== НЕ ИЗМЕНИЛОСЬ ==========
+ (void)refreshUnchanged {
    if (!trackedAddresses || trackedAddresses.count == 0 || !currentValues) {
        [self addLog:@"❌ Сначала начни сканирование"];
        [self updateLogWindow];
        return;
    }
    
    NSMutableArray *newAddresses = [NSMutableArray array];
    NSMutableArray *newValues = [NSMutableArray array];
    task_t task = mach_task_self();
    
    [self addLog:@"\n📉 ПОИСК НЕИЗМЕНИВШИХСЯ..."];
    int unchanged = 0;
    
    for (int i = 0; i < trackedAddresses.count; i++) {
        NSNumber *addrNum = trackedAddresses[i];
        vm_address_t addr = [addrNum unsignedLongLongValue];
        
        float value = 0;
        vm_size_t data_read = 0;
        kern_return_t kr = vm_read_overwrite(task, addr, 4, (vm_address_t)&value, &data_read);
        
        if (kr == KERN_SUCCESS) {
            float oldValue = [currentValues[i] floatValue];
            if (fabs(value - oldValue) <= 0.001f) {
                [newAddresses addObject:addrNum];
                [newValues addObject:@(value)];
                unchanged++;
            }
        }
    }
    
    trackedAddresses = newAddresses;
    currentValues = newValues;
    
    [self addLog:[NSString stringWithFormat:@"✅ Найдено неизменившихся: %d", unchanged]];
    [self addLog:[NSString stringWithFormat:@"📊 Осталось адресов: %lu", (unsigned long)trackedAddresses.count]];
    [self updateLogWindow];
}

// ========== ПОКАЗАТЬ КАНДИДАТОВ ==========
+ (void)showCandidates {
    [self addLog:@"\n🎯 ТЕКУЩИЕ КАНДИДАТЫ:"];
    
    if (!trackedAddresses || trackedAddresses.count == 0) {
        [self addLog:@"❌ Нет кандидатов"];
    } else {
        // Группируем по 3 (для поиска XYZ)
        for (int i = 0; i < trackedAddresses.count; i++) {
            NSNumber *addrNum = trackedAddresses[i];
            float value = currentValues ? [currentValues[i] floatValue] : 0;
            
            // Показываем только осмысленные значения (не 0 и не огромные)
            if (fabs(value) > 0.1 && fabs(value) < 10000) {
                [self addLog:[NSString stringWithFormat:@"%d. 0x%llx = %.3f", 
                              i+1, (unsigned long long)[addrNum unsignedLongLongValue], value]];
                
                // Показываем следующие два адреса как возможные Y и Z
                if (i + 1 < trackedAddresses.count) {
                    float y = [currentValues[i+1] floatValue];
                    if (fabs(y) > 0.1 && fabs(y) < 10000) {
                        [self addLog:[NSString stringWithFormat:@"   Y: 0x%llx = %.3f", 
                                      (unsigned long long)[trackedAddresses[i+1] unsignedLongLongValue], y]];
                    }
                }
                if (i + 2 < trackedAddresses.count) {
                    float z = [currentValues[i+2] floatValue];
                    if (fabs(z) > 0.1 && fabs(z) < 10000) {
                        [self addLog:[NSString stringWithFormat:@"   Z: 0x%llx = %.3f", 
                                      (unsigned long long)[trackedAddresses[i+2] unsignedLongLongValue], z]];
                    }
                }
            }
        }
    }
    [self showLogWindow];
}

// ========== ЛОГ ==========
+ (void)addLog:(NSString *)text {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendFormat:@"%@\n", text];
    NSLog(@"%@", text);
}

+ (void)updateLogWindow {
    if (logWindow) {
        for (UIView *view in logWindow.subviews) {
            if ([view isKindOfClass:[UITextView class]]) {
                UITextView *tv = (UITextView *)view;
                tv.text = logText;
                if (tv.text.length > 0) {
                    NSRange bottom = NSMakeRange(tv.text.length - 1, 1);
                    [tv scrollRangeToVisible:bottom];
                }
                break;
            }
        }
    }
}

+ (void)showLogWindow {
    if (logWindow) {
        logWindow.hidden = NO;
        [self updateLogWindow];
        return;
    }
    
    CGFloat w = [UIScreen mainScreen].bounds.size.width - 40;
    CGFloat h = [UIScreen mainScreen].bounds.size.height - 150;
    CGFloat x = 20;
    CGFloat y = 70;
    
    logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, w, h)];
    logWindow.windowLevel = UIWindowLevelAlert + 2;
    logWindow.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
    logWindow.layer.cornerRadius = 10;
    logWindow.layer.borderWidth = 2;
    logWindow.layer.borderColor = [UIColor greenColor].CGColor;
    
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(5, 5, w-10, h-60)];
    tv.backgroundColor = [UIColor blackColor];
    tv.textColor = [UIColor greenColor];
    tv.font = [UIFont fontWithName:@"Courier" size:10];
    tv.text = logText;
    tv.editable = NO;
    [logWindow addSubview:tv];
    
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(20, h-50, 100, 40);
    copyBtn.backgroundColor = [UIColor systemBlueColor];
    copyBtn.layer.cornerRadius = 8;
    [copyBtn setTitle:@"📋 Копировать" forState:UIControlStateNormal];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w-120, h-50, 100, 40);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 8;
    [closeBtn setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [closeBtn addTarget:self action:@selector(closeLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:closeBtn];
    
    [logWindow makeKeyAndVisible];
}

+ (void)closeLogWindow {
    logWindow.hidden = YES;
}

+ (void)copyLog {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = logText;
    
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(120, 300, 120, 40)];
    toast.backgroundColor = [UIColor blackColor];
    toast.textColor = [UIColor whiteColor];
    toast.text = @"✅ Скопировано";
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 8;
    [[self mainWindow] addSubview:toast];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [toast removeFromSuperview];
    });
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
            
            [ButtonHandler addLog:@"✅ Твик загружен"];
            [ButtonHandler addLog:@"📋 Копируй адреса и жми ВСТАВИТЬ"];
        });
    }
}
