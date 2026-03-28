#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

// ==================== RVA ИЗ IDA ====================
#define STATIC_FIELDS_PTR_RVA       0x8FC1848   // off_8FC1848
#define OFFSET_TO_OBJ               0xB8
#define PLAYER_CONTROLLER_OFFSET    0x30
#define TRANSFORM_OFFSET            0xF0        // из _FT_Get_Transform
#define POSITION_OFFSET             0x20

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
    
    // 1. Получаем staticFieldsPtr из off_8FC1848
    uintptr_t staticFieldsPtr = *(uintptr_t*)(base + STATIC_FIELDS_PTR_RVA);
    if (staticFieldsPtr == 0) return result;
    
    // 2. Получаем объект по смещению 0xB8
    uintptr_t obj = *(uintptr_t*)(staticFieldsPtr + OFFSET_TO_OBJ);
    if (obj == 0) return result;
    
    // 3. Получаем _playerController
    uintptr_t playerController = *(uintptr_t*)(obj + PLAYER_CONTROLLER_OFFSET);
    if (playerController == 0) return result;
    
    // 4. Получаем Transform (через 0xF0, как в _FT_Get_Transform)
    uintptr_t transform = *(uintptr_t*)(playerController + TRANSFORM_OFFSET);
    if (transform == 0) return result;
    
    // 5. Получаем позицию
    result.x = *(float*)(transform + POSITION_OFFSET);
    result.y = *(float*)(transform + POSITION_OFFSET + 4);
    result.z = *(float*)(transform + POSITION_OFFSET + 8);
    
    return result;
}

// ==================== UI МЕНЮ ====================
@interface ESPMenu : NSObject
+ (void)setup;
@end

@implementation ESPMenu

static UIButton *menuButton = nil;
static UIView *menuContainer = nil;
static UILabel *coordLabel = nil;
static BOOL isMenuVisible = NO;

+ (void)showAlert:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                       message:message 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        if (rootVC) {
            [rootVC presentViewController:alert animated:YES completion:nil];
        }
    });
}

+ (void)checkCoordinates {
    struct Vector3 pos = GetPlayerPosition();
    NSString *message;
    if (pos.x == 0 && pos.y == 0 && pos.z == 0) {
        message = @"❌ Не удалось получить координаты!\nЗайди в матч и нажми снова";
        coordLabel.text = @"❌ Зайди в матч";
        coordLabel.textColor = [UIColor redColor];
    } else {
        message = [NSString stringWithFormat:@"X: %.2f\nY: %.2f\nZ: %.2f", pos.x, pos.y, pos.z];
        coordLabel.text = [NSString stringWithFormat:@"X:%.0f  Y:%.0f  Z:%.0f", pos.x, pos.y, pos.z];
        coordLabel.textColor = [UIColor greenColor];
    }
    [self showAlert:@"Координаты игрока" message:message];
}

+ (void)updateCoordinates {
    if (!coordLabel) return;
    struct Vector3 pos = GetPlayerPosition();
    if (pos.x == 0 && pos.y == 0 && pos.z == 0) {
        coordLabel.text = @"❌ Зайди в матч";
        coordLabel.textColor = [UIColor redColor];
    } else {
        coordLabel.text = [NSString stringWithFormat:@"X:%.0f  Y:%.0f  Z:%.0f", pos.x, pos.y, pos.z];
        coordLabel.textColor = [UIColor greenColor];
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
    
    CGRect frame = menuContainer.frame;
    frame.origin.x = menuButton.frame.origin.x;
    frame.origin.y = menuButton.frame.origin.y + menuButton.frame.size.height + 5;
    menuContainer.frame = frame;
}

+ (void)setup {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    
    menuButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    menuButton.frame = CGRectMake(keyWindow.bounds.size.width - 70, 60, 50, 50);
    menuButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.9];
    menuButton.layer.cornerRadius = 25;
    [menuButton setTitle:@"🎯" forState:UIControlStateNormal];
    [menuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    menuButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [menuButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
    [menuButton addGestureRecognizer:pan];
    [keyWindow addSubview:menuButton];
    
    menuContainer = [[UIView alloc] initWithFrame:CGRectMake(menuButton.frame.origin.x, 
                                                              menuButton.frame.origin.y + 55, 
                                                              260, 150)];
    menuContainer.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.95];
    menuContainer.layer.cornerRadius = 12;
    menuContainer.hidden = YES;
    menuContainer.userInteractionEnabled = YES;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, 260, 28)];
    title.text = @"Modern Strike ESP";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [menuContainer addSubview:title];
    
    UIButton *checkBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    checkBtn.frame = CGRectMake(10, 45, 240, 38);
    checkBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1];
    checkBtn.layer.cornerRadius = 8;
    [checkBtn setTitle:@"📍 Мои координаты" forState:UIControlStateNormal];
    [checkBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    checkBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [checkBtn addTarget:self action:@selector(checkCoordinates) forControlEvents:UIControlEventTouchUpInside];
    [menuContainer addSubview:checkBtn];
    
    coordLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 100, 250, 40)];
    coordLabel.text = @"Зайди в матч";
    coordLabel.textColor = [UIColor lightGrayColor];
    coordLabel.font = [UIFont systemFontOfSize:12];
    coordLabel.textAlignment = NSTextAlignmentCenter;
    coordLabel.numberOfLines = 2;
    [menuContainer addSubview:coordLabel];
    
    [keyWindow addSubview:menuContainer];
    
    [NSTimer scheduledTimerWithTimeInterval:2.0 
                                     target:self 
                                   selector:@selector(updateCoordinates) 
                                   userInfo:nil 
                                    repeats:YES];
    
    NSLog(@"[ESP] Menu ready!");
}

@end

static void loadMenu() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (keyWindow) {
            [ESPMenu setup];
        } else {
            loadMenu();
        }
    });
}

%ctor {
    NSLog(@"[ESP] Tweak loaded!");
    loadMenu();
}
