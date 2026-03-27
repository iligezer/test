#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <substrate.h>

// ==================== СМЕЩЕНИЯ ДЛЯ iOS (Modern Strike Online) ====================

// Utilities TypeInfo (найден в IDA)
#define UTILITIES_TYPEINFO_RVA          0x8E15248

// Смещения полей (найдены в IDA)
#define PLAYERCONTROLLER_OFFSET         0x30        // _playerController в static_fields
#define AXEARMS_OFFSET                  0x150       // FirstPersonController -> AxeArms
#define TRANSFORM_POSITION_OFFSET       0x20        // Transform.position

// RVA функций (найдены в script.json)
#define GET_PLAYERCONTROLLER_RVA        0x32494cc
#define CAMERA_GET_MAIN_RVA             0x445baf8
#define WORLD_TO_SCREEN_POINT_RVA       0x445a9cc

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

// Получить позицию игрока
Vector3 GetPlayerPosition() {
    Vector3 result = {0, 0, 0};
    
    uintptr_t base = getBase();
    if (base == 0) {
        NSLog(@"[ESP] Base not found");
        return result;
    }
    
    NSLog(@"[ESP] Base: 0x%llx", (unsigned long long)base);
    
    // 1. Utilities TypeInfo
    uintptr_t typeInfo = base + UTILITIES_TYPEINFO_RVA;
    NSLog(@"[ESP] TypeInfo: 0x%llx", (unsigned long long)typeInfo);
    
    // 2. static_fields (TypeInfo + 0x08)
    uintptr_t static_fields = *(uintptr_t*)(typeInfo + 0x08);
    NSLog(@"[ESP] static_fields: 0x%llx", (unsigned long long)static_fields);
    
    if (static_fields == 0) {
        NSLog(@"[ESP] static_fields is NULL");
        return result;
    }
    
    // 3. FirstPersonController (_playerController)
    uintptr_t firstPersonController = *(uintptr_t*)(static_fields + PLAYERCONTROLLER_OFFSET);
    NSLog(@"[ESP] FirstPersonController: 0x%llx", (unsigned long long)firstPersonController);
    
    if (firstPersonController == 0) {
        NSLog(@"[ESP] FirstPersonController is NULL");
        return result;
    }
    
    // 4. Transform (AxeArms)
    uintptr_t transform = *(uintptr_t*)(firstPersonController + AXEARMS_OFFSET);
    NSLog(@"[ESP] Transform: 0x%llx", (unsigned long long)transform);
    
    if (transform == 0) {
        NSLog(@"[ESP] Transform is NULL");
        return result;
    }
    
    // 5. Position
    result.x = *(float*)(transform + TRANSFORM_POSITION_OFFSET);
    result.y = *(float*)(transform + TRANSFORM_POSITION_OFFSET + 4);
    result.z = *(float*)(transform + TRANSFORM_POSITION_OFFSET + 8);
    
    NSLog(@"[ESP] Position: (%.2f, %.2f, %.2f)", result.x, result.y, result.z);
    
    return result;
}

// ==================== МЕНЮ И UI ====================

@interface TestMenu : UIView {
    UIButton *menuButton;
    UIView *menuView;
    UILabel *coordLabel;
    BOOL isMenuVisible;
}
@end

@implementation TestMenu

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        isMenuVisible = NO;
        [self setupMenuButton];
    }
    return self;
}

- (void)setupMenuButton {
    // Плавающая кнопка
    menuButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    menuButton.frame = CGRectMake(20, 100, 50, 50);
    menuButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.9];
    menuButton.layer.cornerRadius = 25;
    menuButton.layer.shadowColor = [UIColor blackColor].CGColor;
    menuButton.layer.shadowOffset = CGSizeMake(2, 2);
    menuButton.layer.shadowOpacity = 0.5;
    [menuButton setTitle:@"⚡" forState:UIControlStateNormal];
    [menuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    menuButton.titleLabel.font = [UIFont systemFontOfSize:24];
    [menuButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    // Добавляем возможность перетаскивать кнопку
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
    [menuButton addGestureRecognizer:pan];
    
    [self addSubview:menuButton];
    
    // Меню
    menuView = [[UIView alloc] initWithFrame:CGRectMake(20, 160, 250, 180)];
    menuView.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.95];
    menuView.layer.cornerRadius = 12;
    menuView.layer.borderWidth = 1;
    menuView.layer.borderColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1].CGColor;
    menuView.hidden = YES;
    
    // Заголовок
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 250, 30)];
    title.text = @"Modern Strike ESP Test";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:16];
    [menuView addSubview:title];
    
    // Кнопка проверки координат
    UIButton *checkButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    checkButton.frame = CGRectMake(20, 50, 210, 40);
    checkButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1];
    checkButton.layer.cornerRadius = 8;
    [checkButton setTitle:@"📍 Проверить координаты" forState:UIControlStateNormal];
    [checkButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    checkButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [checkButton addTarget:self action:@selector(checkCoordinates) forControlEvents:UIControlEventTouchUpInside];
    [menuView addSubview:checkButton];
    
    // Кнопка проверки смещений
    UIButton *offsetsButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    offsetsButton.frame = CGRectMake(20, 100, 210, 40);
    offsetsButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.3 blue:0.2 alpha:1];
    offsetsButton.layer.cornerRadius = 8;
    [offsetsButton setTitle:@"🔧 Проверить смещения" forState:UIControlStateNormal];
    [offsetsButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    offsetsButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [offsetsButton addTarget:self action:@selector(checkOffsets) forControlEvents:UIControlEventTouchUpInside];
    [menuView addSubview:offsetsButton];
    
    // Метка для вывода координат
    coordLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 150, 230, 20)];
    coordLabel.text = @"Координаты: ???";
    coordLabel.textColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1];
    coordLabel.font = [UIFont systemFontOfSize:11];
    coordLabel.textAlignment = NSTextAlignmentCenter;
    [menuView addSubview:coordLabel];
    
    [self addSubview:menuView];
}

- (void)dragButton:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self];
    CGRect newFrame = menuButton.frame;
    newFrame.origin.x += translation.x;
    newFrame.origin.y += translation.y;
    
    // Ограничиваем, чтобы кнопка не выходила за экран
    if (newFrame.origin.x < 0) newFrame.origin.x = 0;
    if (newFrame.origin.y < 0) newFrame.origin.y = 0;
    if (newFrame.origin.x + newFrame.size.width > self.frame.size.width) {
        newFrame.origin.x = self.frame.size.width - newFrame.size.width;
    }
    if (newFrame.origin.y + newFrame.size.height > self.frame.size.height) {
        newFrame.origin.y = self.frame.size.height - newFrame.size.height;
    }
    
    menuButton.frame = newFrame;
    [gesture setTranslation:CGPointZero inView:self];
    
    if (gesture.state == UIGestureRecognizerStateEnded) {
        // Сохраняем позицию кнопки
        [[NSUserDefaults standardUserDefaults] setFloat:newFrame.origin.x forKey:@"buttonX"];
        [[NSUserDefaults standardUserDefaults] setFloat:newFrame.origin.y forKey:@"buttonY"];
    }
}

- (void)toggleMenu {
    isMenuVisible = !isMenuVisible;
    menuView.hidden = !isMenuVisible;
}

- (void)checkCoordinates {
    NSLog(@"[ESP] ========== CHECK COORDINATES ==========");
    Vector3 pos = GetPlayerPosition();
    
    NSString *message;
    if (pos.x == 0 && pos.y == 0 && pos.z == 0) {
        message = @"❌ Не удалось получить координаты!\nПроверь логи в консоли.";
        coordLabel.text = @"Координаты: ОШИБКА!";
        coordLabel.textColor = [UIColor redColor];
    } else {
        message = [NSString stringWithFormat:@"✅ X: %.2f\nY: %.2f\nZ: %.2f", pos.x, pos.y, pos.z];
        coordLabel.text = [NSString stringWithFormat:@"📍 X:%.0f Y:%.0f Z:%.0f", pos.x, pos.y, pos.z];
        coordLabel.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1];
    }
    
    // Показываем алерт
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Координаты игрока" 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

- (void)checkOffsets {
    NSLog(@"[ESP] ========== CHECK OFFSETS ==========");
    
    uintptr_t base = getBase();
    if (base == 0) {
        [self showAlert:@"Ошибка" message:@"База UnityFramework не найдена!"];
        return;
    }
    
    NSString *info = [NSString stringWithFormat:
        @"База: 0x%llx\n"
        @"Utilities TypeInfo: 0x%llx\n"
        @"static_fields: 0x%llx\n"
        @"_playerController смещение: 0x%02x\n"
        @"AxeArms смещение: 0x%02x\n"
        @"Transform.position смещение: 0x%02x",
        (unsigned long long)base,
        (unsigned long long)(base + UTILITIES_TYPEINFO_RVA),
        (unsigned long long)(base + UTILITIES_TYPEINFO_RVA + 0x08),
        PLAYERCONTROLLER_OFFSET,
        AXEARMS_OFFSET,
        TRANSFORM_POSITION_OFFSET
    ];
    
    [self showAlert:@"Смещения" message:info];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

@end

// ==================== ЗАГРУЗКА ТВИКА ====================

static TestMenu *testMenu;

static void loadTestMenu() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (keyWindow) {
            testMenu = [[TestMenu alloc] initWithFrame:keyWindow.bounds];
            [keyWindow addSubview:testMenu];
            NSLog(@"[ESP] Test menu loaded!");
            
            // Выводим информацию при запуске
            GetPlayerPosition();
        } else {
            // Если окна нет, пробуем снова
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                loadTestMenu();
            });
        }
    });
}

%ctor {
    NSLog(@"[ESP] Tweak loaded!");
    loadTestMenu();
}
