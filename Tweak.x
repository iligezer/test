#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <substrate.h>

// ==================== СМЕЩЕНИЯ ====================

#define UTILITIES_TYPEINFO_RVA          0x8E15248
#define PLAYERCONTROLLER_OFFSET_CANDIDATE_1   0x28
#define PLAYERCONTROLLER_OFFSET_CANDIDATE_2   0x30
#define AXEARMS_OFFSET                  0x150
#define TRANSFORM_POSITION_OFFSET       0x20

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

// Функция для чтения позиции по заданному смещению
struct Vector3 GetPositionAtOffset(int playerOffset) {
    struct Vector3 result = {0, 0, 0};
    
    uintptr_t base = getBase();
    if (base == 0) {
        NSLog(@"[ESP] Base = 0");
        return result;
    }
    
    // 1. Utilities TypeInfo
    uintptr_t typeInfo = base + UTILITIES_TYPEINFO_RVA;
    NSLog(@"[ESP] TypeInfo = 0x%llx", (unsigned long long)typeInfo);
    
    // 2. static_fields
    uintptr_t static_fields = *(uintptr_t*)(typeInfo + 0x08);
    NSLog(@"[ESP] static_fields = 0x%llx", (unsigned long long)static_fields);
    if (static_fields == 0) return result;
    
    // 3. FirstPersonController (читаем по тестовому смещению)
    uintptr_t firstPersonController = *(uintptr_t*)(static_fields + playerOffset);
    NSLog(@"[ESP] FirstPersonController (offset 0x%02x) = 0x%llx", playerOffset, (unsigned long long)firstPersonController);
    if (firstPersonController == 0) return result;
    
    // 4. Transform (AxeArms)
    uintptr_t transform = *(uintptr_t*)(firstPersonController + AXEARMS_OFFSET);
    NSLog(@"[ESP] Transform = 0x%llx", (unsigned long long)transform);
    if (transform == 0) return result;
    
    // 5. Position
    result.x = *(float*)(transform + TRANSFORM_POSITION_OFFSET);
    result.y = *(float*)(transform + TRANSFORM_POSITION_OFFSET + 4);
    result.z = *(float*)(transform + TRANSFORM_POSITION_OFFSET + 8);
    NSLog(@"[ESP] Position = (%.2f, %.2f, %.2f)", result.x, result.y, result.z);
    
    return result;
}

// ==================== КЛАСС МЕНЮ ====================

@interface TestMenu : NSObject
+ (void)setup;
@end

@implementation TestMenu

static UIView *menuContainer = nil;
static UIButton *menuButton = nil;
static UILabel *coordLabel28 = nil;
static UILabel *coordLabel30 = nil;
static BOOL isMenuVisible = NO;

+ (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

+ (void)checkBothOffsets {
    struct Vector3 pos28 = GetPositionAtOffset(PLAYERCONTROLLER_OFFSET_CANDIDATE_1);
    struct Vector3 pos30 = GetPositionAtOffset(PLAYERCONTROLLER_OFFSET_CANDIDATE_2);
    
    NSString *message = [NSString stringWithFormat:
        @"Смещение 0x28:\n  X: %.2f\n  Y: %.2f\n  Z: %.2f\n\n"
        @"Смещение 0x30:\n  X: %.2f\n  Y: %.2f\n  Z: %.2f\n\n"
        @"🔍 Какие координаты выглядят реальными?\n"
        @"(Если оба нули — игра еще не загрузила игрока)",
        pos28.x, pos28.y, pos28.z,
        pos30.x, pos30.y, pos30.z];
    
    [self showAlert:@"Проверка смещений" message:message];
    
    // Обновляем лейблы
    if (coordLabel28) {
        if (pos28.x == 0 && pos28.y == 0 && pos28.z == 0) {
            coordLabel28.text = @"0x28: ❌ не найден";
            coordLabel28.textColor = [UIColor redColor];
        } else {
            coordLabel28.text = [NSString stringWithFormat:@"0x28: X:%.0f Y:%.0f Z:%.0f", pos28.x, pos28.y, pos28.z];
            coordLabel28.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1];
        }
    }
    
    if (coordLabel30) {
        if (pos30.x == 0 && pos30.y == 0 && pos30.z == 0) {
            coordLabel30.text = @"0x30: ❌ не найден";
            coordLabel30.textColor = [UIColor redColor];
        } else {
            coordLabel30.text = [NSString stringWithFormat:@"0x30: X:%.0f Y:%.0f Z:%.0f", pos30.x, pos30.y, pos30.z];
            coordLabel30.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1];
        }
    }
}

+ (void)updateBothCoordinates {
    struct Vector3 pos28 = GetPositionAtOffset(PLAYERCONTROLLER_OFFSET_CANDIDATE_1);
    struct Vector3 pos30 = GetPositionAtOffset(PLAYERCONTROLLER_OFFSET_CANDIDATE_2);
    
    if (coordLabel28) {
        if (pos28.x == 0 && pos28.y == 0 && pos28.z == 0) {
            coordLabel28.text = @"0x28: ❌";
            coordLabel28.textColor = [UIColor redColor];
        } else {
            coordLabel28.text = [NSString stringWithFormat:@"0x28: X:%.0f Y:%.0f", pos28.x, pos28.z];
            coordLabel28.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1];
        }
    }
    
    if (coordLabel30) {
        if (pos30.x == 0 && pos30.y == 0 && pos30.z == 0) {
            coordLabel30.text = @"0x30: ❌";
            coordLabel30.textColor = [UIColor redColor];
        } else {
            coordLabel30.text = [NSString stringWithFormat:@"0x30: X:%.0f Y:%.0f", pos30.x, pos30.z];
            coordLabel30.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1];
        }
    }
}

+ (void)toggleMenu {
    isMenuVisible = !isMenuVisible;
    menuContainer.hidden = !isMenuVisible;
}

+ (void)dragButton:(UIPanGestureRecognizer *)gesture {
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

+ (void)setup {
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
    [menuButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
    [menuButton addGestureRecognizer:pan];
    
    [keyWindow addSubview:menuButton];
    
    // Меню (увеличил размер для двух строк координат)
    menuContainer = [[UIView alloc] initWithFrame:CGRectMake(menuButton.frame.origin.x, 
                                                              menuButton.frame.origin.y + 55, 
                                                              220, 210)];
    menuContainer.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.95];
    menuContainer.layer.cornerRadius = 12;
    menuContainer.hidden = YES;
    menuContainer.userInteractionEnabled = YES;
    
    // Заголовок
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, 220, 28)];
    title.text = @"Modern Strike ESP Test";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [menuContainer addSubview:title];
    
    // Кнопка проверки
    UIButton *checkBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    checkBtn.frame = CGRectMake(10, 45, 200, 38);
    checkBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1];
    checkBtn.layer.cornerRadius = 8;
    [checkBtn setTitle:@"🔍 Проверить оба смещения" forState:UIControlStateNormal];
    [checkBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    checkBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [checkBtn addTarget:self action:@selector(checkBothOffsets) forControlEvents:UIControlEventTouchUpInside];
    [menuContainer addSubview:checkBtn];
    
    // Координаты для 0x28
    coordLabel28 = [[UILabel alloc] initWithFrame:CGRectMake(5, 95, 210, 28)];
    coordLabel28.text = @"0x28: ?";
    coordLabel28.textColor = [UIColor lightGrayColor];
    coordLabel28.font = [UIFont systemFontOfSize:12];
    coordLabel28.textAlignment = NSTextAlignmentCenter;
    [menuContainer addSubview:coordLabel28];
    
    // Координаты для 0x30
    coordLabel30 = [[UILabel alloc] initWithFrame:CGRectMake(5, 125, 210, 28)];
    coordLabel30.text = @"0x30: ?";
    coordLabel30.textColor = [UIColor lightGrayColor];
    coordLabel30.font = [UIFont systemFontOfSize:12];
    coordLabel30.textAlignment = NSTextAlignmentCenter;
    [menuContainer addSubview:coordLabel30];
    
    // Подсказка
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(5, 160, 210, 40)];
    hint.text = @"💡 Зайди в матч, нажми кнопку\nКакие координаты меняются?";
    hint.textColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1];
    hint.font = [UIFont systemFontOfSize:10];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.numberOfLines = 2;
    [menuContainer addSubview:hint];
    
    [keyWindow addSubview:menuContainer];
    
    // Обновляем координаты каждые 2 секунды
    [NSTimer scheduledTimerWithTimeInterval:2.0 
                                     target:self 
                                   selector:@selector(updateBothCoordinates) 
                                   userInfo:nil 
                                    repeats:YES];
    
    NSLog(@"[ESP] Menu setup complete!");
}

@end

// ==================== ЗАГРУЗКА ====================

static void loadMenu() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].keyWindow) {
            [TestMenu setup];
        } else {
            loadMenu();
        }
    });
}

%ctor {
    NSLog(@"[ESP] Tweak loaded!");
    loadMenu();
}
