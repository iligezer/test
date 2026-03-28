#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <substrate.h>

// ==================== RVA ИЗ IDA ====================
#define GLOBAL_PTR_RVA      0x8FC1A80
#define TRANSFORM_OFFSET    0xB8

// ==================== ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ====================
static UIView *menuContainer = nil;
static UIButton *menuButton = nil;
static UILabel *coordLabel = nil;
static BOOL isMenuVisible = NO;

// ==================== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ====================

uintptr_t getBase() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

struct Vector3 {
    float x, y, z;
};

struct Vector3 GetPlayerPosition() {
    struct Vector3 result = {0, 0, 0};
    
    uintptr_t base = getBase();
    if (base == 0) {
        NSLog(@"[ESP] Base not found");
        return result;
    }
    
    // 1. Глобальный указатель
    uintptr_t globalPtrAddr = base + GLOBAL_PTR_RVA;
    uintptr_t globalPtr = *(uintptr_t*)globalPtrAddr;
    NSLog(@"[ESP] globalPtr = 0x%llx", (unsigned long long)globalPtr);
    
    if (globalPtr == 0) return result;
    
    // 2. Разыменовываем
    uintptr_t obj = *(uintptr_t*)globalPtr;
    NSLog(@"[ESP] obj = 0x%llx", (unsigned long long)obj);
    
    if (obj == 0) return result;
    
    // 3. Получаем Transform
    uintptr_t transform = *(uintptr_t*)(obj + TRANSFORM_OFFSET);
    NSLog(@"[ESP] transform = 0x%llx", (unsigned long long)transform);
    
    if (transform == 0) return result;
    
    // 4. Читаем позицию
    result.x = *(float*)(transform + 0);
    result.y = *(float*)(transform + 4);
    result.z = *(float*)(transform + 8);
    
    NSLog(@"[ESP] Position: (%.2f, %.2f, %.2f)", result.x, result.y, result.z);
    
    return result;
}

// ==================== КЛАСС ДЛЯ ТАЙМЕРА ====================

@interface TimerHelper : NSObject
+ (void)updateCoordinates;
@end

@implementation TimerHelper
+ (void)updateCoordinates {
    if (!coordLabel) return;
    struct Vector3 pos = GetPlayerPosition();
    if (pos.x == 0 && pos.y == 0 && pos.z == 0) {
        coordLabel.text = @"❌ Ошибка! Смотри логи";
        coordLabel.textColor = [UIColor redColor];
    } else {
        coordLabel.text = [NSString stringWithFormat:@"X:%.0f  Y:%.0f  Z:%.0f", pos.x, pos.y, pos.z];
        coordLabel.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1];
    }
}
@end

// ==================== ФУНКЦИИ МЕНЮ ====================

static void showAlert(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

static void checkCoordinates() {
    struct Vector3 pos = GetPlayerPosition();
    NSString *message;
    if (pos.x == 0 && pos.y == 0 && pos.z == 0) {
        message = @"❌ Не удалось получить координаты!\n\nПроверь логи в консоли";
    } else {
        message = [NSString stringWithFormat:@"X: %.2f\nY: %.2f\nZ: %.2f", pos.x, pos.y, pos.z];
    }
    showAlert(@"Координаты игрока", message);
}

static void toggleMenu() {
    isMenuVisible = !isMenuVisible;
    menuContainer.hidden = !isMenuVisible;
}

static void dragButton(UIPanGestureRecognizer *gesture) {
    CGPoint translation = [gesture translationInView:menuButton.superview];
    CGPoint newCenter = CGPointMake(menuButton.center.x + translation.x, menuButton.center.y + translation.y);
    
    CGFloat halfWidth = menuButton.frame.size.width / 2;
    CGFloat halfHeight = menuButton.frame.size.height / 2;
    newCenter.x = MAX(halfWidth, MIN(newCenter.x, menuButton.superview.bounds.size.width - halfWidth));
    newCenter.y = MAX(halfHeight, MIN(newCenter.y, menuButton.superview.bounds.size.height - halfHeight));
    
    menuButton.center = newCenter;
    [gesture setTranslation:CGPointZero inView:menuButton.superview];
    
    // Меню следует за кнопкой
    CGRect frame = menuContainer.frame;
    frame.origin.x = menuButton.frame.origin.x;
    frame.origin.y = menuButton.frame.origin.y + menuButton.frame.size.height + 5;
    menuContainer.frame = frame;
}

static void setupMenu() {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    
    // Кнопка-меню
    menuButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    menuButton.frame = CGRectMake(keyWindow.bounds.size.width - 70, 60, 50, 50);
    menuButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.9];
    menuButton.layer.cornerRadius = 25;
    [menuButton setTitle:@"⚡" forState:UIControlStateNormal];
    [menuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    menuButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [menuButton addTarget:nil action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:@selector(dragButton:)];
    [menuButton addGestureRecognizer:pan];
    [keyWindow addSubview:menuButton];
    
    // Контейнер меню
    menuContainer = [[UIView alloc] initWithFrame:CGRectMake(menuButton.frame.origin.x, 
                                                              menuButton.frame.origin.y + 55, 
                                                              220, 140)];
    menuContainer.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.95];
    menuContainer.layer.cornerRadius = 12;
    menuContainer.hidden = YES;
    menuContainer.userInteractionEnabled = YES;
    
    // Заголовок
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, 220, 28)];
    title.text = @"Modern Strike ESP";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [menuContainer addSubview:title];
    
    // Кнопка "Координаты"
    UIButton *coordBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    coordBtn.frame = CGRectMake(10, 45, 200, 38);
    coordBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1];
    coordBtn.layer.cornerRadius = 8;
    [coordBtn setTitle:@"📍 Мои координаты" forState:UIControlStateNormal];
    [coordBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    coordBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [coordBtn addTarget:nil action:@selector(checkCoordinates) forControlEvents:UIControlEventTouchUpInside];
    [menuContainer addSubview:coordBtn];
    
    // Метка с координатами
    coordLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 95, 210, 35)];
    coordLabel.text = @"X: ?  Y: ?  Z: ?";
    coordLabel.textColor = [UIColor colorWithRed:0.7 green:0.7 blue:0.7 alpha:1];
    coordLabel.font = [UIFont systemFontOfSize:11];
    coordLabel.textAlignment = NSTextAlignmentCenter;
    coordLabel.numberOfLines = 2;
    [menuContainer addSubview:coordLabel];
    
    [keyWindow addSubview:menuContainer];
    
    // Обновляем координаты раз в секунду
    [NSTimer scheduledTimerWithTimeInterval:1.0 
                                     target:[TimerHelper class]
                                   selector:@selector(updateCoordinates)
                                   userInfo:nil
                                    repeats:YES];
    
    NSLog(@"[ESP] Menu setup complete!");
    
    // Проверяем при запуске
    GetPlayerPosition();
}

static void loadMenu() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].keyWindow) {
            setupMenu();
        } else {
            loadMenu();
        }
    });
}

%ctor {
    NSLog(@"[ESP] Tweak loaded!");
    loadMenu();
}
