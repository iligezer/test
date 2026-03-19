#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define LOG(fmt, ...) NSLog(@"[Aimbot] " fmt, ##__VA_ARGS__)

static UIButton *g_floatButton = nil;
static BOOL g_menuVisible = NO;
static UIView *g_menuView = nil;

#pragma mark - Действия (объявляем заранее)

void toggleMenu();
void testAction();
void dragButton(UIPanGestureRecognizer *gesture);

#pragma mark - Создание плавающей кнопки

void createFloatingButton() {
    @autoreleasepool {
        // Получаем активное окно
        UIWindow *keyWindow = nil;
        NSArray<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes.allObjects;
        for (UIScene *scene in scenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                keyWindow = ((UIWindowScene *)scene).windows.firstObject;
                break;
            }
        }
        
        if (!keyWindow) {
            LOG("No window found");
            return;
        }
        
        // Создаем плавающую кнопку
        g_floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
        g_floatButton.frame = CGRectMake(20, 100, 50, 50);
        g_floatButton.backgroundColor = [UIColor systemBlueColor];
        g_floatButton.layer.cornerRadius = 25;
        g_floatButton.layer.borderWidth = 2;
        g_floatButton.layer.borderColor = [UIColor whiteColor].CGColor;
        [g_floatButton setTitle:@"🎯" forState:UIControlStateNormal];
        g_floatButton.titleLabel.font = [UIFont systemFontOfSize:24];
        
        // Добавляем действие (nil вместо self)
        [g_floatButton addTarget:nil 
                          action:@selector(toggleMenu) 
                forControlEvents:UIControlEventTouchUpInside];
        
        // Добавляем возможность перетаскивания
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] 
                                       initWithTarget:nil 
                                       action:@selector(dragButton:)];
        [g_floatButton addGestureRecognizer:pan];
        
        [keyWindow addSubview:g_floatButton];
        
        // Создаем меню (изначально скрыто)
        g_menuView = [[UIView alloc] initWithFrame:CGRectMake(80, 100, 220, 200)];
        g_menuView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
        g_menuView.layer.cornerRadius = 10;
        g_menuView.layer.borderWidth = 1;
        g_menuView.layer.borderColor = [UIColor whiteColor].CGColor;
        g_menuView.hidden = YES;
        
        // Заголовок
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 220, 30)];
        titleLabel.text = @"Aimbot Menu";
        titleLabel.textColor = [UIColor whiteColor];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        [g_menuView addSubview:titleLabel];
        
        // Кнопка теста
        UIButton *testBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        testBtn.frame = CGRectMake(20, 50, 180, 40);
        [testBtn setTitle:@"Test" forState:UIControlStateNormal];
        testBtn.backgroundColor = [UIColor systemGray5Color];
        testBtn.layer.cornerRadius = 5;
        [testBtn addTarget:nil 
                    action:@selector(testAction) 
          forControlEvents:UIControlEventTouchUpInside];
        [g_menuView addSubview:testBtn];
        
        // Кнопка закрытия
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(20, 100, 180, 40);
        [closeBtn setTitle:@"Close" forState:UIControlStateNormal];
        closeBtn.backgroundColor = [UIColor systemGray5Color];
        closeBtn.layer.cornerRadius = 5;
        [closeBtn addTarget:nil 
                     action:@selector(toggleMenu) 
           forControlEvents:UIControlEventTouchUpInside];
        [g_menuView addSubview:closeBtn];
        
        [keyWindow addSubview:g_menuView];
        
        LOG("Floating button created");
    }
}

#pragma mark - Действия

void toggleMenu() {
    g_menuVisible = !g_menuVisible;
    g_menuView.hidden = !g_menuVisible;
    LOG("Menu toggled");
}

void testAction() {
    LOG("Test button pressed");
    
    // Здесь будет поиск классов
    NSArray *classes = @[@"GameManager", @"PlayerController", @"Weapon"];
    for (NSString *name in classes) {
        Class cls = objc_getClass([name UTF8String]);
        if (cls) {
            LOG("✅ Found class: %@", name);
        } else {
            LOG("❌ Class not found: %@", name);
        }
    }
}

void dragButton(UIPanGestureRecognizer *gesture) {
    UIView *button = gesture.view;
    CGPoint translation = [gesture translationInView:button.superview];
    button.center = CGPointMake(
        button.center.x + translation.x,
        button.center.y + translation.y
    );
    [gesture setTranslation:CGPointZero inView:button.superview];
}

#pragma mark - Конструктор

__attribute__((constructor))
static void init() {
    LOG("Tweak loaded!");
    
    // Ждем 5 секунд, чтобы игра полностью загрузилась
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 
                   dispatch_get_main_queue(), ^{
        LOG("Creating UI...");
        createFloatingButton();
    });
}
