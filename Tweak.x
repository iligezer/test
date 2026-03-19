#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>

// ===== ПРОТОТИПЫ =====
void showResultWindow(NSString *text);
void showLoadingIndicator();
void hideLoadingIndicator();
uintptr_t getBaseAddress();

// ===== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ =====
static UITextView *g_textView = nil;
static UIButton *g_copyBtn = nil;
static UIWindow *g_loadingWindow = nil;
static UIActivityIndicatorView *g_spinner = nil;
static UILabel *g_loadingLabel = nil;

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

// Безопасное чтение памяти с try-catch
size_t safeRead(uintptr_t address, void *buffer, size_t size) {
    @try {
        vm_size_t bytesRead = 0;
        kern_return_t kr = vm_read_overwrite(current_task(), (vm_address_t)address, size, (vm_address_t)buffer, &bytesRead);
        return (kr == KERN_SUCCESS) ? bytesRead : 0;
    } @catch (NSException *e) {
        return 0;
    }
}

// ===== ИНДИКАТОР ЗАГРУЗКИ =====
void showLoadingIndicator() {
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
        
        // Создаем окно загрузки
        g_loadingWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 150, 120)];
        g_loadingWindow.center = keyWindow.center;
        g_loadingWindow.windowLevel = UIWindowLevelAlert + 3;
        g_loadingWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        g_loadingWindow.layer.cornerRadius = 20;
        g_loadingWindow.layer.borderWidth = 2;
        g_loadingWindow.layer.borderColor = [UIColor systemBlueColor].CGColor;
        g_loadingWindow.hidden = NO;
        
        // Спиннер
        g_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        g_spinner.center = CGPointMake(75, 40);
        g_spinner.color = [UIColor systemBlueColor];
        [g_spinner startAnimating];
        [g_loadingWindow addSubview:g_spinner];
        
        // Текст
        g_loadingLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 70, 150, 30)];
        g_loadingLabel.text = @"СКАНИРУЮ...";
        g_loadingLabel.textColor = [UIColor whiteColor];
        g_loadingLabel.textAlignment = NSTextAlignmentCenter;
        g_loadingLabel.font = [UIFont boldSystemFontOfSize:14];
        [g_loadingWindow addSubview:g_loadingLabel];
        
        [g_loadingWindow makeKeyAndVisible];
    });
}

void hideLoadingIndicator() {
    dispatch_async(dispatch_get_main_queue(), ^{
        [g_spinner stopAnimating];
        g_loadingWindow.hidden = YES;
        g_loadingWindow = nil;
    });
}

// ===== ПОЛНЫЙ СКАН С ЗАЩИТОЙ =====
void fullMemoryScan() {
    NSMutableString *log = [NSMutableString stringWithString:@"🔍 ПОЛНЫЙ СКАН ПАМЯТИ\n\n"];
    
    uintptr_t base = getBaseAddress();
    if (base == 0) {
        [log appendString:@"❌ UnityFramework не найден\n"];
        hideLoadingIndicator();
        showResultWindow(log);
        return;
    }
    
    [log appendFormat:@"📍 Базовый адрес: 0x%lx\n", base];
    [log appendString:@"📊 Сканирование...\n\n"];
    
    int healthCount = 0;
    int posCount = 0;
    int ptrCount = 0;
    
    // Сканируем меньший диапазон и с большим шагом для безопасности
    uintptr_t startAddr = base;
    uintptr_t endAddr = base + 0x800000; // 8 MB вместо 32 MB
    
    [log appendFormat:@"📏 Диапазон: 0x%lx - 0x%lx\n\n", startAddr, endAddr];
    
    int totalChecks = 0;
    int maxResults = 15; // Ограничиваем количество результатов
    
    for (uintptr_t addr = startAddr; addr < endAddr && totalChecks < 50000; addr += 32) {
        totalChecks++;
        
        @autoreleasepool {
            // Ищем здоровье (100.0)
            if (healthCount < maxResults) {
                float val;
                if (safeRead(addr, &val, sizeof(float)) == sizeof(float)) {
                    if (fabsf(val - 100.0f) < 0.01f) {
                        [log appendFormat:@"❤️ Здоровье: 0x%lx = 100.0\n", addr];
                        healthCount++;
                    }
                }
            }
            
            // Ищем позиции (X, Y, Z)
            if (posCount < maxResults) {
                float x, y, z;
                if (safeRead(addr, &x, sizeof(float)) == sizeof(float) &&
                    safeRead(addr + 4, &y, sizeof(float)) == sizeof(float) &&
                    safeRead(addr + 8, &z, sizeof(float)) == sizeof(float)) {
                    
                    if (fabsf(x) < 1000 && fabsf(y) < 1000 && fabsf(z) < 1000 &&
                        (fabsf(x) > 0.1 || fabsf(y) > 0.1 || fabsf(z) > 0.1)) {
                        [log appendFormat:@"📍 Позиция: 0x%lx → X=%.1f Y=%.1f Z=%.1f\n", addr, x, y, z];
                        posCount++;
                    }
                }
            }
            
            // Ищем указатели
            if (ptrCount < maxResults) {
                uintptr_t ptr;
                if (safeRead(addr, &ptr, sizeof(uintptr_t)) == sizeof(uintptr_t)) {
                    if (ptr >= base && ptr < base + 0x800000) {
                        [log appendFormat:@"🔗 Указатель: 0x%lx → 0x%lx\n", addr, ptr];
                        ptrCount++;
                    }
                }
            }
        }
    }
    
    [log appendString:@"\n📊 ИТОГИ:\n"];
    [log appendFormat:@"• Проверено адресов: %d\n", totalChecks];
    [log appendFormat:@"• Найдено здоровья: %d\n", healthCount];
    [log appendFormat:@"• Найдено позиций: %d\n", posCount];
    [log appendFormat:@"• Найдено указателей: %d\n", ptrCount];
    
    if (healthCount == 0 && posCount == 0) {
        [log appendString:@"\n⚠️ Ничего не найдено. Возможно:\n"];
        [log appendString:@"• Игра еще не загрузилась\n"];
        [log appendString:@"• Значения изменились (здоровье не 100)\n"];
        [log appendString:@"• Нужен другой диапазон\n"];
    }
    
    hideLoadingIndicator();
    showResultWindow(log);
}

// ===== КОПИРОВАНИЕ В БУФЕР =====
void copyLogToClipboard() {
    if (g_textView) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = g_textView.text;
        
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

// ===== ОКНО РЕЗУЛЬТАТОВ =====
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
        
        // Текст
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
        [g_copyBtn addTarget:nil action:@selector(copyLogToClipboard) forControlEvents:UIControlEventTouchUpInside];
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
        
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowOpacity = 0.5;
        self.layer.shadowRadius = 6;
        
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

// ===== МЕНЮ =====
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
    
    self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.layer.cornerRadius = 20;
    self.layer.borderWidth = 2;
    self.layer.borderColor = [UIColor systemBlueColor].CGColor;
    
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 8);
    self.layer.shadowOpacity = 0.5;
    self.layer.shadowRadius = 12;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, width, 30)];
    title.text = @"🎯 ESP SCANNER";
    title.textColor = [UIColor systemBlueColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:18];
    [self addSubview:title];
    
    UIButton *scanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    scanBtn.frame = CGRectMake(30, 60, 200, 50);
    [scanBtn setTitle:@"🔍 ПОЛНЫЙ СКАН" forState:UIControlStateNormal];
    scanBtn.backgroundColor = [UIColor systemBlueColor];
    [scanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    scanBtn.layer.cornerRadius = 12;
    scanBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    scanBtn.tag = 1;
    [self addSubview:scanBtn];
    
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
    // НЕ закрываем меню сразу! Показываем индикатор
    self.menuView.hidden = YES; // скрываем меню
    showLoadingIndicator(); // показываем "СКАНИРУЮ..."
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        fullMemoryScan(); // сканируем
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
