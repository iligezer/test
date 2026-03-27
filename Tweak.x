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

// Безопасное чтение
BOOL isValidPointer(uintptr_t ptr) {
    if (ptr == 0) return NO;
    if (ptr < 0x100000000) return NO;
    if (ptr > 0x2000000000) return NO;
    return YES;
}

uintptr_t safeReadPtr(uintptr_t addr) {
    if (!isValidPointer(addr)) return 0;
    return *(uintptr_t*)addr;
}

float safeReadFloat(uintptr_t addr) {
    if (!isValidPointer(addr)) return 0;
    return *(float*)addr;
}

@interface SafeDebugMenu : NSObject
+ (void)setup;
@end

@implementation SafeDebugMenu

static UIView *menuContainer = nil;
static UIButton *menuButton = nil;
static UITextView *debugText = nil;
static BOOL isMenuVisible = NO;
static NSMutableString *logBuffer = nil;

+ (void)copyLog {
    if (debugText.text.length > 0) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = debugText.text;
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅ Скопировано" 
                                                                       message:@"Лог скопирован в буфер обмена" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        [rootVC presentViewController:alert animated:YES completion:nil];
    }
}

+ (void)debugAddresses {
    logBuffer = [NSMutableString string];
    [logBuffer appendString:@"=== Modern Strike Debug ===\n\n"];
    
    uintptr_t base = getBase();
    if (base == 0) {
        [logBuffer appendString:@"❌ Base не найдена!\n"];
        [self showDebugInfo];
        return;
    }
    
    [logBuffer appendFormat:@"Base: 0x%llx\n\n", (unsigned long long)base];
    
    // 1. Utilities TypeInfo
    uintptr_t typeInfo = base + UTILITIES_TYPEINFO_RVA;
    [logBuffer appendFormat:@"TypeInfo: 0x%llx\n", (unsigned long long)typeInfo];
    
    // 2. static_fields
    uintptr_t static_fields = safeReadPtr(typeInfo + 0x08);
    [logBuffer appendFormat:@"static_fields: 0x%llx\n\n", (unsigned long long)static_fields];
    
    if (static_fields == 0 || !isValidPointer(static_fields)) {
        [logBuffer appendString:@"❌ static_fields невалидный\n"];
        [self showDebugInfo];
        return;
    }
    
    // 3. Читаем ТОЛЬКО 4 кандидата (безопасно)
    int candidates[] = {0x28, 0x30, 0x38, 0x40};
    [logBuffer appendString:@"Проверка кандидатов _playerController:\n\n"];
    
    for (int i = 0; i < 4; i++) {
        int offset = candidates[i];
        uintptr_t firstPerson = safeReadPtr(static_fields + offset);
        
        [logBuffer appendFormat:@"[0x%02x] FirstPerson = 0x%llx", offset, (unsigned long long)firstPerson];
        
        if (firstPerson == 0 || !isValidPointer(firstPerson)) {
            [logBuffer appendString:@" ❌ (невалидный)\n"];
            continue;
        }
        
        // Пробуем прочитать AxeArms
        uintptr_t transform = safeReadPtr(firstPerson + AXEARMS_OFFSET);
        [logBuffer appendFormat:@"\n       Transform = 0x%llx", (unsigned long long)transform];
        
        if (transform == 0 || !isValidPointer(transform)) {
            [logBuffer appendString:@" ❌ (невалидный)\n\n"];
            continue;
        }
        
        // Читаем позицию
        float x = safeReadFloat(transform + 0x20);
        float y = safeReadFloat(transform + 0x24);
        float z = safeReadFloat(transform + 0x28);
        
        [logBuffer appendFormat:@"\n       Position: (%.2f, %.2f, %.2f)", x, y, z];
        
        // Проверяем, похоже ли на реальные координаты
        if (fabs(x) < 1000 && fabs(y) < 1000 && fabs(z) < 1000 && x != 0) {
            [logBuffer appendString:@" ✅ РЕАЛИСТИЧНЫЕ КООРДИНАТЫ!\n\n"];
        } else {
            [logBuffer appendString:@" ❌ нереалистичные\n\n"];
        }
    }
    
    [logBuffer appendString:@"\n💡 Если ни один кандидат не дал реалистичных координат,\n"];
    [logBuffer appendString:@"   значит смещение _playerController другое.\n"];
    [logBuffer appendString:@"   Нужно поискать другие кандидаты (0x48, 0x50 и т.д.)\n"];
    
    [self showDebugInfo];
}

+ (void)showDebugInfo {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (debugText) {
            debugText.text = logBuffer;
        }
    });
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
    
    // Маленькая кнопка (40x40)
    menuButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    menuButton.frame = CGRectMake(keyWindow.bounds.size.width - 55, 60, 40, 40);
    menuButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.9];
    menuButton.layer.cornerRadius = 20;
    [menuButton setTitle:@"🔍" forState:UIControlStateNormal];
    [menuButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    menuButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [menuButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
    [menuButton addGestureRecognizer:pan];
    [keyWindow addSubview:menuButton];
    
    // Маленькое меню (260x300)
    menuContainer = [[UIView alloc] initWithFrame:CGRectMake(menuButton.frame.origin.x, 
                                                              menuButton.frame.origin.y + 45, 
                                                              260, 300)];
    menuContainer.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.08 alpha:0.95];
    menuContainer.layer.cornerRadius = 10;
    menuContainer.layer.borderWidth = 0.5;
    menuContainer.layer.borderColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:1].CGColor;
    menuContainer.hidden = YES;
    menuContainer.userInteractionEnabled = YES;
    
    // Заголовок
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, 260, 28)];
    title.text = @"Modern Strike Debug";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [menuContainer addSubview:title];
    
    // Кнопка Debug
    UIButton *debugBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    debugBtn.frame = CGRectMake(10, 45, 240, 38);
    debugBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:1];
    debugBtn.layer.cornerRadius = 8;
    [debugBtn setTitle:@"🔍 Проверить смещения" forState:UIControlStateNormal];
    [debugBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    debugBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [debugBtn addTarget:self action:@selector(debugAddresses) forControlEvents:UIControlEventTouchUpInside];
    [menuContainer addSubview:debugBtn];
    
    // Кнопка копирования
    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    copyBtn.frame = CGRectMake(10, 92, 240, 38);
    copyBtn.backgroundColor = [UIColor colorWithRed:0.3 green:0.6 blue:0.3 alpha:1];
    copyBtn.layer.cornerRadius = 8;
    [copyBtn setTitle:@"📋 Копировать лог" forState:UIControlStateNormal];
    [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    copyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [menuContainer addSubview:copyBtn];
    
    // Текстовое поле для вывода (маленькое)
    debugText = [[UITextView alloc] initWithFrame:CGRectMake(5, 140, 250, 150)];
    debugText.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:1];
    debugText.textColor = [UIColor colorWithRed:0.7 green:0.7 blue:0.7 alpha:1];
    debugText.font = [UIFont fontWithName:@"Courier" size:10];
    debugText.editable = NO;
    debugText.text = @"Нажми 'Проверить смещения'";
    [menuContainer addSubview:debugText];
    
    [keyWindow addSubview:menuContainer];
    
    NSLog(@"[ESP] Safe debug menu loaded!");
}

@end

static void loadMenu() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].keyWindow) {
            [SafeDebugMenu setup];
        } else {
            loadMenu();
        }
    });
}

%ctor {
    NSLog(@"[ESP] Debug tweak loaded!");
    loadMenu();
}
