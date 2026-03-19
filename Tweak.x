#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>

// ===== ПРОТОТИПЫ =====
void showResultWindow(NSString *text);
uintptr_t getBaseAddress();

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

// Безопасное чтение памяти
size_t safeRead(uintptr_t address, void *buffer, size_t size) {
    vm_size_t bytesRead = 0;
    kern_return_t kr = vm_read_overwrite(current_task(), (vm_address_t)address, size, (vm_address_t)buffer, &bytesRead);
    return (kr == KERN_SUCCESS) ? bytesRead : 0;
}

// ===== ПОЛНЫЙ СКАН ОДНОЙ КНОПКОЙ =====
void fullMemoryScan() {
    NSMutableString *log = [NSMutableString stringWithString:@"🔍 ПОЛНЫЙ СКАН ПАМЯТИ\n\n"];
    
    uintptr_t base = getBaseAddress();
    if (base == 0) {
        [log appendString:@"❌ UnityFramework не найден\n"];
        showResultWindow(log);
        return;
    }
    
    [log appendFormat:@"📍 Базовый адрес: 0x%lx\n", base];
    [log appendString:@"📊 Сканирование...\n\n"];
    
    int healthCount = 0;
    int posCount = 0;
    int ptrCount = 0;
    
    // Сканируем с шагом 16 байт для скорости
    for (uintptr_t addr = base; addr < base + 0x2000000; addr += 16) {
        // Ищем здоровье (100.0)
        float val;
        if (safeRead(addr, &val, sizeof(float)) == sizeof(float)) {
            if (fabsf(val - 100.0f) < 0.01f && healthCount < 10) {
                [log appendFormat:@"❤️ Здоровье: 0x%lx = 100.0\n", addr];
                healthCount++;
            }
        }
        
        // Ищем позиции (X, Y, Z)
        float x, y, z;
        if (safeRead(addr, &x, sizeof(float)) == sizeof(float) &&
            safeRead(addr + 4, &y, sizeof(float)) == sizeof(float) &&
            safeRead(addr + 8, &z, sizeof(float)) == sizeof(float)) {
            
            if (fabsf(x) < 1000 && fabsf(y) < 1000 && fabsf(z) < 1000 &&
                (fabsf(x) > 1 || fabsf(y) > 1 || fabsf(z) > 1) && posCount < 10) {
                [log appendFormat:@"📍 Позиция: 0x%lx → X=%.1f Y=%.1f Z=%.1f\n", addr, x, y, z];
                posCount++;
            }
        }
        
        // Ищем указатели на объекты
        uintptr_t ptr;
        if (safeRead(addr, &ptr, sizeof(uintptr_t)) == sizeof(uintptr_t)) {
            if (ptr >= base && ptr < base + 0x2000000 && ptrCount < 10) {
                [log appendFormat:@"🔗 Указатель: 0x%lx → 0x%lx\n", addr, ptr];
                ptrCount++;
            }
        }
    }
    
    [log appendString:@"\n📋 ИТОГИ:\n"];
    [log appendFormat:@"• Найдено здоровья: %d\n", healthCount];
    [log appendFormat:@"• Найдено позиций: %d\n", posCount];
    [log appendFormat:@"• Найдено указателей: %d\n", ptrCount];
    
    [log appendString:@"\n💡 Теперь запусти Il2CppDumper и сравни адреса"];
    
    showResultWindow(log);
}

// ===== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ДЛЯ ОКНА РЕЗУЛЬТАТОВ =====
static UITextView *g_textView = nil;
static UIButton *g_copyBtn = nil;

void copyLogToClipboard() {
    if (g_textView) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = g_textView.text;
        
        // Визуальное подтверждение
        if (g_copyBtn) {
            UIColor *originalColor = g_copyBtn.backgroundColor;
            NSString *originalTitle = [g_copyBtn titleForState:UIControlStateNormal];
            
            g_copyBtn.backgroundColor = [UIColor systemOrangeColor];
            [g_copyBtn setTitle:@"✅ СКОПИРОВАНО" forState:UIControlStateNormal];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                g_copyBtn.backgroundColor = originalColor;
                [g_copyBtn setTitle:originalTitle forState:UIControlStateNormal];
            });
        }
    }
}

// ===== ОКНО РЕЗУЛЬТАТОВ С КНОПКОЙ КОПИРОВАНИЯ =====
void showResultWindow(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
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
        
        CGFloat windowWidth = keyWindow.frame.size.width - 40;
        UIWindow *resultWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 80, windowWidth, 450)];
        resultWindow.windowLevel = UIWindowLevelAlert + 2;
        resultWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.98];
        resultWindow.layer.cornerRadius = 20;
        resultWindow.layer.borderWidth = 2;
        resultWindow.layer.borderColor = [UIColor systemBlueColor].CGColor;
        resultWindow.hidden = NO;
        
        // Заголовок
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, windowWidth, 30)];
        title.text = @"📋 РЕЗУЛЬТАТЫ СКАНА";
        title.textColor = [UIColor systemBlueColor];
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont boldSystemFontOfSize:18];
        [resultWindow addSubview:title];
        
        // Текст с результатами
        g_textView = [[UITextView alloc] initWithFrame:CGRectMake(15, 60, windowWidth - 30, 300)];
        g_textView.backgroundColor = [UIColor blackColor];
        g_textView.textColor = [UIColor greenColor];
        g_textView.font = [UIFont fontWithName:@"Courier" size:12];
        g_textView.text = text;
        g_textView.editable = NO;
        g_textView.selectable = YES;
        g_textView.layer.cornerRadius = 10;
        [resultWindow addSubview:g_textView];
        
        // Кнопка копирования
        g_copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        g_copyBtn.frame = CGRectMake(20, 380, (windowWidth - 50) / 2, 45);
        [g_copyBtn setTitle:@"📋 КОПИРОВАТЬ" forState:UIControlStateNormal];
        g_copyBtn.backgroundColor = [UIColor systemGreenColor];
        [g_copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        g_copyBtn.layer.cornerRadius = 12;
        g_copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [g_copyBtn addTarget:self action:@selector(copyLogToClipboard) forControlEvents:UIControlEventTouchUpInside];
        [resultWindow addSubview:g_copyBtn];
        
        // Кнопка закрытия
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(30 + (windowWidth - 50) / 2, 380, (windowWidth - 50) / 2, 45);
        [closeBtn setTitle:@"❌ ЗАКРЫТЬ" forState:UIControlStateNormal];
        closeBtn.backgroundColor = [UIColor systemRedColor];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        closeBtn.layer.cornerRadius = 12;
        closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [closeBtn addTarget:resultWindow action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
        [resultWindow addSubview:closeBtn];
        
        [resultWindow makeKeyAndVisible];
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
        
        // Тень
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowOpacity = 0.5;
        self.layer.shadowRadius = 6;
        
        // Иконка
        UILabel *label = [[UILabel alloc] initWithFrame:self.bounds];
        label.text = @"🔍";
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont boldSystemFontOfSize:28];
        [self addSubview:label];
        
        // Жесты
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
    
    // Ограничения
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
@property (nonatomic, weak) UIView *menuView;
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.floatButton && !self.floatButton.hidden) {
        CGPoint buttonPoint = [self convertPoint:point toView:self.floatButton];
        if ([self.floatButton pointInside:buttonPoint withEvent:event]) {
            return self.floatButton;
        }
    }
    if (self.menuView && !self.menuView.hidden) {
        CGPoint menuPoint = [self convertPoint:point toView:self.menuView];
        if ([self.menuView pointInside:menuPoint withEvent:event]) {
            return [self.menuView hitTest:menuPoint withEvent:event];
        }
    }
    return nil;
}

@end

// ===== ПРОСТОЕ МЕНЮ =====
@interface SimpleMenuView : UIView
@property (nonatomic, strong) UIButton *closeButton;
@end

@implementation SimpleMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupSimpleStyle];
    }
    return self;
}

- (void)setupSimpleStyle {
    CGFloat width = 260;
    CGFloat height = 200;
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    
    self.frame = CGRectMake((screenWidth - width) / 2, (screenHeight - height) / 2, width, height);
    
    // Фон
    self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.layer.cornerRadius = 20;
    self.layer.borderWidth = 2;
    self.layer.borderColor = [UIColor systemBlueColor].CGColor;
    
    // Тень
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 8);
    self.layer.shadowOpacity = 0.5;
    self.layer.shadowRadius = 12;
    
    // Заголовок
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, width, 30)];
    title.text = @"🎯 ESP SCANNER";
    title.textColor = [UIColor systemBlueColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:18];
    [self addSubview:title];
    
    // Кнопка сканирования
    UIButton *scanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    scanBtn.frame = CGRectMake(30, 60, 200, 50);
    [scanBtn setTitle:@"🔍 ПОЛНЫЙ СКАН" forState:UIControlStateNormal];
    scanBtn.backgroundColor = [UIColor systemBlueColor];
    [scanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    scanBtn.layer.cornerRadius = 12;
    scanBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    scanBtn.tag = 1;
    [self addSubview:scanBtn];
    
    // Кнопка закрытия
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.frame = CGRectMake(30, 125, 200, 45);
    [self.closeButton setTitle:@"❌ ЗАКРЫТЬ" forState:UIControlStateNormal];
    self.closeButton.backgroundColor = [UIColor systemGrayColor];
    [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeButton.layer.cornerRadius = 12;
    self.closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self addSubview:self.closeButton];
}

@end

// ===== ГЛАВНЫЙ UI =====
@interface AimbotUI : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
@property (nonatomic, strong) FloatButton *floatButton;
@property (nonatomic, strong) SimpleMenuView *menuView;
@property (nonatomic, assign) BOOL menuVisible;
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
            [strongSelf toggleMenu];
        }
    }];
    
    [self buildSimpleMenu];
}

- (void)buildSimpleMenu {
    self.menuView = [[SimpleMenuView alloc] initWithFrame:CGRectZero];
    self.menuView.hidden = YES;
    self.window.menuView = self.menuView;
    [self.window addSubview:self.menuView];
    
    // Назначаем действия
    for (UIView *view in self.menuView.subviews) {
        if ([view isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)view;
            if (btn.tag == 1) {
                [btn addTarget:self action:@selector(scanAction) forControlEvents:UIControlEventTouchUpInside];
            } else {
                [btn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
            }
        }
    }
}

- (void)toggleMenu {
    self.menuVisible = !self.menuVisible;
    
    if (self.menuVisible) {
        self.menuView.hidden = NO;
        self.menuView.transform = CGAffineTransformMakeScale(0.8, 0.8);
        self.menuView.alpha = 0;
        [UIView animateWithDuration:0.3 animations:^{
            self.menuView.transform = CGAffineTransformIdentity;
            self.menuView.alpha = 1;
        }];
    } else {
        [UIView animateWithDuration:0.2 animations:^{
            self.menuView.transform = CGAffineTransformMakeScale(0.8, 0.8);
            self.menuView.alpha = 0;
        } completion:^(BOOL finished) {
            self.menuView.hidden = YES;
            self.menuView.transform = CGAffineTransformIdentity;
        }];
    }
}

- (void)scanAction {
    [self toggleMenu]; // Закрываем меню
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        fullMemoryScan(); // Сканируем в фоне
    });
}

@end

// ===== ТОЧКА ВХОДА =====
static AimbotUI *g_ui = nil;

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_ui = [[AimbotUI alloc] init];
        NSLog(@"[ESP] Твик загружен!");
    });
}
