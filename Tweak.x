#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

// ========== ПОЛУЧЕНИЕ БАЗОВОГО АДРЕСА ==========
uintptr_t getUnityFrameworkBase() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework")) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

// ========== ВЫВОД КООРДИНАТ НА ЭКРАН ==========
static void showPosition() {
    uintptr_t base = getUnityFrameworkBase();
    if (!base) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"ESP"
            message:@"UnityFramework не найден"
            delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
        return;
    }
    
    // Наши смещения из IDA
    uintptr_t typeInfo = base + 0x8E15248;
    uintptr_t static_fields = *(uintptr_t*)(typeInfo + 0x08);
    
    // Пробуем оба кандидата
    uintptr_t player1 = *(uintptr_t*)(static_fields + 0x28);
    uintptr_t player2 = *(uintptr_t*)(static_fields + 0x30);
    
    float x1 = 0, y1 = 0, z1 = 0;
    float x2 = 0, y2 = 0, z2 = 0;
    
    if (player1) {
        uintptr_t transform1 = *(uintptr_t*)(player1 + 0x150);
        if (transform1) {
            x1 = *(float*)(transform1 + 0x20);
            y1 = *(float*)(transform1 + 0x24);
            z1 = *(float*)(transform1 + 0x28);
        }
    }
    
    if (player2) {
        uintptr_t transform2 = *(uintptr_t*)(player2 + 0x150);
        if (transform2) {
            x2 = *(float*)(transform2 + 0x20);
            y2 = *(float*)(transform2 + 0x24);
            z2 = *(float*)(transform2 + 0x28);
        }
    }
    
    NSString *msg = [NSString stringWithFormat:
        @"База: 0x%lX\n\n"
        @"Кандидат +0x28:\n"
        @"  Player: 0x%lX\n"
        @"  Transform: 0x%lX\n"
        @"  X: %.2f Y: %.2f Z: %.2f\n\n"
        @"Кандидат +0x30:\n"
        @"  Player: 0x%lX\n"
        @"  Transform: 0x%lX\n"
        @"  X: %.2f Y: %.2f Z: %.2f",
        base,
        player1, *(uintptr_t*)(player1 + 0x150), x1, y1, z1,
        player2, *(uintptr_t*)(player2 + 0x150), x2, y2, z2];
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Modern Strike ESP"
        message:msg
        delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alert show];
}

// ========== ХУК НА ЗАГРУЗКУ ИГРЫ ==========
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        showPosition();
    });
}
