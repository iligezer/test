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

// ========== ПОЛУЧЕНИЕ КООРДИНАТ ==========
void getPosition(float *x, float *y, float *z, float *x2, float *y2, float *z2, uintptr_t *player1, uintptr_t *player2, uintptr_t *trans1, uintptr_t *trans2) {
    uintptr_t base = getUnityFrameworkBase();
    if (!base) return;
    
    uintptr_t typeInfo = base + 0x8E15248;
    uintptr_t static_fields = *(uintptr_t*)(typeInfo + 0x08);
    
    *player1 = *(uintptr_t*)(static_fields + 0x28);
    *player2 = *(uintptr_t*)(static_fields + 0x30);
    
    if (*player1) {
        *trans1 = *(uintptr_t*)(*player1 + 0x150);
        if (*trans1) {
            *x = *(float*)(*trans1 + 0x20);
            *y = *(float*)(*trans1 + 0x24);
            *z = *(float*)(*trans1 + 0x28);
        }
    }
    
    if (*player2) {
        *trans2 = *(uintptr_t*)(*player2 + 0x150);
        if (*trans2) {
            *x2 = *(float*)(*trans2 + 0x20);
            *y2 = *(float*)(*trans2 + 0x24);
            *z2 = *(float*)(*trans2 + 0x28);
        }
    }
}

// ========== ПЛАВАЮЩАЯ КНОПКА ==========
@interface FloatingButton : UIButton
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
@end

@implementation FloatingButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:0.9];
        self.layer.cornerRadius = 30;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowRadius = 4;
        self.layer.shadowOpacity = 0.3;
        
        [self setTitle:@"⚡" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont systemFontOfSize:24];
        
        self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:self.panGesture];
    }
    return self;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    
    // Ограничиваем по краям экрана
    CGFloat halfWidth = self.frame.size.width / 2;
    CGFloat halfHeight = self.frame.size.height / 2;
    newCenter.x = MAX(halfWidth, MIN(newCenter.x, self.superview.bounds.size.width - halfWidth));
    newCenter.y = MAX(halfHeight, MIN(newCenter.y, self.superview.bounds.size.height - halfHeight));
    
    self.center = newCenter;
    [gesture setTranslation:CGPointZero inView:self.superview];
}

@end

// ========== МЕНЮ С КНОПКОЙ ПОКАЗАТЬ КООРДИНАТЫ ==========
@interface ESPMenuView : UIView
@property (nonatomic, strong) UIButton *showCoordsButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation ESPMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:0.95];
        self.layer.cornerRadius = 16;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowRadius = 8;
        self.layer.shadowOpacity = 0.5;
        
        // Заголовок
        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 16, frame.size.width - 100, 30)];
        self.titleLabel.text = @"MODERN STRIKE ESP";
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        [self addSubview:self.titleLabel];
        
        // Кнопка показать координаты
        self.showCoordsButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.showCoordsButton.frame = CGRectMake(20, 60, frame.size.width - 40, 44);
        self.showCoordsButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
        self.showCoordsButton.layer.cornerRadius = 8;
        [self.showCoordsButton setTitle:@"📍 ПОКАЗАТЬ КООРДИНАТЫ" forState:UIControlStateNormal];
        [self.showCoordsButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.showCoordsButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [self addSubview:self.showCoordsButton];
        
        // Кнопка закрыть
        self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.closeButton.frame = CGRectMake(frame.size.width - 50, 12, 40, 40);
        [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
        [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
        [self addSubview:self.closeButton];
    }
    return self;
}

@end

// ========== ОСНОВНОЙ КЛАСС ==========
@interface ESPManager : NSObject
@property (nonatomic, strong) FloatingButton *floatButton;
@property (nonatomic, strong) ESPMenuView *menuView;
@property (nonatomic, assign) BOOL isMenuVisible;
@end

@implementation ESPManager

+ (instancetype)shared {
    static ESPManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ESPManager alloc] init];
    });
    return instance;
}

- (void)setupUI {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) return;
        
        // Создаём плавающую кнопку (60x60)
        self.floatButton = [[FloatingButton alloc] initWithFrame:CGRectMake(keyWindow.bounds.size.width - 80, 100, 60, 60)];
        [self.floatButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:self.floatButton];
        
        // Создаём меню (280x160)
        self.menuView = [[ESPMenuView alloc] initWithFrame:CGRectMake(keyWindow.bounds.size.width/2 - 140, keyWindow.bounds.size.height/2 - 80, 280, 160)];
        self.menuView.hidden = YES;
        [self.menuView.showCoordsButton addTarget:self action:@selector(showCoordinates) forControlEvents:UIControlEventTouchUpInside];
        [self.menuView.closeButton addTarget:self action:@selector(hideMenu) forControlEvents:UIControlEventTouchUpInside];
        [keyWindow addSubview:self.menuView];
    });
}

- (void)toggleMenu {
    self.isMenuVisible = !self.isMenuVisible;
    self.menuView.hidden = !self.isMenuVisible;
}

- (void)hideMenu {
    self.isMenuVisible = NO;
    self.menuView.hidden = YES;
}

- (void)showCoordinates {
    float x1 = 0, y1 = 0, z1 = 0;
    float x2 = 0, y2 = 0, z2 = 0;
    uintptr_t player1 = 0, player2 = 0;
    uintptr_t trans1 = 0, trans2 = 0;
    
    getPosition(&x1, &y1, &z1, &x2, &y2, &z2, &player1, &player2, &trans1, &trans2);
    
    uintptr_t base = getUnityFrameworkBase();
    
    NSString *message = [NSString stringWithFormat:
        @"📱 UnityFramework: 0x%lX\n\n"
        @"🔹 Кандидат +0x28:\n"
        @"   Player: 0x%lX\n"
        @"   Transform: 0x%lX\n"
        @"   📍 X: %.2f  Y: %.2f  Z: %.2f\n\n"
        @"🔸 Кандидат +0x30:\n"
        @"   Player: 0x%lX\n"
        @"   Transform: 0x%lX\n"
        @"   📍 X: %.2f  Y: %.2f  Z: %.2f",
        base,
        player1, trans1, x1, y1, z1,
        player2, trans2, x2, y2, z2];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🎯 MODERN STRIKE ESP"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

@end

// ========== ИНИЦИАЛИЗАЦИЯ ПРИ ЗАПУСКЕ ==========
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [[ESPManager shared] setupUI];
    });
}
