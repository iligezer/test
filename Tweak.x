#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

// ===== ПРОТОТИПЫ =====
uintptr_t getBaseAddress();
size_t safeRead(uintptr_t address, void *buffer, size_t size);

// ===== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ =====
static UIWindow *g_logWindow = nil;
static UITextView *g_logTextView = nil;
static NSMutableString *g_logText = nil;

// ===== РАБОТА С ПАМЯТЬЮ =====
uintptr_t getBaseAddress() {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework") != NULL) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

size_t safeRead(uintptr_t address, void *buffer, size_t size) {
    @try {
        vm_size_t bytesRead = 0;
        kern_return_t kr = vm_read_overwrite(current_task(), (vm_address_t)address, size, (vm_address_t)buffer, &bytesRead);
        return (kr == KERN_SUCCESS) ? bytesRead : 0;
    } @catch (NSException *e) {
        return 0;
    }
}

// ===== ДОБАВЛЕНИЕ ЛОГА В РЕАЛЬНОМ ВРЕМЕНИ =====
void addLog(NSString *format, ...) {
    if (!g_logText) {
        g_logText = [[NSMutableString alloc] init];
    }
    
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    [g_logText appendString:message];
    [g_logText appendString:@"\n"];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        g_logTextView.text = g_logText;
        
        // Автоскролл вниз
        if (g_logTextView.text.length > 0) {
            NSRange bottom = NSMakeRange(g_logTextView.text.length - 1, 1);
            [g_logTextView scrollRangeToVisible:bottom];
        }
    });
}

// ===== СОЗДАНИЕ ОКНА С ЛОГАМИ =====
void createLogWindow() {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) {
                    keyWindow = w;
                    break;
                }
            }
        }
        if (keyWindow) break;
    }
    
    if (!keyWindow) return;
    
    CGFloat width = keyWindow.frame.size.width - 40;
    CGFloat height = 450;
    
    g_logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 80, width, height)];
    g_logWindow.windowLevel = UIWindowLevelAlert + 2;
    g_logWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
    g_logWindow.layer.cornerRadius = 20;
    g_logWindow.layer.borderWidth = 2;
    g_logWindow.layer.borderColor = [UIColor systemBlueColor].CGColor;
    g_logWindow.hidden = NO;
    
    // Заголовок
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, width, 30)];
    title.text = @"📋 СКАНИРОВАНИЕ ПАМЯТИ";
    title.textColor = [UIColor systemBlueColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:18];
    [g_logWindow addSubview:title];
    
    // Текстовое поле для логов
    g_logTextView = [[UITextView alloc] initWithFrame:CGRectMake(15, 60, width - 30, 310)];
    g_logTextView.backgroundColor = [UIColor blackColor];
    g_logTextView.textColor = [UIColor greenColor];
    g_logTextView.font = [UIFont fontWithName:@"Courier" size:12];
    g_logTextView.editable = NO;
    g_logTextView.selectable = YES;
    g_logTextView.layer.cornerRadius = 10;
    [g_logWindow addSubview:g_logTextView];
    
    // Кнопка копирования
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.frame = CGRectMake(20, 390, (width - 50) / 2, 40);
    [copyBtn setTitle:@"📋 КОПИРОВАТЬ" forState:UIControlStateNormal];
    copyBtn.backgroundColor = [UIColor systemGreenColor];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    copyBtn.layer.cornerRadius = 10;
    copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [copyBtn addTarget:nil action:@selector(copyLogs) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:copyBtn];
    
    // Кнопка закрытия
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(30 + (width - 50) / 2, 390, (width - 50) / 2, 40);
    [closeBtn setTitle:@"❌ ЗАКРЫТЬ" forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor systemRedColor];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 10;
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [closeBtn addTarget:g_logWindow action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
    [g_logWindow addSubview:closeBtn];
    
    [g_logWindow makeKeyAndVisible];
}

// ===== ФУНКЦИЯ КОПИРОВАНИЯ =====
void copyLogs() {
    if (g_logTextView) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = g_logTextView.text;
        
        // Визуальное подтверждение
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅" message:@"Скопировано!" preferredStyle:UIAlertControllerStyleAlert];
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }
}

// ===== ПОЛНЫЙ СКАН (ОДНА ФУНКЦИЯ) =====
void startFullScan() {
    // Создаем окно с логами
    dispatch_async(dispatch_get_main_queue(), ^{
        createLogWindow();
        addLog(@"🔍 ПОЛНЫЙ СКАН ПАМЯТИ\n");
        addLog(@"⏳ Идет сканирование...\n");
    });
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        uintptr_t base = getBaseAddress();
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (base == 0) {
                addLog(@"❌ UnityFramework не найден!");
                return;
            }
            addLog([NSString stringWithFormat:@"📍 Базовый адрес: 0x%lx", base]);
            addLog(@"📊 Сканирую диапазон: 0x%lx - 0x%lx\n", base, base + 0x800000);
        });
        
        int healthCount = 0;
        int posCount = 0;
        int ptrCount = 0;
        int totalChecked = 0;
        
        // Сканируем
        for (uintptr_t addr = base; addr < base + 0x800000 && totalChecked < 20000; addr += 16) {
            totalChecked++;
            
            if (totalChecked % 1000 == 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    addLog(@"⏳ Проверено %d адресов...", totalChecked);
                });
            }
            
            // Ищем здоровье
            if (healthCount < 10) {
                float val;
                if (safeRead(addr, &val, sizeof(float)) == sizeof(float)) {
                    if (fabsf(val - 100.0f) < 0.01f) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            addLog(@"❤️ Здоровье: 0x%lx = 100.0", addr);
                        });
                        healthCount++;
                    }
                }
            }
            
            // Ищем позиции
            if (posCount < 10) {
                float x, y, z;
                if (safeRead(addr, &x, sizeof(float)) == sizeof(float) &&
                    safeRead(addr + 4, &y, sizeof(float)) == sizeof(float) &&
                    safeRead(addr + 8, &z, sizeof(float)) == sizeof(float)) {
                    
                    if (fabsf(x) < 1000 && fabsf(y) < 1000 && fabsf(z) < 1000 &&
                        (fabsf(x) > 0.1 || fabsf(y) > 0.1 || fabsf(z) > 0.1)) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            addLog(@"📍 Позиция: 0x%lx → X=%.1f Y=%.1f Z=%.1f", addr, x, y, z);
                        });
                        posCount++;
                    }
                }
            }
            
            // Ищем указатели
            if (ptrCount < 10) {
                uintptr_t ptr;
                if (safeRead(addr, &ptr, sizeof(uintptr_t)) == sizeof(uintptr_t)) {
                    if (ptr >= base && ptr < base + 0x800000) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            addLog(@"🔗 Указатель: 0x%lx → 0x%lx", addr, ptr);
                        });
                        ptrCount++;
                    }
                }
            }
        }
        
        // Итоги
        dispatch_async(dispatch_get_main_queue(), ^{
            addLog(@"\n📊 СКАНИРОВАНИЕ ЗАВЕРШЕНО!");
            addLog(@"✅ Проверено адресов: %d", totalChecked);
            addLog(@"✅ Найдено здоровья: %d", healthCount);
            addLog(@"✅ Найдено позиций: %d", posCount);
            addLog(@"✅ Найдено указателей: %d", ptrCount);
            
            if (healthCount == 0 && posCount == 0) {
                addLog(@"\n⚠️ Ничего не найдено. Возможно:");
                addLog(@"• Игра еще не загрузилась");
                addLog(@"• Значения изменились");
                addLog(@"• Нужен другой диапазон");
            }
        });
    });
}

// ===== ПЛАВАЮЩАЯ КНОПКА =====
@interface FloatButton : UIImageView
@property (nonatomic, copy) void (^actionBlock)(void);
@property (nonatomic, assign) CGPoint lastLocation;
@end

@implementation FloatButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 60, 60)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 30;
        self.layer.borderWidth = 2;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        self.userInteractionEnabled = YES;
        
        UILabel *label = [[UILabel alloc] initWithFrame:self.bounds];
        label.text = @"🔍";
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont boldSystemFontOfSize:28];
        [self addSubview:label];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
        [self addGestureRecognizer:pan];
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)dragButton:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.lastLocation = self.center;
    }
    
    CGPoint newCenter = CGPointMake(self.lastLocation.x + translation.x, self.lastLocation.y + translation.y);
    
    CGFloat half = 30;
    newCenter.x = MAX(half, MIN(self.superview.bounds.size.width - half, newCenter.x));
    newCenter.y = MAX(half + 50, MIN(self.superview.bounds.size.height - half - 50, newCenter.y));
    
    self.center = newCenter;
}

- (void)handleTap {
    if (self.actionBlock) self.actionBlock();
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block;
}

@end

// ===== ПРОПУСКАЮЩЕЕ ОКНО =====
@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *floatButton;
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.floatButton && !self.floatButton.hidden) {
        CGPoint buttonPoint = [self convertPoint:point toView:self.floatButton];
        if ([self.floatButton pointInside:buttonPoint withEvent:event]) {
            return self.floatButton;
        }
    }
    return nil;
}

@end

// ===== ГЛАВНЫЙ UI =====
@interface AimbotUI : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
@property (nonatomic, strong) FloatButton *floatButton;
@end

@implementation AimbotUI

- (instancetype)init {
    self = [super init];
    if (self) [self setupUI];
    return self;
}

- (void)setupUI {
    self.window = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.hidden = NO;
    
    self.floatButton = [[FloatButton alloc] init];
    self.window.floatButton = self.floatButton;
    [self.window addSubview:self.floatButton];
    
    __weak typeof(self) weakSelf = self;
    [self.floatButton setAction:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            startFullScan(); // Просто запускаем скан
        }
    }];
}

@end

// ===== ТОЧКА ВХОДА =====
static AimbotUI *g_ui = nil;

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_ui = [[AimbotUI alloc] init];
        NSLog(@"[SCAN] Твик загружен!");
    });
}
