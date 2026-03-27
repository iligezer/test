#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <substrate.h>

#define UTILITIES_TYPEINFO_RVA          0x8E15248

uintptr_t getBase() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

@interface ScanMenu : NSObject
+ (void)setup;
@end

@implementation ScanMenu

static UIView *menuContainer = nil;
static UIButton *menuButton = nil;
static UITextView *debugText = nil;
static BOOL isMenuVisible = NO;

+ (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    [rootVC presentViewController:alert animated:YES completion:nil];
}

+ (void)scanForTransform {
    uintptr_t base = getBase();
    if (base == 0) {
        [self showAlert:@"Ошибка" message:@"Base не найдена"];
        return;
    }
    
    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"Base: 0x%llx\n", (unsigned long long)base];
    
    uintptr_t typeInfo = base + UTILITIES_TYPEINFO_RVA;
    uintptr_t static_fields = *(uintptr_t*)(typeInfo + 0x08);
    [info appendFormat:@"static_fields: 0x%llx\n\n", (unsigned long long)static_fields];
    
    // Проверяем оба кандидата _playerController
    int playerOffsets[] = {0x28, 0x30};
    
    for (int p = 0; p < 2; p++) {
        int playerOffset = playerOffsets[p];
        uintptr_t firstPerson = *(uintptr_t*)(static_fields + playerOffset);
        
        [info appendFormat:@"\n========== _playerController at 0x%02x ==========\n", playerOffset];
        [info appendFormat:@"FirstPerson: 0x%llx\n", (unsigned long long)firstPerson];
        
        if (firstPerson == 0 || firstPerson < base) {
            [info appendString:@"❌ Невалидный адрес\n"];
            continue;
        }
        
        [info appendString:@"\nСканирование возможных смещений Transform (0x00 - 0x200):\n"];
        
        int foundCount = 0;
        
        // Сканируем все возможные смещения
        for (int offset = 0; offset <= 0x200; offset += 8) {
            uintptr_t possibleTransform = *(uintptr_t*)(firstPerson + offset);
            
            // Проверка: адрес должен быть в диапазоне памяти игры
            if (possibleTransform == 0) continue;
            if (possibleTransform < base) continue;
            if (possibleTransform > base + 0x20000000) continue;
            
            // Проверка выравнивания (Transform должен быть кратен 8)
            if ((possibleTransform & 0x7) != 0) continue;
            
            // Пытаемся прочитать klass (первое поле Transform)
            uintptr_t klass = *(uintptr_t*)possibleTransform;
            
            // klass должен быть указателем на Class (обычно в диапазоне игры)
            if (klass < base || klass > base + 0x20000000) continue;
            
            // Читаем position
            float x = *(float*)(possibleTransform + 0x20);
            float y = *(float*)(possibleTransform + 0x24);
            float z = *(float*)(possibleTransform + 0x28);
            
            // Проверяем, похоже ли на реальные координаты
            if (fabs(x) < 10000 && fabs(y) < 10000 && fabs(z) < 10000 && (x != 0 || y != 0 || z != 0)) {
                [info appendFormat:@"\n✅ НАЙДЕН! offset 0x%03x (0x%x)\n", offset, offset];
                [info appendFormat:@"   Transform: 0x%llx\n", (unsigned long long)possibleTransform];
                [info appendFormat:@"   klass: 0x%llx\n", (unsigned long long)klass];
                [info appendFormat:@"   position: (%.2f, %.2f, %.2f)\n", x, y, z];
                foundCount++;
            }
        }
        
        if (foundCount == 0) {
            [info appendString:@"❌ Не найдено валидных Transform\n"];
        }
    }
    
    [self showAlert:@"Scan Results" message:info];
    if (debugText) {
        debugText.text = info;
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
    [menuButton setTitle:@"🔍" forState:UIControlStateNormal];
    [menuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    menuButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [menuButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
    [menuButton addGestureRecognizer:pan];
    [keyWindow addSubview:menuButton];
    
    menuContainer = [[UIView alloc] initWithFrame:CGRectMake(menuButton.frame.origin.x, 
                                                              menuButton.frame.origin.y + 55, 
                                                              380, 500)];
    menuContainer.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.95];
    menuContainer.layer.cornerRadius = 12;
    menuContainer.hidden = YES;
    menuContainer.userInteractionEnabled = YES;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, 380, 28)];
    title.text = @"Modern Strike - Scan Transform";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [menuContainer addSubview:title];
    
    UIButton *scanBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    scanBtn.frame = CGRectMake(10, 45, 360, 40);
    scanBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:1];
    scanBtn.layer.cornerRadius = 8;
    [scanBtn setTitle:@"🔍 СКАНИРОВАТЬ TRANSFORM" forState:UIControlStateNormal];
    [scanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    scanBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [scanBtn addTarget:self action:@selector(scanForTransform) forControlEvents:UIControlEventTouchUpInside];
    [menuContainer addSubview:scanBtn];
    
    debugText = [[UITextView alloc] initWithFrame:CGRectMake(5, 95, 370, 390)];
    debugText.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1];
    debugText.textColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1];
    debugText.font = [UIFont fontWithName:@"Courier" size:9];
    debugText.editable = NO;
    debugText.text = @"Зайди в матч, затем нажми кнопку\nСканер найдет правильное смещение AxeArms";
    [menuContainer addSubview:debugText];
    
    [keyWindow addSubview:menuContainer];
    
    NSLog(@"[ESP] Scan menu loaded!");
}

@end

static void loadMenu() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].keyWindow) {
            [ScanMenu setup];
        } else {
            loadMenu();
        }
    });
}

%ctor {
    NSLog(@"[ESP] Scan tweak loaded!");
    loadMenu();
}
