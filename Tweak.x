#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <signal.h>
#import <setjmp.h>

// ==================== RVA ИЗ IDA ====================
#define STATIC_FIELDS_PTR_RVA       0x8FC1848
#define OFFSET_TO_OBJ               0xB8
#define PLAYER_CONTROLLER_OFFSET    0x30
#define TRANSFORM_OFFSET            0xF0
#define POSITION_OFFSET             0x20

// ==================== ЗАЩИТА ОТ ВЫЛЕТА ====================
static jmp_buf jump_buffer;
static volatile BOOL is_reading = NO;

static void sig_handler(int sig) {
    if (is_reading) {
        longjmp(jump_buffer, 1);
    }
}

static BOOL safe_read(void *dst, const void *src, size_t size) {
    if (src == NULL) return NO;
    if ((uintptr_t)src < 0x100000000) return NO;
    if ((uintptr_t)src > 0x2000000000) return NO;
    
    // Устанавливаем обработчик сигнала
    signal(SIGSEGV, sig_handler);
    signal(SIGBUS, sig_handler);
    
    is_reading = YES;
    BOOL success = YES;
    if (setjmp(jump_buffer) == 0) {
        memcpy(dst, src, size);
    } else {
        success = NO;
    }
    is_reading = NO;
    
    // Восстанавливаем обработчики
    signal(SIGSEGV, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    
    return success;
}

static uintptr_t safe_read_ptr(uintptr_t addr) {
    uintptr_t val = 0;
    if (safe_read(&val, (void*)addr, sizeof(val))) {
        return val;
    }
    return 0;
}

static float safe_read_float(uintptr_t addr) {
    float val = 0;
    if (safe_read(&val, (void*)addr, sizeof(val))) {
        return val;
    }
    return 0;
}

uintptr_t getBase() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework")) {
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
    
    NSLog(@"[ESP] === START GET POSITION ===");
    
    if (base == 0) {
        NSLog(@"[ESP] ❌ Base = 0");
        return result;
    }
    NSLog(@"[ESP] ✅ Base = 0x%lx", base);
    
    // 1. staticFieldsPtr
    uintptr_t staticFieldsPtrAddr = base + STATIC_FIELDS_PTR_RVA;
    NSLog(@"[ESP] staticFieldsPtrAddr = 0x%lx", staticFieldsPtrAddr);
    
    uintptr_t staticFieldsPtr = safe_read_ptr(staticFieldsPtrAddr);
    if (staticFieldsPtr == 0) {
        NSLog(@"[ESP] ❌ staticFieldsPtr = 0");
        return result;
    }
    NSLog(@"[ESP] ✅ staticFieldsPtr = 0x%lx", staticFieldsPtr);
    
    // 2. obj
    uintptr_t objAddr = staticFieldsPtr + OFFSET_TO_OBJ;
    NSLog(@"[ESP] objAddr = 0x%lx", objAddr);
    
    uintptr_t obj = safe_read_ptr(objAddr);
    if (obj == 0) {
        NSLog(@"[ESP] ❌ obj = 0");
        return result;
    }
    NSLog(@"[ESP] ✅ obj = 0x%lx", obj);
    
    // 3. playerController
    uintptr_t playerControllerAddr = obj + PLAYER_CONTROLLER_OFFSET;
    NSLog(@"[ESP] playerControllerAddr = 0x%lx", playerControllerAddr);
    
    uintptr_t playerController = safe_read_ptr(playerControllerAddr);
    if (playerController == 0) {
        NSLog(@"[ESP] ❌ playerController = 0");
        return result;
    }
    NSLog(@"[ESP] ✅ playerController = 0x%lx", playerController);
    
    // 4. transform
    uintptr_t transformAddr = playerController + TRANSFORM_OFFSET;
    NSLog(@"[ESP] transformAddr = 0x%lx", transformAddr);
    
    uintptr_t transform = safe_read_ptr(transformAddr);
    if (transform == 0) {
        NSLog(@"[ESP] ❌ transform = 0");
        return result;
    }
    NSLog(@"[ESP] ✅ transform = 0x%lx", transform);
    
    // 5. position
    result.x = safe_read_float(transform + POSITION_OFFSET);
    result.y = safe_read_float(transform + POSITION_OFFSET + 4);
    result.z = safe_read_float(transform + POSITION_OFFSET + 8);
    
    NSLog(@"[ESP] position = (%.2f, %.2f, %.2f)", result.x, result.y, result.z);
    NSLog(@"[ESP] === END GET POSITION ===");
    
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
        message = @"❌ Не удалось получить координаты!\nСмотри логи в консоли";
        coordLabel.text = @"❌ Ошибка!";
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
                                                              280, 200)];
    menuContainer.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.95];
    menuContainer.layer.cornerRadius = 12;
    menuContainer.hidden = YES;
    menuContainer.userInteractionEnabled = YES;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, 280, 28)];
    title.text = @"Modern Strike ESP v2";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [menuContainer addSubview:title];
    
    UIButton *checkBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    checkBtn.frame = CGRectMake(10, 45, 260, 40);
    checkBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1];
    checkBtn.layer.cornerRadius = 8;
    [checkBtn setTitle:@"📍 Мои координаты" forState:UIControlStateNormal];
    [checkBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    checkBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [checkBtn addTarget:self action:@selector(checkCoordinates) forControlEvents:UIControlEventTouchUpInside];
    [menuContainer addSubview:checkBtn];
    
    UILabel *info = [[UILabel alloc] initWithFrame:CGRectMake(5, 100, 270, 40)];
    info.text = @"Смотри логи в Xcode Console\nWindow → Devices → Console";
    info.textColor = [UIColor lightGrayColor];
    info.font = [UIFont systemFontOfSize:10];
    info.textAlignment = NSTextAlignmentCenter;
    info.numberOfLines = 2;
    [menuContainer addSubview:info];
    
    coordLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 150, 270, 40)];
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
    
    // Принудительно вызываем для логов
    GetPlayerPosition();
    
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
