#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define LOG(fmt, ...) NSLog(@"[Aimbot] " fmt, ##__VA_ARGS__)

#pragma mark - Тест загрузки

__attribute__((constructor))
static void init() {
    LOG("📦 Tweak loaded!");
    
    // Ждем 5 секунд
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        LOG("✅ Aimbot ready!");
        
        // Безопасно получаем окно (iOS 13+)
        UIWindow *keyWindow = nil;
        NSArray<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes.allObjects;
        for (UIScene *scene in scenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                keyWindow = ((UIWindowScene *)scene).windows.firstObject;
                break;
            }
        }
        
        if (keyWindow) {
            LOG("✅ Window found: %@", keyWindow);
            
            // Ищем UILabel
            for (UIView *subview in keyWindow.subviews) {
                if ([subview isKindOfClass:[UILabel class]]) {
                    UILabel *label = (UILabel *)subview;
                    LOG("✅ Found label: %@", label.text);
                }
            }
        } else {
            LOG("❌ No window found");
        }
    });
}

#pragma mark - Простой хук для теста

%hook UIViewController
- (void)viewDidLoad {
    %orig;
    LOG("✅ ViewController loaded: %@", NSStringFromClass([self class]));
}
%end
