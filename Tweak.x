#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <objc/runtime.h>

// ========== ТВОИ АДРЕСА ==========
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
static NSMutableArray *trackedAddresses = nil; // массив отслеживаемых адресов
static NSMutableArray *currentValues = nil;    // текущие значения
static NSMutableArray *previousValues = nil;   // предыдущие значения для сравнения
static int scanStep = 0;

// ========== ОБЪЯВЛЕНИЕ ==========
@interface ButtonHandler : NSObject
+ (void)showMenu;
+ (void)closeMenu;
+ (void)copyLog;
+ (void)showLogWindow;
+ (void)updateLogWindow;
+ (void)addLog:(NSString*)text;
+ (void)addAddress;
+ (void)resetScan;
+ (void)startScan;
+ (void)refreshChanged;
+ (void)refreshUnchanged;
+ (void)showCandidates;
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
    CGFloat menuHeight = 500;
    CGFloat menuX = ([UIScreen mainScreen].bounds.size.width - menuWidth) / 2;
    CGFloat menuY = ([UIScreen mainScreen].bounds.size.height - menuHeight) / 2;
    
    UIWindow *menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(menuX, menuY, menuWidth, menuHeight)];
    menuWindow.windowLevel = UIWindowLevelAlert + 3;
    menuWindow.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    menuWindow.layer.cornerRadius = 10;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, menuWidth, 30)];
    title.text = @"⚡ ADDRESS TRACKER";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    [menuWindow addSubview:title];
    
    // Кнопка: ДОБАВИТЬ АДРЕС
    UIButton *addBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    addBtn.frame = CGRectMake(20, 50, menuWidth-40, 40);
    addBtn.backgroundColor = [UIColor systemBlueColor];
    [addBtn setTitle:@"➕ ДОБАВИТЬ АДРЕС" forState:UIControlStateNormal];
    [addBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [addBtn addTarget:self action:@selector(addAddress) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:addBtn];
    
    // Кнопка: НАЧАТЬ СКАНИРОВАНИЕ
    UIButton *startBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    startBtn.frame = CGRectMake(20, 100, menuWidth-40, 40);
    startBtn.backgroundColor = [UIColor systemPurpleColor];
    [startBtn setTitle:@"🔍 НАЧАТЬ СКАНИРОВАНИЕ" forState:UIControlStateNormal];
    [startBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [startBtn addTarget:self action:@selector(startScan) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:startBtn];
    
    // Кнопка: ИЗМЕНИЛОСЬ
    UIButton *changedBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    changedBtn.frame = CGRectMake(20, 150, menuWidth-40, 40);
    changedBtn.backgroundColor = [UIColor systemGreenColor];
    [changedBtn setTitle:@"📈 ИЗМЕНИЛОСЬ" forState:UIControlStateNormal];
    [changedBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [changedBtn addTarget:self action:@selector(refreshChanged) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:changedBtn];
    
    // Кнопка: НЕ ИЗМЕНИЛОСЬ
    UIButton *unchangedBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    unchangedBtn.frame = CGRectMake(20, 200, menuWidth-40, 40);
    unchangedBtn.backgroundColor = [UIColor systemOrangeColor];
    [unchangedBtn setTitle:@"📉 НЕ ИЗМЕНИЛОСЬ" forState:UIControlStateNormal];
    [unchangedBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [unchangedBtn addTarget:self action:@selector(refreshUnchanged) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:unchangedBtn];
    
    // Кнопка: ПОКАЗАТЬ КАНДИДАТОВ
    UIButton *showBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    showBtn.frame = CGRectMake(20, 250, menuWidth-40, 40);
    showBtn.backgroundColor = [UIColor systemIndigoColor];
    [showBtn setTitle:@"📋 ПОКАЗАТЬ КАНДИДАТОВ" forState:UIControlStateNormal];
    [showBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [showBtn addTarget:self action:@selector(showCandidates) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:showBtn];
    
    // Кнопка: СБРОС
    UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    resetBtn.frame = CGRectMake(20, 300, menuWidth-40, 40);
    resetBtn.backgroundColor = [UIColor systemRedColor];
    [resetBtn setTitle:@"🔄 СБРОС" forState:UIControlStateNormal];
    [resetBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [resetBtn addTarget:self action:@selector(resetScan) forControlEvents:UIControlEventTouchUpInside];
    [menuWindow addSubview:resetBtn];
    
    // Кнопка: ЗАКРЫТЬ
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(20, 350, menuWidth-40, 40);
    closeBtn.backgroundColor = [UIColor systemGrayColor];
    [closeBtn setTitle:@"✖️ ЗАКРЫТЬ" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
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

// ========== ДОБАВИТЬ АДРЕС ==========
+ (void)addAddress {
    if (!trackedAddresses) trackedAddresses = [NSMutableArray array];
    
    // Используем UIAlertController с полем ввода
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Добавить адрес"
                                                                   message:@"Введите адрес в формате 0x281764090"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"0x...";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    
    UIAlertAction *addAction = [UIAlertAction actionWithTitle:@"Добавить" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *textField = alert.textFields.firstObject;
        NSString *addrStr = textField.text;
        
        if (addrStr.length > 0) {
            unsigned long long addr = 0;
            NSScanner *scanner = [NSScanner scannerWithString:addrStr];
            
            // Пробуем разные форматы
            if ([scanner scanHexLongLong:&addr]) {
                [trackedAddresses addObject:@(addr)];
                [self addLog:[NSString stringWithFormat:@"✅ Добавлен адрес: 0x%llx", addr]];
                [self addLog:[NSString stringWithFormat:@"📊 Всего адресов: %lu", (unsigned long)trackedAddresses.count]];
            } else {
                [self addLog:@"❌ Неверный формат. Используй 0x281764090"];
            }
        }
    }];
    
    UIAlertAction *doneAction = [UIAlertAction actionWithTitle:@"Готово" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self addLog:@"✅ Ввод адресов завершен"];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:addAction];
    [alert addAction:doneAction];
    [alert addAction:cancelAction];
    
    // Показываем алерт
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

// ========== НАЧАТЬ СКАНИРОВАНИЕ ==========
+ (void)startScan {
    if (!trackedAddresses || trackedAddresses.count == 0) {
        [self addLog:@"❌ Сначала добавь адреса"];
        [self updateLogWindow];
        return;
    }
    
    currentValues = [NSMutableArray array];
    previousValues = [NSMutableArray array];
    
    task_t task = mach_task_self();
    
    for (NSNumber *addrNum in trackedAddresses) {
        vm_address_t addr = [addrNum unsignedLongLongValue];
        
        // Читаем текущее значение
        float value = 0;
        vm_size_t data_read = 0;
        kern_return_t kr = vm_read_overwrite(task, addr, 4, (vm_address_t)&value, &data_read);
        
        if (kr == KERN_SUCCESS) {
            [currentValues addObject:@(value)];
            [self addLog:[NSString stringWithFormat:@"📌 Адрес 0x%llx = %.3f", (unsigned long long)addr, value]];
        } else {
            [currentValues addObject:@(0.0f)];
            [self addLog:[NSString stringWithFormat:@"❌ Не удалось прочитать 0x%llx", (unsigned long long)addr]];
        }
    }
    
    previousValues = [currentValues mutableCopy];
    scanStep = 1;
    
    [self addLog:@"\n✅ Начальное сканирование завершено"];
    [self addLog:@"📊 Двигайся и нажимай ИЗМЕНИЛОСЬ/НЕ ИЗМЕНИЛОСЬ"];
    [self updateLogWindow];
}

// ========== ИЗМЕНИЛОСЬ ==========
+ (void)refreshChanged {
    if (!trackedAddresses || trackedAddresses.count == 0) {
        [self addLog:@"❌ Сначала начни сканирование"];
        [self updateLogWindow];
        return;
    }
    
    NSMutableArray *newAddresses = [NSMutableArray array];
    NSMutableArray *newValues = [NSMutableArray array];
    task_t task = mach_task_self();
    
    for (int i = 0; i < trackedAddresses.count; i++) {
        NSNumber *addrNum = trackedAddresses[i];
        vm_address_t addr = [addrNum unsignedLongLongValue];
        
        // Читаем текущее значение
        float value = 0;
        vm_size_t data_read = 0;
        kern_return_t kr = vm_read_overwrite(task, addr, 4, (vm_address_t)&value, &data_read);
        
        if (kr == KERN_SUCCESS) {
            float oldValue = [currentValues[i] floatValue];
            
            // Если значение изменилось (с допуском 0.001)
            if (fabs(value - oldValue) > 0.001f) {
                [newAddresses addObject:addrNum];
                [newValues addObject:@(value)];
                [self addLog:[NSString stringWithFormat:@"✅ ИЗМЕНИЛОСЬ 0x%llx: %.3f -> %.3f", 
                              (unsigned long long)addr, oldValue, value]];
            }
        }
    }
    
    trackedAddresses = newAddresses;
    currentValues = newValues;
    
    [self addLog:[NSString stringWithFormat:@"\n📊 Осталось адресов: %lu", (unsigned long)trackedAddresses.count]];
    [self updateLogWindow];
}

// ========== НЕ ИЗМЕНИЛОСЬ ==========
+ (void)refreshUnchanged {
    if (!trackedAddresses || trackedAddresses.count == 0) {
        [self addLog:@"❌ Сначала начни сканирование"];
        [self updateLogWindow];
        return;
    }
    
    NSMutableArray *newAddresses = [NSMutableArray array];
    NSMutableArray *newValues = [NSMutableArray array];
    task_t task = mach_task_self();
    
    for (int i = 0; i < trackedAddresses.count; i++) {
        NSNumber *addrNum = trackedAddresses[i];
        vm_address_t addr = [addrNum unsignedLongLongValue];
        
        // Читаем текущее значение
        float value = 0;
        vm_size_t data_read = 0;
        kern_return_t kr = vm_read_overwrite(task, addr, 4, (vm_address_t)&value, &data_read);
        
        if (kr == KERN_SUCCESS) {
            float oldValue = [currentValues[i] floatValue];
            
            // Если значение НЕ изменилось
            if (fabs(value - oldValue) <= 0.001f) {
                [newAddresses addObject:addrNum];
                [newValues addObject:@(value)];
                [self addLog:[NSString stringWithFormat:@"✅ НЕ ИЗМЕНИЛОСЬ 0x%llx: %.3f", 
                              (unsigned long long)addr, value]];
            }
        }
    }
    
    trackedAddresses = newAddresses;
    currentValues = newValues;
    
    [self addLog:[NSString stringWithFormat:@"\n📊 Осталось адресов: %lu", (unsigned long)trackedAddresses.count]];
    [self updateLogWindow];
}

// ========== ПОКАЗАТЬ КАНДИДАТОВ ==========
+ (void)showCandidates {
    [self addLog:@"\n📋 ТЕКУЩИЕ КАНДИДАТЫ:"];
    
    if (!trackedAddresses || trackedAddresses.count == 0) {
        [self addLog:@"❌ Нет адресов для отслеживания"];
    } else {
        for (int i = 0; i < trackedAddresses.count; i++) {
            NSNumber *addrNum = trackedAddresses[i];
            float value = [currentValues[i] floatValue];
            [self addLog:[NSString stringWithFormat:@"%d. 0x%llx = %.3f", 
                          i+1, (unsigned long long)[addrNum unsignedLongLongValue], value]];
        }
    }
    
    [self showLogWindow];
}

// ========== СБРОС ==========
+ (void)resetScan {
    [trackedAddresses removeAllObjects];
    [currentValues removeAllObjects];
    [previousValues removeAllObjects];
    scanStep = 0;
    [self addLog:@"🔄 СКАНИРОВАНИЕ СБРОШЕНО"];
    [self updateLogWindow];
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
    [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [logWindow addSubview:copyBtn];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w-120, h-50, 100, 40);
    closeBtn.backgroundColor = [UIColor systemRedColor];
    closeBtn.layer.cornerRadius = 8;
    [closeBtn setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
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

+ (UIViewController*)topViewController {
    UIWindow *window = [self mainWindow];
    if (!window) return nil;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }
    return vc;
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
            [ButtonHandler addLog:@"⚡ Нажми кнопку для меню"];
        });
    }
}
