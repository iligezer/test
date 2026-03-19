#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ============================================
// САМАЯ ПРОСТАЯ ПРОВЕРКА
// ============================================

@interface SimpleTweak : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *button;
@end

@implementation SimpleTweak

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup {
    NSLog(@"[DEBUG] setup called");
    
    // 1. Создаём окно поверх всего
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelAlert + 1000; // максимальный уровень
    self.window.backgroundColor = [UIColor clearColor];
    self.window.userInteractionEnabled = YES;
    
    // 2. Создаём простой UIView как кнопку
    self.button = [[UIView alloc] initWithFrame:CGRectMake(20, 100, 80, 80)];
    self.button.backgroundColor = [UIColor systemBlueColor];
    self.button.layer.cornerRadius = 40;
    self.button.userInteractionEnabled = YES;
    
    // 3. Добавляем обработчик касания
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
    [self.button addGestureRecognizer:tap];
    
    // 4. Добавляем в окно
    [self.window addSubview:self.button];
    self.window.hidden = NO;
    
    NSLog(@"[DEBUG] window created, button added");
}

- (void)handleTap {
    NSLog(@"[DEBUG] BUTTON TAPPED!");
    
    // Просто показываем alert
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Успех"
                                                                   message:@"Кнопка работает!"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    // Показываем через главное окно игры
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    [mainWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

@end

// ============================================
// КОНСТРУКТОР
// ============================================
static SimpleTweak *tweak = nil;

__attribute__((constructor))
static void init() {
    NSLog(@"[DEBUG] constructor called");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSLog(@"[DEBUG] creating tweak");
        tweak = [[SimpleTweak alloc] init];
    });
}
