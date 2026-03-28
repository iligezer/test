#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <substrate.h>

// ==================== СМЕЩЕНИЯ ====================
#define UTILITIES_TYPEINFO_RVA          0x8E15248
#define PLAYERCONTROLLER_OFFSET         0x30
#define POSITION_X_OFFSET               0x158
#define POSITION_Y_OFFSET               0x15C
#define POSITION_Z_OFFSET               0x160

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
    
    uintptr_t firstPerson = *(uintptr_t*)(static_fields + PLAYERCONTROLLER_OFFSET);
    if (firstPerson == 0) return result;
    
    result.x = *(float*)(firstPerson + POSITION_X_OFFSET);
    result.y = *(float*)(firstPerson + POSITION_Y_OFFSET);
    result.z = *(float*)(firstPerson + POSITION_Z_OFFSET);
    
    return result;
}

// ==================== КЛАСС МЕНЮ ====================

@interface ESPMenu : NSObject
+ (void)setup;
@end

@implementation ESPMenu

static UIButton *menuButton = nil;
static UIView *menuView = nil;
static UILabel *coordLabel = nil;
static BOOL isMenuVisible = NO;
static NSTimer *updateTimer = nil;

+ (void)checkCoordinates {
    struct Vector3 pos = GetPlayerPosition();
    NSString *message = [NSString stringWithFormat:@"X: %.2f\nY: %.2f\nZ: %.2f", pos.x, pos.y, pos.z];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Твои координаты" 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

+ (void)updateCoordinates {
    if (!coordLabel) return;
    struct Vector3 pos = GetPlayerPosition();
    if (pos.x == 0 && pos.y == 0 && pos.z == 0) {
        coordLabel.text = @"❌ Игрок не найден";
        coordLabel.textColor = [UIColor redColor];
    } else {
        coordLabel.text = [NSString stringWithFormat:@"X:%.0f  Y:%.0f  Z:%.0f", pos.x, pos.y, pos.z];
        coordLabel.textColor = [UIColor colorWithRed:0.3 green:0.9 blue:0.3 alpha:1];
    }
}

+ (void)toggleMenu {
    isMenuVisible = !isMenuVisible;
    menuView.hidden = !isMenuVisible;
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
    
    CGRect frame = menuView.frame;
    frame.origin.x = menuButton.frame.origin.x;
    frame.origin.y = menuButton.frame.origin.y + menuButton.frame.size.height + 5;
    menuView.frame = frame;
}

+ (void)setup {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    
    // Кнопка
    menuButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    menuButton.frame = CGRectMake(keyWindow.bounds.size.width - 70, 60, 50, 50);
    menuButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.9];
    menuButton.layer.cornerRadius = 25;
    [menuButton setTitle:@"⚡" forState:UIControlStateNormal];
    [menuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    menuButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [menuButton addTarget:[ESPMenu class] action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[ESPMenu class] action:@selector(dragButton:)];
    [menuButton addGestureRecognizer:pan];
    [keyWindow addSubview:menuButton];
    
    // Меню
    menuView = [[UIView alloc] initWithFrame:CGRectMake(menuButton.frame.origin.x, menuButton.frame.origin.y + 55, 220, 120)];
    menuView.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.95];
    menuView.layer.cornerRadius = 12;
    menuView.hidden = YES;
    menuView.userInteractionEnabled = YES;
    
    UIButton *checkBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    checkBtn.frame = CGRectMake(10, 10, 200, 40);
    checkBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1];
    checkBtn.layer.cornerRadius = 8;
    [checkBtn setTitle:@"📍 Мои координаты" forState:UIControlStateNormal];
    [checkBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    checkBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [checkBtn addTarget:[ESPMenu class] action:@selector(checkCoordinates) forControlEvents:UIControlEventTouchUpInside];
    [menuView addSubview:checkBtn];
    
    coordLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 60, 210, 40)];
    coordLabel.text = @"X: ?  Y: ?  Z: ?";
    coordLabel.textColor = [UIColor lightGrayColor];
    coordLabel.font = [UIFont systemFontOfSize:12];
    coordLabel.textAlignment = NSTextAlignmentCenter;
    coordLabel.numberOfLines = 2;
    [menuView addSubview:coordLabel];
    
    [keyWindow addSubview:menuView];
    
    // Обновление координат каждую секунду
    updateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 
                                                   target:[ESPMenu class] 
                                                 selector:@selector(updateCoordinates) 
                                                 userInfo:nil 
                                                  repeats:YES];
    
    NSLog(@"[ESP] Menu setup complete!");
}

@end

// ==================== ЗАГРУЗКА ====================

static void loadMenu() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].keyWindow) {
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
