#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>

// ============================================
// ПРОТОТИПЫ
// ============================================
void showResultWindow(NSString *text);
void scanClasses(void);

// ============================================
// ФУНКЦИЯ ПОКАЗА ОКНА С РЕЗУЛЬТАТАМИ
// ============================================
void showResultWindow(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Получаем активное окно
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
        
        // Создаём окно поверх игры
        UIWindow *resultWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, keyWindow.frame.size.width - 40, 400)];
        resultWindow.windowLevel = UIWindowLevelAlert + 2;
        resultWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        resultWindow.layer.cornerRadius = 15;
        resultWindow.layer.borderWidth = 2;
        resultWindow.layer.borderColor = [UIColor systemBlueColor].CGColor;
        resultWindow.hidden = NO;
        
        // Заголовок
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, resultWindow.frame.size.width, 40)];
        title.text = @"📊 Результаты сканирования";
        title.textColor = [UIColor whiteColor];
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont boldSystemFontOfSize:18];
        [resultWindow addSubview:title];
        
        // Текстовое поле с результатами
        UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(10, 60, resultWindow.frame.size.width - 20, 260)];
        textView.backgroundColor = [UIColor blackColor];
        textView.textColor = [UIColor greenColor];
        textView.font = [UIFont fontWithName:@"Courier" size:12];
        textView.text = text;
        textView.editable = NO;
        textView.selectable = YES; // можно копировать
        textView.layer.cornerRadius = 8;
        [resultWindow addSubview:textView];
        
        // Кнопка закрытия
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(resultWindow.frame.size.width/2 - 50, 340, 100, 40);
        [closeBtn setTitle:@"Закрыть" forState:UIControlStateNormal];
        closeBtn.backgroundColor = [UIColor systemBlueColor];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        closeBtn.layer.cornerRadius = 8;
        [closeBtn addTarget:resultWindow action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
        [resultWindow addSubview:closeBtn];
        
        [resultWindow makeKeyAndVisible];
    });
}

// ============================================
// СКАНИРОВАНИЕ КЛАССОВ
// ============================================
void scanClasses() {
    NSMutableString *result = [NSMutableString stringWithString:@"=== РЕЗУЛЬТАТЫ СКАНИРОВАНИЯ ===\n\n"];
    
    NSArray *classNames = @[
        @"GameManager", @"PlayerManager", @"EnemyManager",
        @"PlayerController", @"EnemyController", @"WeaponController",
        @"CameraController", @"UnityEngine_GameObject", @"UnityEngine_Transform"
    ];
    
    int found = 0;
    for (NSString *name in classNames) {
        Class cls = objc_getClass([name UTF8String]);
        if (cls) {
            [result appendFormat:@"✅ %@\n", name];
            found++;
        } else {
            [result appendFormat:@"❌ %@\n", name];
        }
    }
    
    [result appendFormat:@"\n📊 Найдено классов: %d из %lu", found, (unsigned long)classNames.count];
    
    // Показываем окно с результатами
    showResultWindow(result);
}

// ============================================
// ПЛАВАЮЩАЯ КНОПКА
// ============================================
@interface FloatButton : UIImageView
@property (nonatomic, copy) void (^actionBlock)(void);
- (void)setAction:(void (^)(void))block;
@end

@implementation FloatButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 50, 50)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 25;
        self.userInteractionEnabled = YES;
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)handleTap {
    if (self.actionBlock) self.actionBlock();
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block;
}

@end

// ============================================
// ПРОЗРАЧНОЕ ОКНО
// ============================================
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

// ============================================
// ОСНОВНОЙ КЛАСС
// ============================================
@interface AimbotUI : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
@property (nonatomic, strong) FloatButton *floatButton;
@property (nonatomic, strong) UIView *menuView;
@property (nonatomic, assign) BOOL menuVisible;
@end

@implementation AimbotUI

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupUI];
    }
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
        [weakSelf toggleMenu];
    }];
    
    [self buildMenu];
}

- (void)buildMenu {
    self.menuView = [[UIView alloc] initWithFrame:CGRectMake(80, 160, 260, 300)];
    self.menuView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.menuView.layer.cornerRadius = 15;
    self.menuView.layer.borderWidth = 2;
    self.menuView.layer.borderColor = [UIColor systemBlueColor].CGColor;
    self.menuView.hidden = YES;
    self.window.menuView = self.menuView;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 260, 40)];
    title.text = @"Aimbot Control";
    title.textColor = [UIColor whiteColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:18];
    [self.menuView addSubview:title];
    
    // Кнопка сканирования
    UIButton *scanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    scanBtn.frame = CGRectMake(30, 70, 200, 50);
    [scanBtn setTitle:@"🔍 Scan Classes" forState:UIControlStateNormal];
    scanBtn.backgroundColor = [UIColor systemGrayColor];
    [scanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    scanBtn.layer.cornerRadius = 10;
    [scanBtn addTarget:self action:@selector(scanAction) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:scanBtn];
    
    // Кнопка закрытия меню
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(30, 140, 200, 50);
    [closeBtn setTitle:@"❌ Close Menu" forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor systemRedColor];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 10;
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.menuView addSubview:closeBtn];
    
    [self.window addSubview:self.menuView];
}

- (void)toggleMenu {
    self.menuVisible = !self.menuVisible;
    self.menuView.hidden = !self.menuVisible;
}

- (void)scanAction {
    scanClasses();
}

@end

// ============================================
// КОНСТРУКТОР
// ============================================
static AimbotUI *g_ui = nil;

__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_ui = [[AimbotUI alloc] init];
    });
}
