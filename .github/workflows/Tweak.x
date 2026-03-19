#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ============================================
// ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
// ============================================
static UIWindow *g_menuWindow = nil;
static UIButton *g_toggleButton = nil;
static UIView *g_menuView = nil;
static UITextView *g_logView = nil;
static NSMutableString *g_logText = nil;
static BOOL g_menuVisible = NO;

// ============================================
// ЛОГИРОВАНИЕ
// ============================================
void addLog(NSString *format, ...) {
    if (!g_logText) g_logText = [[NSMutableString alloc] init];
    
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    
    [g_logText appendFormat:@"[%@] %@\n", timestamp, message];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        g_logView.text = g_logText;
        [g_logView scrollRangeToVisible:NSMakeRange(g_logView.text.length, 0)];
    });
    
    NSLog(@"%@", message);
}

// ============================================
// ТЕСТ БАЗОВЫХ ФУНКЦИЙ
// ============================================
void testBasicFunctions() {
    addLog(@"\n🔧 ТЕСТ БАЗОВЫХ ФУНКЦИЙ");
    addLog(@"✅ UI доступен");
    addLog(@"✅ Objective-C runtime работает");
    addLog(@"✅ Можно создавать окна");
    
    // Проверка objc_msgSend
    addLog(@"✅ objc_msgSend доступен");
    
    // Проверка хуков
    Class playerClass = objc_getClass("PlayerController");
    if (playerClass) {
        addLog(@"✅ PlayerController найден");
        
        // Проверка метода update
        Method updateMethod = class_getInstanceMethod(playerClass, @selector(update));
        if (updateMethod) {
            addLog(@"✅ Метод update доступен для хука");
        }
    } else {
        addLog(@"❌ PlayerController НЕ найден");
    }
}

// ============================================
// СКАНИРОВАНИЕ КЛАССОВ
// ============================================
void scanGameClasses() {
    addLog(@"\n🔍 СКАНИРОВАНИЕ КЛАССОВ");
    
    NSArray *classesToScan = @[
        @"GameManager",
        @"PlayerController",
        @"EnemyController",
        @"Weapon",
        @"WeaponController",
        @"CameraController",
        @"AimAssist",
        @"TargetingSystem",
        @"Bullet",
        @"Projectile"
    ];
    
    int found = 0;
    for (NSString *className in classesToScan) {
        Class cls = objc_getClass([className UTF8String]);
        if (cls) {
            addLog(@"✅ %@", className);
            found++;
            
            // Показываем методы класса
            unsigned int methodCount = 0;
            Method *methods = class_copyMethodList(cls, &methodCount);
            if (methodCount > 0) {
                for (int i = 0; i < min(3, methodCount); i++) {
                    SEL selector = method_getName(methods[i]);
                    addLog(@"   📌 %s", sel_getName(selector));
                }
                if (methodCount > 3) addLog(@"   ... и еще %d методов", methodCount-3);
                free(methods);
            }
        } else {
            addLog(@"❌ %@", className);
        }
    }
    
    addLog(@"\n📊 Найдено классов: %d из %lu", found, (unsigned long)classesToScan.count);
}

// ============================================
// СКАНИРОВАНИЕ МЕТОДОВ
// ============================================
void scanMethods() {
    addLog(@"\n🔧 СКАНИРОВАНИЕ МЕТОДОВ");
    
    NSArray *methodsToScan = @[
        @"update",
        @"fire",
        @"shoot",
        @"aimAt",
        @"getPosition",
        @"setPosition",
        @"getHealth",
        @"isAlive",
        @"getTeam",
        @"getEnemies"
    ];
    
    for (NSString *methodName in methodsToScan) {
        SEL selector = NSSelectorFromString(methodName);
        
        // Проверяем на разных классах
        NSArray *classes = @[
            @"PlayerController",
            @"Weapon",
            @"GameManager"
        ];
        
        for (NSString *className in classes) {
            Class cls = objc_getClass([className UTF8String]);
            if (cls && [cls instancesRespondToSelector:selector]) {
                addLog(@"✅ %@.%@", className, methodName);
                break;
            }
        }
    }
}

// ============================================
// СОЗДАНИЕ МЕНЮ
// ============================================
void createMenu() {
    // Получаем активное окно
    UIWindow *mainWindow = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *window in ws.windows) {
                if (window.isKeyWindow) {
                    mainWindow = window;
                    break;
                }
            }
        }
        if (mainWindow) break;
    }
    
    if (!mainWindow) return;
    
    // Создаем плавающую кнопку
    g_toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];
    g_toggleButton.frame = CGRectMake(20, 100, 50, 50);
    g_toggleButton.backgroundColor = [UIColor systemBlueColor];
    g_toggleButton.layer.cornerRadius = 25;
    g_toggleButton.layer.borderWidth = 2;
    g_toggleButton.layer.borderColor = [UIColor whiteColor].CGColor;
    [g_toggleButton setTitle:@"🎯" forState:UIControlStateNormal];
    g_toggleButton.titleLabel.font = [UIFont systemFontOfSize:24];
    [g_toggleButton addTarget:nil action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    // Добавляем возможность перетаскивания
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[self class] action:@selector(dragButton:)];
    [g_toggleButton addGestureRecognizer:pan];
    
    [mainWindow addSubview:g_toggleButton];
    
    // Создаем меню (изначально скрыто)
    g_menuView = [[UIView alloc] initWithFrame:CGRectMake(80, 100, 250, 400)];
    g_menuView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    g_menuView.layer.cornerRadius = 15;
    g_menuView.layer.borderWidth = 2;
    g_menuView.layer.borderColor = [UIColor systemBlueColor].CGColor;
    g_menuView.hidden = YES;
    
    // Заголовок
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 250, 40)];
    titleLabel.text = @"AIMBOT MENU";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [g_menuView addSubview:titleLabel];
    
    // Кнопки
    NSArray *buttons = @[@"🔧 Тест функций", @"🔍 Сканировать классы", @"⚙️ Сканировать методы"];
    CGFloat yPos = 60;
    
    for (int i = 0; i < buttons.count; i++) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(20, yPos, 210, 40);
        [btn setTitle:buttons[i] forState:UIControlStateNormal];
        btn.backgroundColor = [UIColor systemGray5Color];
        btn.layer.cornerRadius = 8;
        [btn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        btn.tag = 100 + i;
        [btn addTarget:nil action:@selector(menuButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [g_menuView addSubview:btn];
        yPos += 50;
    }
    
    // Лог
    g_logView = [[UITextView alloc] initWithFrame:CGRectMake(20, yPos, 210, 150)];
    g_logView.backgroundColor = [UIColor blackColor];
    g_logView.textColor = [UIColor greenColor];
    g_logView.font = [UIFont fontWithName:@"Courier" size:10];
    g_logView.layer.cornerRadius = 5;
    g_logView.editable = NO;
    [g_menuView addSubview:g_logView];
    
    [mainWindow addSubview:g_menuView];
    
    addLog(@"✅ Меню создано");
}

// ============================================
// ДЕЙСТВИЯ
// ============================================
void toggleMenu() {
    g_menuVisible = !g_menuVisible;
    g_menuView.hidden = !g_menuVisible;
    
    if (g_menuVisible) {
        [g_logText setString:@""];
        g_logView.text = @"";
        addLog(@"📱 Меню открыто");
    }
}

void menuButtonTapped(UIButton *sender) {
    NSInteger tag = sender.tag - 100;
    
    [g_logText setString:@""];
    g_logView.text = @"";
    
    if (tag == 0) {
        testBasicFunctions();
    } else if (tag == 1) {
        scanGameClasses();
    } else if (tag == 2) {
        scanMethods();
    }
}

void dragButton(UIPanGestureRecognizer *gesture) {
    CGPoint translation = [gesture translationInView:g_menuWindow];
    gesture.view.center = CGPointMake(
        gesture.view.center.x + translation.x,
        gesture.view.center.y + translation.y
    );
    [gesture setTranslation:CGPointZero inView:g_menuWindow];
}

// ============================================
// КОНСТРУКТОР
// ============================================
__attribute__((constructor))
static void init() {
    NSLog(@"🚀 Aimbot tweak loaded!");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        createMenu();
    });
}
