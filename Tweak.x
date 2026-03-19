#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>

// ===== ПРОТОТИПЫ =====
void showResultWindow(NSString *text);
uintptr_t getBaseAddress();
void searchForHealthValues();
void searchForPlayerPositions();
void searchForGameManager();

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

// Функция для чтения памяти процесса
size_t readMemory(uintptr_t address, void *buffer, size_t size) {
    vm_size_t bytesRead = 0;
    kern_return_t kr = vm_read_overwrite(current_task(), (vm_address_t)address, size, (vm_address_t)buffer, &bytesRead);
    if (kr != KERN_SUCCESS) {
        return 0;
    }
    return bytesRead;
}

// ПОИСК ЗНАЧЕНИЙ ЗДОРОВЬЯ (100.0)
void searchForHealthValues() {
    NSMutableString *log = [NSMutableString stringWithString:@"❤️ ПОИСК ЗДОРОВЬЯ (100.0)\n\n"];
    
    uintptr_t base = getBaseAddress();
    if (base == 0) {
        [log appendString:@"❌ UnityFramework не найден\n"];
        showResultWindow(log);
        return;
    }
    
    [log appendFormat:@"📍 Базовый адрес: 0x%lx\n", base];
    [log appendFormat:@"📍 Диапазон поиска: 0x%lx - 0x%lx\n", base, base + 0x4000000]; // ~64 MB
    
    float targetValue = 100.0f;
    float foundValues[1000];
    uintptr_t foundAddresses[1000];
    int foundCount = 0;
    
    [log appendString:@"\n🔍 Сканирование...\n"];
    
    // Сканируем память с шагом 4 байта (размер float)
    for (uintptr_t addr = base; addr < base + 0x4000000 && foundCount < 100; addr += 4) {
        float value = 0;
        if (readMemory(addr, &value, sizeof(float)) == sizeof(float)) {
            // Проверяем, близко ли значение к 100.0 (с погрешностью)
            if (fabsf(value - targetValue) < 0.01f) {
                foundAddresses[foundCount] = addr;
                foundValues[foundCount] = value;
                foundCount++;
            }
        }
    }
    
    if (foundCount > 0) {
        [log appendFormat:@"✅ Найдено %d значений 100.0\n\n", foundCount];
        for (int i = 0; i < foundCount && i < 20; i++) {
            [log appendFormat:@"   0x%lx = %.2f\n", foundAddresses[i], foundValues[i]];
        }
        if (foundCount > 20) {
            [log appendFormat:@"   ... и еще %d\n", foundCount - 20];
        }
        
        [log appendString:@"\n📝 Это могут быть:\n"];
        [log appendString:@"   • PlayerHealth.health\n"];
        [log appendString:@"   • EnemyBaseScript.enemyHealth\n"];
        [log appendString:@"   • Другие значения\n"];
    } else {
        [log appendString:@"❌ Значений 100.0 не найдено\n"];
        [log appendString:@"   Возможно, игра еще не загружена\n"];
        [log appendString:@"   или здоровье изменилось\n"];
    }
    
    showResultWindow(log);
}

// ПОИСК ПОЗИЦИЙ (X, Y, Z координаты)
void searchForPlayerPositions() {
    NSMutableString *log = [NSMutableString stringWithString:@"📍 ПОИСК ПОЗИЦИЙ\n\n"];
    
    uintptr_t base = getBaseAddress();
    if (base == 0) {
        [log appendString:@"❌ UnityFramework не найден\n"];
        showResultWindow(log);
        return;
    }
    
    [log appendFormat:@"📍 Базовый адрес: 0x%lx\n", base];
    
    // Ищем паттерн: три float подряд (X, Y, Z)
    [log appendString:@"\n🔍 Поиск координат (X, Y, Z)...\n"];
    
    float positions[1000][3];
    uintptr_t posAddresses[1000];
    int posCount = 0;
    
    // Ищем группы из трех float подряд
    for (uintptr_t addr = base; addr < base + 0x4000000 && posCount < 50; addr += 4) {
        float x, y, z;
        if (readMemory(addr, &x, sizeof(float)) == sizeof(float) &&
            readMemory(addr + 4, &y, sizeof(float)) == sizeof(float) &&
            readMemory(addr + 8, &z, sizeof(float)) == sizeof(float)) {
            
            // Проверяем, похоже ли на координаты (не слишком большие, не слишком маленькие)
            if (fabsf(x) < 1000 && fabsf(y) < 1000 && fabsf(z) < 1000 &&
                (fabsf(x) > 0.1 || fabsf(y) > 0.1 || fabsf(z) > 0.1)) {
                
                positions[posCount][0] = x;
                positions[posCount][1] = y;
                positions[posCount][2] = z;
                posAddresses[posCount] = addr;
                posCount++;
            }
        }
    }
    
    if (posCount > 0) {
        [log appendFormat:@"✅ Найдено %d возможных позиций\n\n", posCount];
        for (int i = 0; i < posCount && i < 10; i++) {
            [log appendFormat:@"   0x%lx: X=%.2f Y=%.2f Z=%.2f\n", 
             posAddresses[i], positions[i][0], positions[i][1], positions[i][2]];
        }
        if (posCount > 10) {
            [log appendFormat:@"   ... и еще %d\n", posCount - 10];
        }
    } else {
        [log appendString:@"❌ Позиции не найдены\n"];
    }
    
    showResultWindow(log);
}

// ПОИСК GameManager по паттерну
void searchForGameManager() {
    NSMutableString *log = [NSMutableString stringWithString:@"🎮 ПОИСК GAMEMANAGER\n\n"];
    
    uintptr_t base = getBaseAddress();
    if (base == 0) {
        [log appendString:@"❌ UnityFramework не найден\n"];
        showResultWindow(log);
        return;
    }
    
    [log appendFormat:@"📍 Базовый адрес: 0x%lx\n", base];
    [log appendString:@"\n🔍 Ищем указатели на GameManager...\n"];
    
    // Ищем указатели, которые могут вести на GameManager
    uintptr_t possiblePointers[100];
    int ptrCount = 0;
    
    for (uintptr_t addr = base; addr < base + 0x4000000 && ptrCount < 50; addr += 8) {
        uintptr_t value = 0;
        if (readMemory(addr, &value, sizeof(uintptr_t)) == sizeof(uintptr_t)) {
            // Проверяем, указывает ли адрес в диапазон игры
            if (value >= base && value < base + 0x4000000) {
                possiblePointers[ptrCount] = addr;
                ptrCount++;
            }
        }
    }
    
    [log appendFormat:@"✅ Найдено %d указателей на память игры\n", ptrCount];
    [log appendString:@"\n📋 Для точного определения GameManager нужно:\n"];
    [log appendString:@"1. Запустить игру\n"];
    [log appendString:@"2. Найти уникальные значения\n"];
    [log appendString:@"3. Сравнить с дампом Il2CppDumper\n"];
    
    showResultWindow(log);
}

// ПОИСК ВСЕГО И СРАЗУ (комбо)
void searchAllForESP() {
    NSMutableString *log = [NSMutableString stringWithString:@"🔬 ПОЛНОЕ СКАНИРОВАНИЕ ДЛЯ ESP\n\n"];
    
    uintptr_t base = getBaseAddress();
    if (base == 0) {
        [log appendString:@"❌ UnityFramework не найден\n"];
        showResultWindow(log);
        return;
    }
    
    [log appendFormat:@"📍 UnityFramework: 0x%lx\n", base];
    [log appendString:@"📊 Анализ структуры памяти...\n\n"];
    
    // 1. Ищем здоровье
    [log appendString:@"❤️ ЗДОРОВЬЕ (100.0):\n"];
    int healthCount = 0;
    for (uintptr_t addr = base; addr < base + 0x2000000 && healthCount < 5; addr += 4) {
        float val;
        if (readMemory(addr, &val, sizeof(float)) == sizeof(float)) {
            if (fabsf(val - 100.0f) < 0.01f) {
                [log appendFormat:@"   0x%lx = 100.0\n", addr];
                healthCount++;
            }
        }
    }
    if (healthCount == 0) [log appendString:@"   ❌ Не найдено\n"];
    
    // 2. Ищем позиции
    [log appendString:@"\n📍 ПОЗИЦИИ (X,Y,Z):\n"];
    int posCount = 0;
    for (uintptr_t addr = base; addr < base + 0x2000000 && posCount < 3; addr += 4) {
        float x, y, z;
        if (readMemory(addr, &x, sizeof(float)) && 
            readMemory(addr+4, &y, sizeof(float)) && 
            readMemory(addr+8, &z, sizeof(float))) {
            if (fabsf(x) < 100 && fabsf(y) < 100 && fabsf(z) < 100) {
                [log appendFormat:@"   0x%lx: %.1f, %.1f, %.1f\n", addr, x, y, z];
                posCount++;
            }
        }
    }
    
    // 3. Советы по ESP
    [log appendString:@"\n📋 ЧТО ДАЛЬШЕ:\n"];
    [log appendString:@"1. Запусти Il2CppDumper\n"];
    [log appendString:@"2. Найди в script.json:\n"];
    [log appendString:@"   - GameManager::Instance\n"];
    [log appendString:@"   - PlayerController::_health\n"];
    [log appendString:@"   - PlayerController::_transform\n"];
    [log appendString:@"3. Подставь адреса в код\n"];
    
    showResultWindow(log);
}

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
        
        UIWindow *resultWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, keyWindow.frame.size.width - 40, 450)];
        resultWindow.windowLevel = UIWindowLevelAlert + 2;
        resultWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        resultWindow.layer.cornerRadius = 20;
        resultWindow.layer.borderWidth = 2;
        resultWindow.layer.borderColor = [UIColor systemPinkColor].CGColor;
        resultWindow.hidden = NO;
        
        // Заголовок
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 15, resultWindow.frame.size.width, 30)];
        title.text = @"🔍 РЕЗУЛЬТАТЫ ПОИСКА";
        title.textColor = [UIColor systemPinkColor];
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont boldSystemFontOfSize:18];
        [resultWindow addSubview:title];
        
        // Текст
        UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(15, 60, resultWindow.frame.size.width - 30, 310)];
        textView.backgroundColor = [UIColor blackColor];
        textView.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.2 alpha:1.0];
        textView.font = [UIFont fontWithName:@"Courier" size:12];
        textView.text = text;
        textView.editable = NO;
        textView.selectable = YES;
        textView.layer.cornerRadius = 10;
        [resultWindow addSubview:textView];
        
        // Кнопка закрытия
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(resultWindow.frame.size.width/2 - 60, 390, 120, 40);
        [closeBtn setTitle:@"ЗАКРЫТЬ" forState:UIControlStateNormal];
        closeBtn.backgroundColor = [UIColor systemPinkColor];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        closeBtn.layer.cornerRadius = 12;
        closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        [closeBtn addTarget:resultWindow action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
        [resultWindow addSubview:closeBtn];
        
        [resultWindow makeKeyAndVisible];
    });
}

// ===== КРАСИВАЯ ПЛАВАЮЩАЯ КНОПКА =====
@interface FloatButton : UIImageView
@property (nonatomic, copy) void (^actionBlock)(void);
@property (nonatomic, assign) CGPoint lastLocation;
- (void)setAction:(void (^)(void))block;
@end

@implementation FloatButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 70, 70)];
    if (self) {
        // Градиентный фон
        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.frame = self.bounds;
        gradient.colors = @[(id)[UIColor systemBlueColor].CGColor, (id)[UIColor systemPurpleColor].CGColor];
        gradient.startPoint = CGPointMake(0, 0);
        gradient.endPoint = CGPointMake(1, 1);
        gradient.cornerRadius = 35;
        [self.layer insertSublayer:gradient atIndex:0];
        
        self.layer.cornerRadius = 35;
        self.layer.borderWidth = 3;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        self.userInteractionEnabled = YES;
        
        // Тени
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 6);
        self.layer.shadowOpacity = 0.6;
        self.layer.shadowRadius = 8;
        
        // Иконка
        UILabel *label = [[UILabel alloc] initWithFrame:self.bounds];
        label.text = @"⚡";
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont boldSystemFontOfSize:32];
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
    CGFloat half = self.frame.size.width / 2;
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

// ===== СУПЕР-КРАСИВОЕ МЕНЮ =====
@interface ModernMenuView : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@end

@implementation ModernMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupSuperStyle];
    }
    return self;
}

- (void)setupSuperStyle {
    CGFloat width = 320;
    CGFloat height = 500;
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    
    self.frame = CGRectMake((screenWidth - width) / 2, (screenHeight - height) / 2, width, height);
    
    // Блюр с эффектом стекла
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurView.frame = self.bounds;
    self.blurView.layer.cornerRadius = 30;
    self.blurView.layer.masksToBounds = YES;
    self.blurView.alpha = 0.95;
    [self addSubview:self.blurView];
    
    // Градиентная обводка
    self.layer.cornerRadius = 30;
    self.layer.borderWidth = 2;
    self.layer.borderColor = [UIColor clearColor].CGColor;
    
    // Тень
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 15);
    self.layer.shadowOpacity = 0.5;
    self.layer.shadowRadius = 25;
    
    // Верхний акцент
    UIView *topAccent = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 4)];
    
    // Градиент для акцента
    CAGradientLayer *accentGradient = [CAGradientLayer layer];
    accentGradient.frame = topAccent.bounds;
    accentGradient.colors = @[(id)[UIColor systemPinkColor].CGColor, 
                              (id)[UIColor systemPurpleColor].CGColor, 
                              (id)[UIColor systemBlueColor].CGColor];
    accentGradient.startPoint = CGPointMake(0, 0);
    accentGradient.endPoint = CGPointMake(1, 0);
    [topAccent.layer addSublayer:accentGradient];
    
    [self addSubview:topAccent];
    
    // Заголовок
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, width - 80, 40)];
    self.titleLabel.text = @"🎯 ESP MASTER";
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [self addSubview:self.titleLabel];
    
    // Кнопка закрытия
    self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.closeButton.frame = CGRectMake(width - 50, 20, 35, 35);
    [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.closeButton.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
    self.closeButton.layer.cornerRadius = 17.5;
    self.closeButton.layer.borderWidth = 1;
    self.closeButton.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.closeButton addTarget:self action:@selector(hideMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.closeButton];
    
    // Декоративный элемент
    UIView *decorLine = [[UIView alloc] initWithFrame:CGRectMake(20, 65, width - 40, 1)];
    decorLine.backgroundColor = [UIColor colorWithWhite:1 alpha:0.2];
    [self addSubview:decorLine];
}

- (void)hideMenu {
    self.hidden = YES;
}

- (UIButton *)createStylishButtonWithTitle:(NSString *)title icon:(NSString *)icon color:(UIColor *)color yPos:(CGFloat)yPos {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(20, yPos, self.frame.size.width - 40, 55);
    button.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.7];
    button.layer.cornerRadius = 18;
    button.layer.borderWidth = 1;
    button.layer.borderColor = [color colorWithAlphaComponent:0.5].CGColor;
    
    // Иконка слева
    UILabel *iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 30, 55)];
    iconLabel.text = icon;
    iconLabel.font = [UIFont systemFontOfSize:22];
    iconLabel.textColor = color;
    [button addSubview:iconLabel];
    
    // Заголовок
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(55, 0, 150, 55)];
    titleLabel.text = title;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [button addSubview:titleLabel];
    
    // Стрелка справа
    UILabel *arrowLabel = [[UILabel alloc] initWithFrame:CGRectMake(button.frame.size.width - 35, 0, 20, 55)];
    arrowLabel.text = @"→";
    arrowLabel.textColor = color;
    arrowLabel.font = [UIFont boldSystemFontOfSize:20];
    [button addSubview:arrowLabel];
    
    return button;
}

- (void)addToggleWithTitle:(NSString *)title icon:(NSString *)icon color:(UIColor *)color yPos:(CGFloat)yPos {
    UIView *rowView = [[UIView alloc] initWithFrame:CGRectMake(20, yPos, self.frame.size.width - 40, 55)];
    rowView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.7];
    rowView.layer.cornerRadius = 18;
    rowView.layer.borderWidth = 1;
    rowView.layer.borderColor = [color colorWithAlphaComponent:0.3].CGColor;
    
    // Иконка
    UILabel *iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 30, 55)];
    iconLabel.text = icon;
    iconLabel.font = [UIFont systemFontOfSize:22];
    iconLabel.textColor = color;
    [rowView addSubview:iconLabel];
    
    // Заголовок
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(55, 0, 150, 55)];
    titleLabel.text = title;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:16];
    [rowView addSubview:titleLabel];
    
    // Кастомный свитч
    UISwitch *switchCtrl = [[UISwitch alloc] initWithFrame:CGRectMake(rowView.frame.size.width - 65, 12, 50, 30)];
    switchCtrl.onTintColor = color;
    switchCtrl.thumbTintColor = [UIColor whiteColor];
    [rowView addSubview:switchCtrl];
    
    [self addSubview:rowView];
}

@end

// ===== ГЛАВНЫЙ UI =====
@interface AimbotUI : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
@property (nonatomic, strong) FloatButton *floatButton;
@property (nonatomic, strong) ModernMenuView *menuView;
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
    
    [self buildBeautifulMenu];
}

- (void)buildBeautifulMenu {
    self.menuView = [[ModernMenuView alloc] initWithFrame:CGRectZero];
    self.menuView.hidden = YES;
    self.window.menuView = self.menuView;
    [self.window addSubview:self.menuView];
    
    CGFloat yPos = 95;
    
    // Кнопка 1: Полное сканирование
    UIButton *scanAllBtn = [self.menuView createStylishButtonWithTitle:@"FULL SCAN" icon:@"🔬" color:[UIColor systemPinkColor] yPos:yPos];
    [scanAllBtn addTarget:self action:@selector(scanAllAction) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:scanAllBtn];
    
    yPos += 70;
    
    // Кнопка 2: Поиск здоровья
    UIButton *healthBtn = [self.menuView createStylishButtonWithTitle:@"HEALTH SCAN" icon:@"❤️" color:[UIColor systemRedColor] yPos:yPos];
    [healthBtn addTarget:self action:@selector(searchHealthAction) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:healthBtn];
    
    yPos += 70;
    
    // Кнопка 3: Поиск позиций
    UIButton *posBtn = [self.menuView createStylishButtonWithTitle:@"POSITIONS" icon:@"📍" color:[UIColor systemGreenColor] yPos:yPos];
    [posBtn addTarget:self action:@selector(searchPositionsAction) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:posBtn];
    
    yPos += 70;
    
    // Кнопка 4: GameManager
    UIButton *gmBtn = [self.menuView createStylishButtonWithTitle:@"GAMEMANAGER" icon:@"🎮" color:[UIColor systemPurpleColor] yPos:yPos];
    [gmBtn addTarget:self action:@selector(searchGMAction) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:gmBtn];
    
    yPos += 70;
    
    // Toggle для ESP (пока неактивен)
    [self.menuView addToggleWithTitle:@"ESP WALLHACK" icon:@"👁️" color:[UIColor systemBlueColor] yPos:yPos];
}

- (void)toggleMenu {
    self.menuVisible = !self.menuVisible;
    
    if (self.menuVisible) {
        self.menuView.hidden = NO;
        self.menuView.transform = CGAffineTransformMakeScale(0.9, 0.9);
        self.menuView.alpha = 0;
        [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
            self.menuView.transform = CGAffineTransformIdentity;
            self.menuView.alpha = 1;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.3 animations:^{
            self.menuView.transform = CGAffineTransformMakeScale(0.9, 0.9);
            self.menuView.alpha = 0;
        } completion:^(BOOL finished) {
            self.menuView.hidden = YES;
            self.menuView.transform = CGAffineTransformIdentity;
        }];
    }
}

// ACTIONS
- (void)scanAllAction {
    searchAllForESP();
}

- (void)searchHealthAction {
    searchForHealthValues();
}

- (void)searchPositionsAction {
    searchForPlayerPositions();
}

- (void)searchGMAction {
    searchForGameManager();
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
