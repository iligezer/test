#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Простой лог в консоль (видно в Xcode/Console)
#define LOG(fmt, ...) NSLog(@"[Aimbot] " fmt, ##__VA_ARGS__)

#pragma mark - Тест загрузки

__attribute__((constructor))
static void init() {
    LOG("📦 Tweak loaded!");
    
    // Даем игре 5 секунд на инициализацию
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        LOG("✅ Aimbot ready!");
        
        // Просто меняем название кнопки в игре (безопасно)
        UIWindow *keyWindow = nil;
        if (@available(iOS 15.0, *)) {
            keyWindow = [UIApplication sharedApplication].connectedScenes
                .allObjects.firstObject.valueForKeyPath(@"delegate.window");
        } else {
            keyWindow = [UIApplication sharedApplication].keyWindow;
        }
        
        if (keyWindow) {
            LOG("✅ Window found");
            
            // Ищем любую UILabel и меняем текст
            [keyWindow recursiveDescription]; // для логов
        } else {
            LOG("❌ No window");
        }
    });
}

#pragma mark - Хук для проверки

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    LOG("✅ UIViewController appeared: %@", NSStringFromClass([self class]));
}
%end
