#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <substrate.h>

// ==================== СМЕЩЕНИЯ ДЛЯ iOS (Modern Strike Online) ====================

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

// ==================== МЕНЮ (как в FreeFire) ====================

@interface TestMenu : UIButton {
    UIView *menuView;
    UILabel *coordLabel;
    BOOL isMenuVisible;
}
@end

@implementation TestMenu

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Кнопка как в FreeFire — просто кнопка, не блокирует касания
        self.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.85];
        self.layer.cornerRadius = 25;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(2, 2);
        self.layer.shadowOpacity = 0.5;
        [self setTitle:@"⚡" forState:UIControlStateNormal];
        [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:24];
        [self addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        
        // Перетаскивание как в FreeFire
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
        [self addGestureRecognizer:pan];
        
        isMenuVisible = NO;
        
        // Меню
        menuView = [[UIView alloc] initWithFrame:CGRectMake(0, 70, 220, 150)];
        menuView.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.95];
        menuView.layer.cornerRadius = 10;
        menuView.layer.borderWidth = 0.5;
        menuView.layer.borderColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1].CGColor;
        menuView.hidden = YES;
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, 220, 25)];
        title.text = @"Modern Strike ESP Test";
        title.textColor = [UIColor whiteColor];
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont boldSystemFontOfSize:14];
        [menuView addSubview:title];
        
        UIButton *checkBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        checkBtn.frame = CGRectMake(10, 40, 200, 35);
        checkBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1];
        checkBtn.layer.cornerRadius = 6;
        [checkBtn setTitle:@"📍 Координаты игрока" forState:UIControlStateNormal];
        [checkBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        checkBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [checkBtn addTarget:self action:@selector(checkCoordinates) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:checkBtn];
        
        UIButton *offsetsBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        offsetsBtn.frame = CGRectMake(10, 85, 200, 35);
        offsetsBtn.backgroundColor = [UIColor colorWithRed:0.6 green:0.3 blue:0.2 alpha:1];
        offsetsBtn.layer.cornerRadius = 6;
        [offsetsBtn setTitle:@"🔧 Смещения" forState:UIControlStateNormal];
        [offsetsBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        offsetsBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [offsetsBtn addTarget:self action:@selector(checkOffsets) forControlEvents:UIControlEventTouchUpInside];
        [menuView addSubview:offsetsBtn];
        
        coordLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 125, 210, 20)];
        coordLabel.text = @"X: ?  Y: ?  Z: ?";
        coordLabel.textColor = [UIColor colorWithRed:0.7 green:0.7 blue:0.7 alpha:1];
        coordLabel.font = [UIFont systemFontOfSize:10];
        coordLabel.textAlignment = NSTextAlignmentCenter;
        [menuView addSubview:coordLabel];
        
        [self addSubview:menuView];
    }
    return self;
}

- (void)dragButton:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    
    // Ограничения
    CGFloat halfWidth = self.frame.size.width / 2;
    CGFloat halfHeight = self.frame.size.height / 2;
    newCenter.x = MAX(halfWidth, MIN(newCenter.x, self.superview.bounds.size.width - halfWidth));
    newCenter.y = MAX(halfHeight, MIN(newCenter.y, self.superview.bounds.size.height - halfHeight));
    
    self.center = newCenter;
    [gesture setTranslation:CGPointZero inView:self.superview];
    
    // Меню двигается вместе с кнопкой
    CGRect newMenuFrame = menuView.frame;
    newMenuFrame.origin.x = self.frame.origin.x;
    newMenuFrame.origin.y = self.frame.origin.y + self.frame.size.height + 5;
    menuView.frame = newMenuFrame;
}

- (void)toggleMenu {
    isMenuVisible = !isMenuVisible;
    menuView.hidden = !isMenuVisible;
}

- (void)checkCoordinates {
    struct Vector3 pos = GetPlayerPosition();
    
    NSString *message;
    if (pos.x == 0 && pos.y == 0 && pos.z == 0) {
        message = @"❌ Не удалось получить координаты!\nПроверь логи в консоли.";
        coordLabel.text = @"X: ERROR  Y: ERROR  Z: ERROR";
        coordLabel.textColor = [UIColor redColor];
    } else {
        message = [NSString stringWithFormat:@"X: %.2f\nY: %.2f\nZ: %.2f", pos.x, pos.y, pos.z];
        coordLabel.text = [NSString stringWithFormat:@"X:%.0f Y:%.0f Z:%.0f", pos.x, pos.y, pos.z];
        coordLabel.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1];
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Твои координаты" 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

- (void)checkOffsets {
    uintptr_t base = getBase();
    if (base == 0) {
        [self showAlert:@"Ошибка" message:@"База не найдена!"];
        return;
    }
    
    NSString *info = [NSString stringWithFormat:
        @"Base: 0x%llx\n"
        @"Utilities TypeInfo: 0x%llx\n"
        @"static_fields: 0x%llx\n"
        @"_playerController: 0x%02x\n"
        @"AxeArms: 0x%02x\n"
        @"position: 0x%02x",
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

// ==================== ЗАГРУЗКА (как в FreeFire) ====================

static TestMenu *testMenu;

static void loadTestMenu() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (keyWindow) {
            // Кнопка 50x50, ставим в правый верхний угол как в FreeFire
            testMenu = [[TestMenu alloc] initWithFrame:CGRectMake(keyWindow.bounds.size.width - 70, 60, 50, 50)];
            [keyWindow addSubview:testMenu];
            NSLog(@"[ESP] Menu loaded!");
            
            // Проверяем при запуске
            GetPlayerPosition();
        } else {
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
