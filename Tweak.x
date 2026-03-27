#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <substrate.h>

#define UTILITIES_TYPEINFO_RVA          0x8E15248
#define AXEARMS_OFFSET                  0x150

uintptr_t getBase() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

@interface DebugMenu : NSObject
+ (void)setup;
@end

@implementation DebugMenu

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

+ (void)debugAddresses {
    uintptr_t base = getBase();
    if (base == 0) {
        [self showAlert:@"Ошибка" message:@"Base не найдена"];
        return;
    }
    
    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"Base: 0x%llx\n\n", (unsigned long long)base];
    
    // 1. Utilities TypeInfo
    uintptr_t typeInfo = base + UTILITIES_TYPEINFO_RVA;
    [info appendFormat:@"TypeInfo: 0x%llx\n", (unsigned long long)typeInfo];
    
    // 2. static_fields
    uintptr_t static_fields = *(uintptr_t*)(typeInfo + 0x08);
    [info appendFormat:@"static_fields: 0x%llx\n\n", (unsigned long long)static_fields];
    
    if (static_fields == 0) {
        [info appendString:@"❌ static_fields = NULL\n"];
        [self showAlert:@"Debug" message:info];
        return;
    }
    
    // 3. Читаем 16 полей подряд от static_fields (чтобы увидеть все возможные кандидаты)
    [info appendString:@"Поля в static_fields:\n"];
    for (int i = 0; i < 16; i++) {
        uintptr_t val = *(uintptr_t*)(static_fields + i * 8);
        [info appendFormat:@"  +0x%02x: 0x%llx\n", i * 8, (unsigned long long)val];
    }
    
    [info appendString:@"\nПопытка прочитать позицию по разным смещениям:\n"];
    
    // 4. Проверяем несколько кандидатов (0x28, 0x30, 0x38, 0x40)
    int candidates[] = {0x28, 0x30, 0x38, 0x40, 0x48, 0x50};
    for (int i = 0; i < 6; i++) {
        int offset = candidates[i];
        uintptr_t firstPerson = *(uintptr_t*)(static_fields + offset);
        if (firstPerson == 0) {
            [info appendFormat:@"\n[0x%02x] FirstPerson = NULL", offset];
            continue;
        }
        
        uintptr_t transform = *(uintptr_t*)(firstPerson + AXEARMS_OFFSET);
        if (transform == 0) {
            [info appendFormat:@"\n[0x%02x] Transform = NULL", offset];
            continue;
        }
        
        // Читаем как float (позиция)
        float x = *(float*)(transform + 0x20);
        float y = *(float*)(transform + 0x24);
        float z = *(float*)(transform + 0x28);
        
        // Также читаем как int (чтобы увидеть сырые данные)
        uint32_t raw_x = *(uint32_t*)(transform + 0x20);
        uint32_t raw_y = *(uint32_t*)(transform + 0x24);
        uint32_t raw_z = *(uint32_t*)(transform + 0x28);
        
        [info appendFormat:@"\n[0x%02x] pos as float: (%.2f, %.2f, %.2f)", offset, x, y, z];
        [info appendFormat:@"\n       as raw: (0x%08x, 0x%08x, 0x%08x)", raw_x, raw_y, raw_z];
        
        // Проверяем, похоже ли на реальные координаты (обычно в пределах -1000..1000)
        if (fabs(x) < 10000 && fabs(y) < 10000 && fabs(z) < 10000 && x != 0) {
            [info appendFormat:@"\n       ✅ ПОХОЖЕ НА РЕАЛЬНЫЕ КООРДИНАТЫ!"];
        }
    }
    
    [self showAlert:@"Debug Info" message:info];
    
    // Обновляем текстовое поле
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
    
    // Кнопка
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
    
    // Меню
    menuContainer = [[UIView alloc] initWithFrame:CGRectMake(menuButton.frame.origin.x, 
                                                              menuButton.frame.origin.y + 55, 
                                                              320, 400)];
    menuContainer.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.95];
    menuContainer.layer.cornerRadius = 12;
    menuContainer.hidden = YES;
    menuContainer.userInteractionEnabled = YES;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, 320, 28)];
    title.text = @"Modern Strike Debug";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [menuContainer addSubview:title];
    
    UIButton *debugBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    debugBtn.frame = CGRectMake(10, 45, 300, 40);
    debugBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:1];
    debugBtn.layer.cornerRadius = 8;
    [debugBtn setTitle:@"🔍 DEBUG: Показать все поля" forState:UIControlStateNormal];
    [debugBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    debugBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [debugBtn addTarget:self action:@selector(debugAddresses) forControlEvents:UIControlEventTouchUpInside];
    [menuContainer addSubview:debugBtn];
    
    // Текстовое поле для вывода
    debugText = [[UITextView alloc] initWithFrame:CGRectMake(5, 95, 310, 290)];
    debugText.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1];
    debugText.textColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1];
    debugText.font = [UIFont fontWithName:@"Courier" size:10];
    debugText.editable = NO;
    debugText.text = @"Нажми кнопку для отладки";
    [menuContainer addSubview:debugText];
    
    [keyWindow addSubview:menuContainer];
    
    NSLog(@"[ESP] Debug menu loaded!");
}

@end

static void loadMenu() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].keyWindow) {
            [DebugMenu setup];
        } else {
            loadMenu();
        }
    });
}

%ctor {
    NSLog(@"[ESP] Debug tweak loaded!");
    loadMenu();
}
