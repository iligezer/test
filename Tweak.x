#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ============================================
// КЛАСС КНОПКИ (как в FloatButton.h)
// ============================================
@interface FloatButton : UIImageView
@property (nonatomic, copy) void (^actionBlock)(void);
- (void)setAction:(void (^)(void))block;
@end

@implementation FloatButton

- (instancetype)init {
    // Размер как у H5GG: 50x50
    self = [super initWithFrame:CGRectMake(20, 100, 50, 50)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 25;
        self.userInteractionEnabled = YES;
        
        // Тап обрабатываем через gesture recognizer (как в H5GG)
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)handleTap {
    if (self.actionBlock) {
        self.actionBlock();
    }
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block;
}

@end

// ============================================
// ОКНО, КОТОРОЕ ПРОПУСКАЕТ ВСЁ, КРОМЕ КНОПКИ
// ============================================
@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *floatButton;
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // Проверяем только кнопку
    if (self.floatButton && !self.floatButton.hidden) {
        CGPoint buttonPoint = [self convertPoint:point toView:self.floatButton];
        if ([self.floatButton pointInside:buttonPoint withEvent:event]) {
            return self.floatButton;
        }
    }
    // Всё остальное — в игру
    return nil;
}

@end

// ============================================
// ОСНОВНОЙ КЛАСС
// ============================================
@interface TweakMain : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
@property (nonatomic, strong) FloatButton *floatButton;
@end

@implementation TweakMain

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup {
    NSLog(@"[Aimbot] Создание окна и кнопки");
    
    // 1. Окно
    self.window = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.hidden = NO;
    
    // 2. Кнопка
    self.floatButton = [[FloatButton alloc] init];
    self.window.floatButton = self.floatButton;
    [self.window addSubview:self.floatButton];
    
    // 3. Действие на кнопку
    __weak typeof(self) weakSelf = self;
    [self.floatButton setAction:^{
        [weakSelf buttonTapped];
    }];
    
    NSLog(@"[Aimbot] Готово");
}

- (void)buttonTapped {
    NSLog(@"[Aimbot] Кнопка нажата!");
    
    // Простой алерт — видно сразу
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Aimbot"
                                                                   message:@"Кнопка работает!"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    // Показываем через главное окно игры
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

@end

// ============================================
// КОНСТРУКТОР
// ============================================
static TweakMain *main = nil;

__attribute__((constructor))
static void init() {
    NSLog(@"[Aimbot] Загрузка...");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        main = [[TweakMain alloc] init];
    });
}
