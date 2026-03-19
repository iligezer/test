#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>

// ===== ПРОТОТИПЫ =====
void showResultWindow(NSString *text);
uintptr_t getBaseAddress();

// ===== РАБОТА С ПАМЯТЬЮ =====
uintptr_t getBaseAddress() {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (strstr(name, "UnityFramework") != NULL) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

void scanMemory() {
    NSMutableString *log = [NSMutableString stringWithString:@"🔬 СКАНИРОВАНИЕ ПАМЯТИ\n\n"];
    uintptr_t base = getBaseAddress();
    [log appendFormat:@"📍 UnityFramework: 0x%lx\n", base];
    [log appendString:@"\n📋 Для ESP нужно найти:\n"];
    [log appendString:@"• GameManager::Instance\n"];
    [log appendString:@"• PlayerController::_health\n"];
    [log appendString:@"• PlayerController::_transform\n"];
    showResultWindow(log);
}

void showResultWindow(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *w in ws.windows) {
                    if (w.isKeyWindow) {
                        keyWindow = w;
                        break;
                    }
                }
            }
            if (keyWindow) break;
        }
        
        if (!keyWindow) return;
        
        UIWindow *resultWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, keyWindow.frame.size.width - 40, 400)];
        resultWindow.windowLevel = UIWindowLevelAlert + 2;
        resultWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        resultWindow.layer.cornerRadius = 15;
        resultWindow.layer.borderWidth = 1;
        resultWindow.layer.borderColor = [UIColor cyanColor].CGColor;
        resultWindow.hidden = NO;
        
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, resultWindow.frame.size.width, 40)];
        title.text = @"🔬 РЕЗУЛЬТАТЫ";
        title.textColor = [UIColor cyanColor];
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont boldSystemFontOfSize:16];
        [resultWindow addSubview:title];
        
        UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(10, 60, resultWindow.frame.size.width - 20, 260)];
        textView.backgroundColor = [UIColor blackColor];
        textView.textColor = [UIColor greenColor];
        textView.font = [UIFont fontWithName:@"Courier" size:11];
        textView.text = text;
        textView.editable = NO;
        textView.selectable = YES;
        [resultWindow addSubview:textView];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(resultWindow.frame.size.width/2 - 50, 340, 100, 40);
        [closeBtn setTitle:@"ЗАКРЫТЬ" forState:UIControlStateNormal];
        closeBtn.backgroundColor = [UIColor systemBlueColor];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        closeBtn.layer.cornerRadius = 8;
        closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [closeBtn addTarget:resultWindow action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
        [resultWindow addSubview:closeBtn];
        
        [resultWindow makeKeyAndVisible];
    });
}

// ===== ПЛАВАЮЩАЯ КНОПКА =====
@interface FloatButton : UIImageView
@property (nonatomic, copy) void (^actionBlock)(void);
@property (nonatomic, assign) CGPoint lastLocation;
- (void)setAction:(void (^)(void))block;
@end

@implementation FloatButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 65, 65)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 32.5;
        self.layer.borderWidth = 3;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        self.userInteractionEnabled = YES;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        self.layer.shadowOpacity = 0.5;
        self.layer.shadowRadius = 6;
        
        // Иконка меню
        UILabel *label = [[UILabel alloc] initWithFrame:self.bounds];
        label.text = @"⚡";
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont boldSystemFontOfSize:28];
        [self addSubview:label];
        
        // Жест для перетаскивания
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
        [self addGestureRecognizer:pan];
        
        // Жест для нажатия
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)dragButton:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.lastLocation = self.center;
    }
    
    CGPoint newCenter = CGPointMake(self.lastLocation.x + translation.x, self.lastLocation.y + translation.y);
    
    // Ограничиваем, чтобы кнопка не уходила за края
    CGFloat halfWidth = self.frame.size.width / 2;
    CGFloat halfHeight = self.frame.size.height / 2;
    CGFloat minX = halfWidth;
    CGFloat maxX = self.superview.bounds.size.width - halfWidth;
    CGFloat minY = halfHeight + 50; // Отступ сверху для статус-бара
    CGFloat maxY = self.superview.bounds.size.height - halfHeight - 50; // Отступ снизу
    
    newCenter.x = MAX(minX, MIN(maxX, newCenter.x));
    newCenter.y = MAX(minY, MIN(maxY, newCenter.y));
    
    self.center = newCenter;
}

- (void)handleTap {
    if (self.actionBlock) self.actionBlock();
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block;
}

@end

// ===== ОКНО, ПРОПУСКАЮЩЕЕ КАСАНИЯ =====
@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *floatButton;
@property (nonatomic, weak) UIView *menuView;
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.floatButton && !self.floatButton.hidden) {
        CGPoint buttonPoint = [self convertPoint:point toView:self.floatButton];
        if ([self.floatButton pointInside:buttonPoint withEvent:event]) {
            return self.floatButton;
        }
    }
    if (self.menuView && !self.menuView.hidden) {
        CGPoint menuPoint = [self convertPoint:point toView:self.menuView];
        if ([self.menuView pointInside:menuPoint withEvent:event]) {
            return [self.menuView hitTest:menuPoint withEvent:event];
        }
    }
    return nil;
}

@end

// ===== КРАСИВОЕ СОВРЕМЕННОЕ МЕНЮ =====
@interface ModernMenuView : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@end

@implementation ModernMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupModernStyle];
    }
    return self;
}

- (void)setupModernStyle {
    // Размеры меню
    CGFloat menuWidth = 300;
    CGFloat menuHeight = 400;
    CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    
    // Центрируем меню на экране
    self.frame = CGRectMake((screenWidth - menuWidth) / 2, (screenHeight - menuHeight) / 2, menuWidth, menuHeight);
    
    // Блюр эффект (стекло)
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.blurView.frame = self.bounds;
    self.blurView.layer.cornerRadius = 25;
    self.blurView.layer.masksToBounds = YES;
    self.blurView.alpha = 0.98;
    [self addSubview:self.blurView];
    
    // Градиентная обводка
    self.layer.cornerRadius = 25;
    self.layer.borderWidth = 2;
    self.layer.borderColor = [UIColor clearColor].CGColor;
    
    // Тень
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 10);
    self.layer.shadowOpacity = 0.5;
    self.layer.shadowRadius = 20;
    
    // Хедер
    self.headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, menuWidth, 60)];
    self.headerView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.5];
    
    // Верхний акцент (полоска)
    UIView *topAccent = [[UIView alloc] initWithFrame:CGRectMake(0, 0, menuWidth, 3)];
    topAccent.backgroundColor = [UIColor systemBlueColor];
    [self.headerView addSubview:topAccent];
    
    // Заголовок
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, menuWidth - 80, 30)];
    self.titleLabel.text = @"🎯 ESP CONTROL";
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.headerView addSubview:self.titleLabel];
    
    // Кнопка закрытия
    self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.closeButton.frame = CGRectMake(menuWidth - 45, 15, 30, 30);
    [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    self.closeButton.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.8];
    self.closeButton.layer.cornerRadius = 15;
    [self.closeButton addTarget:self action:@selector(hideMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.closeButton];
    
    [self addSubview:self.headerView];
}

- (void)hideMenu {
    self.hidden = YES;
}

- (UIButton *)createButtonWithTitle:(NSString *)title color:(UIColor *)color yPos:(CGFloat)yPos {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(20, yPos, self.frame.size.width - 40, 50);
    button.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.8];
    button.layer.cornerRadius = 15;
    
    // Градиент для кнопки
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = button.bounds;
    gradient.colors = @[(id)[color colorWithAlphaComponent:0.8].CGColor, (id)[color colorWithAlphaComponent:0.4].CGColor];
    gradient.startPoint = CGPointMake(0, 0);
    gradient.endPoint = CGPointMake(1, 0);
    gradient.cornerRadius = 15;
    [button.layer insertSublayer:gradient atIndex:0];
    
    // Заголовок
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.titleEdgeInsets = UIEdgeInsetsMake(0, 20, 0, 0);
    
    // Иконка справа
    UILabel *arrow = [[UILabel alloc] initWithFrame:CGRectMake(button.frame.size.width - 40, 0, 30, 50)];
    arrow.text = @"→";
    arrow.textColor = [UIColor whiteColor];
    arrow.font = [UIFont boldSystemFontOfSize:20];
    arrow.textAlignment = NSTextAlignmentRight;
    [button addSubview:arrow];
    
    return button;
}

- (void)addSwitchButtonWithTitle:(NSString *)title yPos:(CGFloat)yPos target:(id)target selector:(SEL)selector {
    UIView *rowView = [[UIView alloc] initWithFrame:CGRectMake(20, yPos, self.frame.size.width - 40, 50)];
    rowView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.8];
    rowView.layer.cornerRadius = 15;
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, 180, 50)];
    label.text = title;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:16];
    [rowView addSubview:label];
    
    UISwitch *switchCtrl = [[UISwitch alloc] initWithFrame:CGRectMake(rowView.frame.size.width - 70, 10, 50, 30)];
    switchCtrl.onTintColor = [UIColor systemBlueColor];
    switchCtrl.tag = 100; // Можно использовать для идентификации
    [rowView addSubview:switchCtrl];
    
    [self addSubview:rowView];
}

@end

// ===== UI ТВИКА =====
@interface AimbotUI : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
@property (nonatomic, strong) FloatButton *floatButton;
@property (nonatomic, strong) ModernMenuView *menuView;
@property (nonatomic, assign) BOOL menuVisible;
@end

@implementation AimbotUI

- (instancetype)init {
    self = [super init];
    if (self) [self setupUI];
    return self;
}

- (void)setupUI {
    self.window = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.hidden = NO;
    
    self.floatButton = [[FloatButton alloc] init];
    self.window.floatButton = self.floatButton;
    [self.window addSubview:self.floatButton];
    
    __weak typeof(self) weakSelf = self;
    [self.floatButton setAction:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf toggleMenu];
        }
    }];
    
    [self buildModernMenu];
}

- (void)buildModernMenu {
    self.menuView = [[ModernMenuView alloc] initWithFrame:CGRectZero];
    self.menuView.hidden = YES;
    self.window.menuView = self.menuView;
    [self.window addSubview:self.menuView];
    
    // Добавляем кнопки
    CGFloat yPos = 80;
    
    // Сканирование памяти
    UIButton *scanBtn = [self.menuView createButtonWithTitle:@"🔍 SCAN MEMORY" color:[UIColor systemIndigoColor] yPos:yPos];
    [scanBtn addTarget:self action:@selector(scanMemoryAction) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:scanBtn];
    
    yPos += 70;
    
    // ESP Toggle
    [self.menuView addSwitchButtonWithTitle:@"👁️ ESP WALLHACK" yPos:yPos target:self selector:nil];
    
    yPos += 70;
    
    // Aimbot Toggle
    [self.menuView addSwitchButtonWithTitle:@"🎯 AIMBOT" yPos:yPos target:self selector:nil];
    
    yPos += 70;
    
    // Инфо кнопка
    UIButton *infoBtn = [self.menuView createButtonWithTitle:@"ℹ️ INFORMATION" color:[UIColor systemGrayColor] yPos:yPos];
    [infoBtn addTarget:self action:@selector(infoAction) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:infoBtn];
}

- (void)toggleMenu {
    self.menuVisible = !self.menuVisible;
    
    if (self.menuVisible) {
        self.menuView.hidden = NO;
        self.menuView.transform = CGAffineTransformMakeScale(0.8, 0.8);
        self.menuView.alpha = 0;
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0 animations:^{
            self.menuView.transform = CGAffineTransformIdentity;
            self.menuView.alpha = 1;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.2 animations:^{
            self.menuView.transform = CGAffineTransformMakeScale(0.8, 0.8);
            self.menuView.alpha = 0;
        } completion:^(BOOL finished) {
            self.menuView.hidden = YES;
            self.menuView.transform = CGAffineTransformIdentity;
        }];
    }
}

- (void)scanMemoryAction {
    scanMemory();
}

- (void)infoAction {
    NSMutableString *log = [NSMutableString stringWithString:@"ℹ️ ИНФОРМАЦИЯ\n\n"];
    uintptr_t base = getBaseAddress();
    [log appendFormat:@"📍 UnityFramework: 0x%lx\n", base];
    [log appendString:@"\n📋 Modern Strike Online\n"];
    [log appendString:@"🎯 ESP Development\n"];
    [log appendString:@"⚡ Waiting for Il2CppDumper\n"];
    showResultWindow(log);
}

@end

// ===== ТОЧКА ВХОДА =====
static AimbotUI *g_ui = nil;

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_ui = [[AimbotUI alloc] init];
        NSLog(@"[Modern Strike] Твик загружен!");
    });
}
