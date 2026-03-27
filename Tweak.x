#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <substrate.h>

// ==================== СМЕЩЕНИЯ ====================

#define UTILITIES_TYPEINFO_RVA          0x8E15248
#define PLAYERCONTROLLER_OFFSET         0x30
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

struct Vector3 GetPlayerPosition() {
    struct Vector3 result = {0, 0, 0};
    
    uintptr_t base = getBase();
    if (base == 0) return result;
    
    uintptr_t typeInfo = base + UTILITIES_TYPEINFO_RVA;
    uintptr_t static_fields = *(uintptr_t*)(typeInfo + 0x08);
    if (static_fields == 0) return result;
    
    uintptr_t firstPersonController = *(uintptr_t*)(static_fields + PLAYERCONTROLLER_OFFSET);
    if (firstPersonController == 0) return result;
    
    uintptr_t transform = *(uintptr_t*)(firstPersonController + AXEARMS_OFFSET);
    if (transform == 0) return result;
    
    result.x = *(float*)(transform + TRANSFORM_POSITION_OFFSET);
    result.y = *(float*)(transform + TRANSFORM_POSITION_OFFSET + 4);
    result.z = *(float*)(transform + TRANSFORM_POSITION_OFFSET + 8);
    
    return result;
}

// ==================== МЕНЮ ====================

static UIView *menuContainer = nil;
static UIButton *menuButton = nil;
static BOOL isMenuVisible = NO;

static void updateCoordinatesLabel(UILabel *label) {
    struct Vector3 pos = GetPlayerPosition();
    if (pos.x == 0 && pos.y == 0 && pos.z == 0) {
        label.text = @"❌ Ошибка! Смотри логи";
        label.textColor = [UIColor redColor];
    } else {
        label.text = [NSString stringWithFormat:@"X:%.0f  Y:%.0f  Z:%.0f", pos.x, pos.y, pos.z];
        label.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1];
    }
}

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
        message = @"❌ Не удалось получить координаты!\n\nПроверь логи в Xcode/Console";
    } else {
        message = [NSString stringWithFormat:@"X: %.2f\nY: %.2f\nZ: %.2f\n\nЭто координаты ТВОЕГО персонажа!", pos.x, pos.y, pos.z];
    }
    showAlert(@"Твои координаты", message);
}

static void checkOffsets() {
    uintptr_t base = getBase();
    if (base == 0) {
        showAlert(@"Ошибка", @"База UnityFramework не найдена!");
        return;
    }
    
    NSString *info = [NSString stringWithFormat:
        @"Base: 0x%llx\n"
        @"Utilities TypeInfo: 0x%llx\n"
        @"static_fields: 0x%llx\n\n"
        @"_playerController offset: 0x%02x\n"
        @"AxeArms offset: 0x%02x\n"
        @"position offset: 0x%02x",
        (unsigned long long)base,
        (unsigned long long)(base + UTILITIES_TYPEINFO_RVA),
        (unsigned long long)(base + UTILITIES_TYPEINFO_RVA + 0x08),
        PLAYERCONTROLLER_OFFSET,
        AXEARMS_OFFSET,
        TRANSFORM_POSITION_OFFSET
    ];
    
    showAlert(@"Смещения", info);
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
    
    // Кнопка-меню (плавающая)
    menuButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    menuButton.frame = CGRectMake(keyWindow.bounds.size.width - 70, 60, 50, 50);
    menuButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.9];
    menuButton.layer.cornerRadius = 25;
    menuButton.layer.shadowColor = [UIColor blackColor].CGColor;
    menuButton.layer.shadowOffset = CGSizeMake(2, 2);
    menuButton.layer.shadowOpacity = 0.5;
    [menuButton setTitle:@"⚡" forState:UIControlStateNormal];
    [menuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    menuButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [menuButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    // Перетаскивание
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
    [menuButton addGestureRecognizer:pan];
    
    [keyWindow addSubview:menuButton];
    
    // Контейнер меню (добавляем на окно, а не на кнопку!)
    menuContainer = [[UIView alloc] initWithFrame:CGRectMake(menuButton.frame.origin.x, 
                                                              menuButton.frame.origin.y + 55, 
                                                              220, 180)];
    menuContainer.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.95];
    menuContainer.layer.cornerRadius = 12;
    menuContainer.layer.borderWidth = 0.5;
    menuContainer.layer.borderColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1].CGColor;
    menuContainer.hidden = YES;
    menuContainer.userInteractionEnabled = YES;  // ← ВАЖНО!
    
    // Заголовок
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, 220, 28)];
    title.text = @"Modern Strike ESP Test";
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
    [coordBtn addTarget:self action:@selector(checkCoordinates) forControlEvents:UIControlEventTouchUpInside];
    [menuContainer addSubview:coordBtn];
    
    // Кнопка "Смещения"
    UIButton *offsetsBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    offsetsBtn.frame = CGRectMake(10, 92, 200, 38);
    offsetsBtn.backgroundColor = [UIColor colorWithRed:0.6 green:0.3 blue:0.2 alpha:1];
    offsetsBtn.layer.cornerRadius = 8;
    [offsetsBtn setTitle:@"🔧 Смещения" forState:UIControlStateNormal];
    [offsetsBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    offsetsBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [offsetsBtn addTarget:self action:@selector(checkOffsets) forControlEvents:UIControlEventTouchUpInside];
    [menuContainer addSubview:offsetsBtn];
    
    // Метка с координатами
    UILabel *coordLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 140, 210, 32)];
    coordLabel.text = @"X: ?  Y: ?  Z: ?";
    coordLabel.textColor = [UIColor colorWithRed:0.7 green:0.7 blue:0.7 alpha:1];
    coordLabel.font = [UIFont systemFontOfSize:11];
    coordLabel.textAlignment = NSTextAlignmentCenter;
    coordLabel.numberOfLines = 2;
    [menuContainer addSubview:coordLabel];
    
    [keyWindow addSubview:menuContainer];
    
    // Обновляем координаты раз в секунду
    [NSTimer scheduledTimerWithTimeInterval:1.0 
                                     target:[NSBlockOperation blockOperationWithBlock:^{
        updateCoordinatesLabel(coordLabel);
    }] 
                                   selector:@selector(main) 
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
