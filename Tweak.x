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

// Структура для хранения адреса и его значений
@interface AddressHistory : NSObject
@property (assign) unsigned long long address;
@property (strong) NSMutableArray *values; // история значений
@end

@implementation AddressHistory
- (instancetype)initWithAddress:(unsigned long long)addr {
    self = [super init];
    if (self) {
        self.address = addr;
        self.values = [NSMutableArray array];
    }
    return self;
}
@end

static NSMutableArray *trackedHistory = nil; // массив AddressHistory

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
+ (void)scanChanged;
+ (void)showChanged;
+ (void)showUnchanged;
+ (void)filterByCount:(BOOL)wantChanged;
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
    CGFloat menuWidth = 280;
    CGFloat menuHeight = 480;
    CGFloat menuX = ([UIScreen mainScreen].bounds.size.width - menuWidth) / 2;
    CGFloat menuY = ([UIScreen mainScreen].bounds.size.height - menuHeight) / 2;
    
    UIWindow *menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(menuX, menuY, menuWidth, menuHeight)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    menuWindow.layer.cornerRadius = 10;
    menuWindow.layer.borderWidth = 1;
    menuWindow.layer.borderColor = [UIColor whiteColor].CGColor;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 5, menuWidth, 25)];
    title.text = @"⚡ TRACKER";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:16];
    [menuWindow addSubview:title];
    
    int yPos = 35;
    int btnHeight = 35;
    int btnSpacing = 2;
    
    // Кнопка: ВСТАВИТЬ АДРЕС
    UIButton *pasteBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    pasteBtn.frame = CGRectMake(10, yPos, menuWidth-20, btnHeight);
    pasteBtn.backgroundColor = [UIColor systemBlueColor];
    pasteBtn.layer.cornerRadius = 6;
    [pasteBtn setTitle:@"📋 ВСТАВИТЬ АДРЕС" forState:UIControlStateNormal];
    [pasteBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    pasteBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [pasteBtn addTarget:self action:@selector(pasteAddress) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:pasteBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: ПОКАЗАТЬ ВСЕ
    UIButton *showBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    showBtn.frame = CGRectMake(10, yPos, menuWidth-20, btnHeight);
    showBtn.backgroundColor = [UIColor systemPurpleColor];
    showBtn.layer.cornerRadius = 6;
    [showBtn setTitle:@"📋 ПОКАЗАТЬ ВСЕ" forState:UIControlStateNormal];
    [showBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    showBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [showBtn addTarget:self action:@selector(showAddresses) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:showBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: НАЧАТЬ СКАНИРОВАНИЕ
    UIButton *startBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    startBtn.frame = CGRectMake(10, yPos, menuWidth-20, btnHeight);
    startBtn.backgroundColor = [UIColor systemGreenColor];
    startBtn.layer.cornerRadius = 6;
    [startBtn setTitle:@"🔍 НАЧАТЬ СКАНИРОВАНИЕ" forState:UIControlStateNormal];
    [startBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    startBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [startBtn addTarget:self action:@selector(startScan) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:startBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: ДОБАВИТЬ ИЗМЕНЕНИЕ
    UIButton *addBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    addBtn.frame = CGRectMake(10, yPos, menuWidth-20, btnHeight);
    addBtn.backgroundColor = [UIColor systemOrangeColor];
    addBtn.layer.cornerRadius = 6;
    [addBtn setTitle:@"📝 ДОБАВИТЬ ИЗМЕНЕНИЕ" forState:UIControlStateNormal];
    [addBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    addBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [addBtn addTarget:self action:@selector(scanChanged) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:addBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: ПОКАЗАТЬ ИЗМЕНИВШИЕСЯ
    UIButton *changedBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    changedBtn.frame = CGRectMake(10, yPos, menuWidth-20, btnHeight);
    changedBtn.backgroundColor = [UIColor systemIndigoColor];
    changedBtn.layer.cornerRadius = 6;
    [changedBtn setTitle:@"📈 ПОКАЗАТЬ ИЗМЕНИВШИЕСЯ" forState:UIControlStateNormal];
    [changedBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    changedBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [changedBtn addTarget:self action:@selector(showChanged) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:changedBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: ПОКАЗАТЬ НЕИЗМЕННЫЕ
    UIButton *unchangedBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    unchangedBtn.frame = CGRectMake(10, yPos, menuWidth-20, btnHeight);
    unchangedBtn.backgroundColor = [UIColor systemRedColor];
    unchangedBtn.layer.cornerRadius = 6;
    [unchangedBtn setTitle:@"📉 ПОКАЗАТЬ НЕИЗМЕННЫЕ" forState:UIControlStateNormal];
    [unchangedBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    unchangedBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [unchangedBtn addTarget:self action:@selector(showUnchanged) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:unchangedBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: ТОП КАНДИДАТЫ
    UIButton *candidatesBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    candidatesBtn.frame = CGRectMake(10, yPos, menuWidth-20, btnHeight);
    candidatesBtn.backgroundColor = [UIColor systemTealColor];
    candidatesBtn.layer.cornerRadius = 6;
    [candidatesBtn setTitle:@"🎯 ТОП КАНДИДАТЫ" forState:UIControlStateNormal];
    [candidatesBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    candidatesBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [candidatesBtn addTarget:self action:@selector(showCandidates) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:candidatesBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: ОЧИСТИТЬ
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.frame = CGRectMake(10, yPos, menuWidth-20, btnHeight);
    clearBtn.backgroundColor = [UIColor systemGrayColor];
    clearBtn.layer.cornerRadius = 6;
    [clearBtn setTitle:@"🗑️ ОЧИСТИТЬ" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    clearBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [clearBtn addTarget:self action:@selector(clearAddresses) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:clearBtn];
    
    yPos += btnHeight + btnSpacing;
    
    // Кнопка: ЗАКРЫТЬ
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(10, yPos, menuWidth-20, btnHeight);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 6;
    [closeBtn setTitle:@"✖️ ЗАКРЫТЬ" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
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
    if (!trackedHistory) {
        trackedHistory = [NSMutableArray array];
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
            // Проверяем, есть ли уже такой адрес
            BOOL exists = NO;
            for (AddressHistory *h in trackedHistory) {
                if (h.address == addr) {
                    exists = YES;
                    break;
                }
            }
            
            if (!exists) {
                AddressHistory *history = [[AddressHistory alloc] initWithAddress:addr];
                [trackedHistory addObject:history];
                [self addLog:[NSString stringWithFormat:@"✅ Вставлен: 0x%llx", addr]];
            } else {
                [self addLog:[NSString stringWithFormat:@"⏩ Уже есть: 0x%llx", addr]];
            }
            [self addLog:[NSString stringWithFormat:@"📊 Всего адресов: %lu", (unsigned long)trackedHistory.count]];
        } else {
            [self addLog:[NSString stringWithFormat:@"❌ Ошибка: %@", addrStr]];
        }
    } else {
        [self addLog:@"❌ Буфер пуст"];
    }
    [self updateLogWindow];
}

// ========== ПОКАЗАТЬ ВСЕ АДРЕСА ==========
+ (void)showAddresses {
    [self addLog:@"\n📋 СОХРАНЕННЫЕ АДРЕСА:"];
    
    if (!trackedHistory || trackedHistory.count == 0) {
        [self addLog:@"❌ Нет адресов"];
    } else {
        for (int i = 0; i < trackedHistory.count; i++) {
            AddressHistory *h = trackedHistory[i];
            [self addLog:[NSString stringWithFormat:@"%d. 0x%llx (%lu значений)", 
                          i+1, h.address, (unsigned long)h.values.count]];
        }
    }
    [self showLogWindow];
}

// ========== ОЧИСТИТЬ ВСЕ ==========
+ (void)clearAddresses {
    [trackedHistory removeAllObjects];
    [self addLog:@"🗑️ Все адреса очищены"];
    [self updateLogWindow];
}

// ========== НАЧАТЬ СКАНИРОВАНИЕ ==========
+ (void)startScan {
    if (!trackedHistory || trackedHistory.count == 0) {
        [self addLog:@"❌ Нет адресов для сканирования"];
        [self updateLogWindow];
        return;
    }
    
    // Расширяем каждый адрес в диапазоне ±0x800
    NSMutableArray *newHistory = [NSMutableArray array];
    int range = 0x800;
    int step = 4;
    
    for (AddressHistory *h in trackedHistory) {
        unsigned long long baseAddr = h.address;
        
        for (int offset = -range; offset <= range; offset += step) {
            unsigned long long newAddr = baseAddr + offset;
            
            // Проверяем, нет ли уже такого
            BOOL exists = NO;
            for (AddressHistory *existing in newHistory) {
                if (existing.address == newAddr) {
                    exists = YES;
                    break;
                }
            }
            
            if (!exists) {
                AddressHistory *newH = [[AddressHistory alloc] initWithAddress:newAddr];
                [newHistory addObject:newH];
            }
        }
    }
    
    trackedHistory = newHistory;
    
    [self addLog:[NSString stringWithFormat:@"\n🔍 РАСШИРЕННОЕ ДО %lu АДРЕСОВ", (unsigned long)trackedHistory.count]];
    
    // Читаем начальные значения
    task_t task = mach_task_self();
    int success = 0;
    
    for (AddressHistory *h in trackedHistory) {
        vm_address_t addr = (vm_address_t)h.address;
        float value = 0;
        vm_size_t data_read = 0;
        kern_return_t kr = vm_read_overwrite(task, addr, 4, (vm_address_t)&value, &data_read);
        
        if (kr == KERN_SUCCESS) {
            [h.values addObject:@(value)];
            success++;
        } else {
            [h.values addObject:@(0.0f)];
        }
    }
    
    [self addLog:[NSString stringWithFormat:@"✅ Успешно прочитано: %d", success]];
    [self addLog:@"📊 Двигайся и нажимай ДОБАВИТЬ ИЗМЕНЕНИЕ"];
    [self updateLogWindow];
}

// ========== ДОБАВИТЬ НОВОЕ ИЗМЕНЕНИЕ ==========
+ (void)scanChanged {
    if (!trackedHistory || trackedHistory.count == 0) {
        [self addLog:@"❌ Нет адресов для сканирования"];
        [self updateLogWindow];
        return;
    }
    
    task_t task = mach_task_self();
    int success = 0;
    
    for (AddressHistory *h in trackedHistory) {
        vm_address_t addr = (vm_address_t)h.address;
        float value = 0;
        vm_size_t data_read = 0;
        kern_return_t kr = vm_read_overwrite(task, addr, 4, (vm_address_t)&value, &data_read);
        
        if (kr == KERN_SUCCESS) {
            [h.values addObject:@(value)];
            success++;
        } else {
            [h.values addObject:@(0.0f)];
        }
    }
    
    [self addLog:[NSString stringWithFormat:@"📝 Добавлено %d новых значений", success]];
    [self addLog:[NSString stringWithFormat:@"📊 Всего записей: %lu", (unsigned long)trackedHistory.count]];
    [self updateLogWindow];
}

// ========== ПОКАЗАТЬ ИЗМЕНИВШИЕСЯ ==========
+ (void)showChanged {
    [self filterByCount:YES];
}

// ========== ПОКАЗАТЬ НЕИЗМЕННЫЕ ==========
+ (void)showUnchanged {
    [self filterByCount:NO];
}

// ========== ФИЛЬТР ПО КОЛИЧЕСТВУ ИЗМЕНЕНИЙ ==========
+ (void)filterByCount:(BOOL)wantChanged {
    if (!trackedHistory || trackedHistory.count == 0) {
        [self addLog:@"❌ Нет данных"];
        [self updateLogWindow];
        return;
    }
    
    NSMutableArray *filtered = [NSMutableArray array];
    
    for (AddressHistory *h in trackedHistory) {
        if (h.values.count < 2) continue;
        
        // Считаем сколько раз значение менялось
        int changes = 0;
        float lastValue = [h.values[0] floatValue];
        
        for (int i = 1; i < h.values.count; i++) {
            float val = [h.values[i] floatValue];
            if (fabs(val - lastValue) > 0.001f) {
                changes++;
                lastValue = val;
            }
        }
        
        if (wantChanged && changes > 0) {
            [filtered addObject:h];
        } else if (!wantChanged && changes == 0) {
            [filtered addObject:h];
        }
    }
    
    trackedHistory = filtered;
    
    [self addLog:[NSString stringWithFormat:@"\n🔍 После фильтра осталось: %lu", (unsigned long)trackedHistory.count]];
    [self updateLogWindow];
}

// ========== ПОКАЗАТЬ КАНДИДАТЫ ==========
+ (void)showCandidates {
    [self addLog:@"\n🎯 ТОП КАНДИДАТЫ (много изменений):"];
    
    if (!trackedHistory || trackedHistory.count == 0) {
        [self addLog:@"❌ Нет данных"];
    } else {
        // Сортируем по количеству изменений
        NSArray *sorted = [trackedHistory sortedArrayUsingComparator:^NSComparisonResult(AddressHistory *h1, AddressHistory *h2) {
            if (h1.values.count < 2) return NSOrderedAscending;
            if (h2.values.count < 2) return NSOrderedDescending;
            
            // Считаем изменения
            int changes1 = 0, changes2 = 0;
            float last1 = [h1.values[0] floatValue];
            float last2 = [h2.values[0] floatValue];
            
            for (int i = 1; i < h1.values.count; i++) {
                if (fabs([h1.values[i] floatValue] - last1) > 0.001f) changes1++;
                last1 = [h1.values[i] floatValue];
            }
            for (int i = 1; i < h2.values.count; i++) {
                if (fabs([h2.values[i] floatValue] - last2) > 0.001f) changes2++;
                last2 = [h2.values[i] floatValue];
            }
            
            return changes2 - changes1;
        }];
        
        int count = 0;
        for (AddressHistory *h in sorted) {
            if (h.values.count < 2) continue;
            if (count++ >= 20) break;
            
            // Показываем адрес и последние 3 значения
            int lastIdx = (int)h.values.count - 1;
            float v1 = [h.values[lastIdx] floatValue];
            float v2 = (lastIdx > 0) ? [h.values[lastIdx-1] floatValue] : 0;
            float v3 = (lastIdx > 1) ? [h.values[lastIdx-2] floatValue] : 0;
            
            [self addLog:[NSString stringWithFormat:@"%d. 0x%llx: %.3f | %.3f | %.3f", 
                          count, h.address, v3, v2, v1]];
            
            // Показываем возможные XYZ тройки
            if (count % 3 == 0) {
                [self addLog:@"   ---"];
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
            
            floatingButton = [[FloatingButton alloc] initWithFrame:CGRectMake(20, 150, 50, 50)];
            [mainWindow addSubview:floatingButton];
            
            [ButtonHandler addLog:@"✅ Твик загружен"];
            [ButtonHandler addLog:@"📋 Копируй адреса и жми ВСТАВИТЬ"];
        });
    }
}
