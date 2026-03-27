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

+ (void)debugRawData {
    uintptr_t base = getBase();
    if (base == 0) {
        [self showAlert:@"Ошибка" message:@"Base не найдена"];
        return;
    }
    
    NSMutableString *info = [NSMutableString string];
    [info appendFormat:@"Base: 0x%llx\n\n", (unsigned long long)base];
    
    uintptr_t typeInfo = base + UTILITIES_TYPEINFO_RVA;
    uintptr_t static_fields = *(uintptr_t*)(typeInfo + 0x08);
    [info appendFormat:@"static_fields: 0x%llx\n\n", (unsigned long long)static_fields];
    
    // Кандидаты из предыдущего анализа
    int candidates[] = {0x28, 0x30};
    
    for (int i = 0; i < 2; i++) {
        int offset = candidates[i];
        uintptr_t firstPerson = *(uintptr_t*)(static_fields + offset);
        [info appendFormat:@"\n========== offset 0x%02x ==========\n", offset];
        [info appendFormat:@"FirstPerson: 0x%llx\n", (unsigned long long)firstPerson];
        
        if (firstPerson == 0) {
            [info appendString:@"❌ NULL\n"];
            continue;
        }
        
        // Читаем 32 байта по адресу FirstPerson (чтобы увидеть, что там)
        [info appendString:@"FirstPerson raw data (32 bytes):\n"];
        for (int j = 0; j < 32; j += 8) {
            uint64_t val = *(uint64_t*)(firstPerson + j);
            [info appendFormat:@"  +0x%02x: 0x%016llx\n", j, (unsigned long long)val];
        }
        
        // Читаем поле по смещению 0x150 (AxeArms) и смотрим, что там
        uintptr_t possibleTransform = *(uintptr_t*)(firstPerson + 0x150);
        [info appendFormat:@"\nPossible Transform (0x150): 0x%llx\n", (unsigned long long)possibleTransform];
        
        if (possibleTransform != 0 && (possibleTransform & 0x7) == 0) {  // Проверка выравнивания
            [info appendString:@"✅ Адрес выровнен, возможно это Transform\n"];
            
            // Пытаемся прочитать klass (первое поле Transform)
            uintptr_t klass = *(uintptr_t*)possibleTransform;
            [info appendFormat:@"  klass: 0x%llx\n", (unsigned long long)klass];
            
            // Читаем position
            float x = *(float*)(possibleTransform + 0x20);
            float y = *(float*)(possibleTransform + 0x24);
            float z = *(float*)(possibleTransform + 0x28);
            [info appendFormat:@"  position: (%.2f, %.2f, %.2f)\n", x, y, z];
            
            if (fabs(x) < 10000 && fabs(y) < 10000 && fabs(z) < 10000 && (x != 0 || y != 0 || z != 0)) {
                [info appendString:@"  ✅ ПОХОЖЕ НА РЕАЛЬНЫЕ КООРДИНАТЫ!\n"];
            } else {
                [info appendString:@"  ❌ Координаты нереалистичные\n"];
            }
        } else {
            [info appendString:@"❌ Адрес не выровнен или NULL, это не Transform\n"];
            // Показываем сырые данные по этому адресу
            [info appendString:@"Raw data at this address:\n"];
            for (int j = 0; j < 32; j += 8) {
                uint64_t val = *(uint64_t*)(possibleTransform + j);
                [info appendFormat:@"  +0x%02x: 0x%016llx\n", j, (unsigned long long)val];
            }
        }
        
        // Также проверим другие возможные смещения для AxeArms (не только 0x150)
        [info appendString:@"\nПроверка других возможных смещений для Transform:\n"];
        int testOffsets[] = {0x28, 0x30, 0x38, 0x40, 0x48, 0x50, 0x58, 0x60, 0x68, 0x70, 0x78, 0x80, 0x88, 0x90, 0x98, 0xA0, 0xA8, 0xB0, 0xB8, 0xC0, 0xC8, 0xD0, 0xD8, 0xE0, 0xE8, 0xF0, 0xF8, 0x100, 0x108, 0x110, 0x118, 0x120, 0x128, 0x130, 0x138, 0x140, 0x148, 0x150, 0x158, 0x160, 0x168, 0x170, 0x178, 0x180};
        
        for (int j = 0; j < sizeof(testOffsets)/sizeof(int); j++) {
            int testOffset = testOffsets[j];
            uintptr_t testPtr = *(uintptr_t*)(firstPerson + testOffset);
            if (testPtr != 0 && (testPtr & 0x7) == 0) {
                // Проверяем, похоже ли на Transform
                uintptr_t klass = *(uintptr_t*)testPtr;
                // Transform обычно имеет vtable в диапазоне UnityFramework
                if (klass > base && klass < base + 0x20000000) {
                    float x = *(float*)(testPtr + 0x20);
                    float y = *(float*)(testPtr + 0x24);
                    float z = *(float*)(testPtr + 0x28);
                    if (fabs(x) < 10000 && fabs(y) < 10000 && fabs(z) < 10000 && (x != 0 || y != 0 || z != 0)) {
                        [info appendFormat:@"  ✅ Найден! offset 0x%02x: pos=(%.2f, %.2f, %.2f)\n", testOffset, x, y, z];
                    }
                }
            }
        }
    }
    
    [self showAlert:@"Raw Data Debug" message:info];
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
                                                              360, 500)];
    menuContainer.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:0.95];
    menuContainer.layer.cornerRadius = 12;
    menuContainer.hidden = YES;
    menuContainer.userInteractionEnabled = YES;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, 360, 28)];
    title.text = @"Modern Strike Debug - Find Transform";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [menuContainer addSubview:title];
    
    UIButton *debugBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    debugBtn.frame = CGRectMake(10, 45, 340, 40);
    debugBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:1];
    debugBtn.layer.cornerRadius = 8;
    [debugBtn setTitle:@"🔍 Найти Transform (AxeArms)" forState:UIControlStateNormal];
    [debugBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    debugBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [debugBtn addTarget:self action:@selector(debugRawData) forControlEvents:UIControlEventTouchUpInside];
    [menuContainer addSubview:debugBtn];
    
    debugText = [[UITextView alloc] initWithFrame:CGRectMake(5, 95, 350, 390)];
    debugText.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1];
    debugText.textColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1];
    debugText.font = [UIFont fontWithName:@"Courier" size:9];
    debugText.editable = NO;
    debugText.text = @"Нажми кнопку после захода в матч";
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
