#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ========== ОБЪЯВЛЕНИЯ КЛАССОВ ==========
@interface Context : NSObject
+ (instancetype)create:(NSString *)name;
- (id)resolve:(Class)type;
@end

@interface FirstPersonController : NSObject
- (id)RootPoint;
@end

@interface INetworkPlayer : NSObject
- (BOOL)IsMine;
- (BOOL)IsDead;
- (BOOL)IsAllyOfLocalPlayer;
- (id)Transform;
- (float)GetCurrentHealth;
- (id)QuarkPlayer;
@end

@interface QuarkRoomPlayer : NSObject
- (BOOL)IsBot;
- (NSString *)Username;
@end

@interface Camera : NSObject
+ (instancetype)main;
- (id)WorldToScreenPoint:(id)point;
@end

@interface Transform : NSObject
- (id)position;
@end

@interface Players : NSObject
- (id)All;
- (BOOL)TryGetCurrentController:(id *)controller;
@end

@interface GameManager : NSObject
+ (instancetype)sharedInstance;
- (id)getPlayers;
- (id)players;
@end

@interface RoomController : NSObject
+ (instancetype)instance;
+ (instancetype)sharedInstance;
- (id)getPlayers;
- (id)players;
@end

// ========== ПЛАВАЮЩАЯ КНОПКА ==========
@interface MenuButton : UIButton
@end

static NSMutableString *logText = nil;
static UIViewController *logViewController = nil;

@implementation MenuButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 50, 50)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 25;
        [self addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:pan];
        
        logText = [[NSMutableString alloc] init];
        [self addLog:@"=== Твик загружен ==="];
    }
    return self;
}

- (void)drag:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [pan translationInView:self.superview];
        self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
        [pan setTranslation:CGPointZero inView:self.superview];
    }
}

- (void)addLog:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"HH:mm:ss";
    NSString *time = [formatter stringFromDate:[NSDate date]];
    
    [logText appendFormat:@"[%@] %@\n", time, message];
    NSLog(@"[Aimbot] %@", message);
}

- (void)showMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ESP Диагностика"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 Запустить диагностику"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        [self runDiagnostics];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📱 Показать логи"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        [self showLogs];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"❌ Закрыть"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) rootVC = rootVC.presentedViewController;
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self;
        alert.popoverPresentationController.sourceRect = self.bounds;
    }
    
    [rootVC presentViewController:alert animated:YES completion:nil];
}

- (void)runDiagnostics {
    [self addLog:@"=== ЗАПУСК ДИАГНОСТИКИ ==="];
    
    // Проверяем базовые классы
    [self addLog:@"Проверка классов:"];
    [self checkClass:@"Context"];
    [self checkClass:@"Players"];
    [self checkClass:@"FirstPersonController"];
    [self checkClass:@"INetworkPlayer"];
    [self checkClass:@"Camera"];
    [self checkClass:@"GameManager"];
    [self checkClass:@"RoomController"];
    
    // Тестируем все 4 метода получения Players
    [self testMethod0]; // Context Gameplay
    [self testMethod1]; // Context Battle
    [self testMethod2]; // GameManager
    [self testMethod3]; // RoomController
    
    [self addLog:@"=== ДИАГНОСТИКА ЗАВЕРШЕНА ==="];
}

- (void)checkClass:(NSString *)className {
    Class cls = objc_getClass([className UTF8String]);
    if (cls) {
        [self addLog:@"✅ %@ найден", className];
    } else {
        [self addLog:@"❌ %@ НЕ найден", className];
    }
}

- (void)testMethod0 {
    [self addLog:@"\n--- Метод 0: Context Gameplay ---"];
    Class contextClass = objc_getClass("Context");
    if (!contextClass) { [self addLog:@"❌ Context class not found"]; return; }
    
    // Используем objc_msgSend для безопасного вызова
    Context *(*createMethod)(id, SEL, NSString *) = (Context *(*)(id, SEL, NSString *))objc_msgSend;
    Context *context = createMethod(contextClass, @selector(create:), @"Gameplay");
    
    if (!context) { [self addLog:@"❌ Failed to create Gameplay context"]; return; }
    [self addLog:@"✅ Context Gameplay создан"];
    
    Class playersClass = objc_getClass("Players");
    if (!playersClass) { [self addLog:@"❌ Players class not found"]; return; }
    
    id (*resolveMethod)(id, SEL, Class) = (id (*)(id, SEL, Class))objc_msgSend;
    id players = resolveMethod(context, @selector(resolve:), playersClass);
    
    if (!players) { [self addLog:@"❌ Failed to resolve Players"]; return; }
    [self addLog:@"✅ Players получен"];
    
    [self testPlayers:players];
}

- (void)testMethod1 {
    [self addLog:@"\n--- Метод 1: Context Battle ---"];
    Class contextClass = objc_getClass("Context");
    if (!contextClass) { [self addLog:@"❌ Context class not found"]; return; }
    
    Context *(*createMethod)(id, SEL, NSString *) = (Context *(*)(id, SEL, NSString *))objc_msgSend;
    Context *context = createMethod(contextClass, @selector(create:), @"Battle");
    
    if (!context) { [self addLog:@"❌ Failed to create Battle context"]; return; }
    [self addLog:@"✅ Context Battle создан"];
    
    Class playersClass = objc_getClass("Players");
    if (!playersClass) { [self addLog:@"❌ Players class not found"]; return; }
    
    id (*resolveMethod)(id, SEL, Class) = (id (*)(id, SEL, Class))objc_msgSend;
    id players = resolveMethod(context, @selector(resolve:), playersClass);
    
    if (!players) { [self addLog:@"❌ Failed to resolve Players"]; return; }
    [self addLog:@"✅ Players получен"];
    
    [self testPlayers:players];
}

- (void)testMethod2 {
    [self addLog:@"\n--- Метод 2: GameManager ---"];
    Class gmClass = objc_getClass("GameManager");
    if (!gmClass) { [self addLog:@"❌ GameManager class not found"]; return; }
    
    id (*sharedMethod)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id gm = sharedMethod(gmClass, @selector(sharedInstance));
    
    if (!gm) { [self addLog:@"❌ sharedInstance вернул nil"]; return; }
    [self addLog:@"✅ GameManager instance получен"];
    
    // Пробуем разные названия методов
    SEL selectors[] = {@selector(getPlayers), @selector(players), @selector(GetPlayers)};
    const char *names[] = {"getPlayers", "players", "GetPlayers"};
    
    for (int i = 0; i < 3; i++) {
        if ([gm respondsToSelector:selectors[i]]) {
            id (*getMethod)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
            id players = getMethod(gm, selectors[i]);
            if (players) {
                [self addLog:@"✅ Players получен через %s", names[i]];
                [self testPlayers:players];
                return;
            }
        }
    }
    
    [self addLog:@"❌ Не удалось получить Players из GameManager"];
}

- (void)testMethod3 {
    [self addLog:@"\n--- Метод 3: RoomController ---"];
    Class rcClass = objc_getClass("RoomController");
    if (!rcClass) { [self addLog:@"❌ RoomController class not found"]; return; }
    
    id rc = nil;
    id (*instanceMethod)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    
    if ([rcClass respondsToSelector:@selector(instance)]) {
        rc = instanceMethod(rcClass, @selector(instance));
    } else if ([rcClass respondsToSelector:@selector(sharedInstance)]) {
        rc = instanceMethod(rcClass, @selector(sharedInstance));
    }
    
    if (!rc) { [self addLog:@"❌ instance/sharedInstance вернул nil"]; return; }
    [self addLog:@"✅ RoomController instance получен"];
    
    // Пробуем разные названия методов
    SEL selectors[] = {@selector(getPlayers), @selector(players), @selector(GetPlayers)};
    const char *names[] = {"getPlayers", "players", "GetPlayers"};
    
    for (int i = 0; i < 3; i++) {
        if ([rc respondsToSelector:selectors[i]]) {
            id (*getMethod)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
            id players = getMethod(rc, selectors[i]);
            if (players) {
                [self addLog:@"✅ Players получен через %s", names[i]];
                [self testPlayers:players];
                return;
            }
        }
    }
    
    [self addLog:@"❌ Не удалось получить Players из RoomController"];
}

- (void)testPlayers:(id)players {
    // Проверяем All
    if ([players respondsToSelector:@selector(All)]) {
        NSArray *(*allMethod)(id, SEL) = (NSArray *(*)(id, SEL))objc_msgSend;
        NSArray *all = allMethod(players, @selector(All));
        
        if (all) {
            [self addLog:@"✅ players.All работает, размер: %lu", (unsigned long)all.count];
            
            // Проверяем локального игрока
            NSMethodSignature *sig = [players methodSignatureForSelector:@selector(TryGetCurrentController:)];
            if (sig) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:players];
                [inv setSelector:@selector(TryGetCurrentController:)];
                FirstPersonController *local = nil;
                [inv setArgument:&local atIndex:2];
                [inv invoke];
                
                BOOL hasLocal = NO;
                [inv getReturnValue:&hasLocal];
                
                if (hasLocal && local) {
                    [self addLog:@"✅ TryGetCurrentController работает"];
                    
                    // Проверяем камеру
                    Class cameraClass = objc_getClass("Camera");
                    Camera *(*mainMethod)(id, SEL) = (Camera *(*)(id, SEL))objc_msgSend;
                    Camera *cam = mainMethod(cameraClass, @selector(main));
                    
                    if (cam) {
                        [self addLog:@"✅ Camera.main работает"];
                    } else {
                        [self addLog:@"❌ Camera.main НЕ работает"];
                    }
                    
                    // Проверяем конвертацию координат
                    id (*rootMethod)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
                    id root = rootMethod(local, @selector(RootPoint));
                    
                    if (root) {
                        id (*posMethod)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
                        id pos = posMethod(root, @selector(position));
                        
                        if (pos) {
                            [self addLog:@"✅ local position получен"];
                        } else {
                            [self addLog:@"❌ position НЕ получен"];
                        }
                    } else {
                        [self addLog:@"❌ RootPoint НЕ получен"];
                    }
                } else {
                    [self addLog:@"❌ TryGetCurrentController вернул NO"];
                }
            } else {
                [self addLog:@"❌ TryGetCurrentController метод отсутствует"];
            }
        } else {
            [self addLog:@"❌ players.All вернул nil"];
        }
    } else {
        [self addLog:@"❌ players не отвечает на All"];
    }
}

- (void)showLogs {
    if (!logViewController) {
        logViewController = [[UIViewController alloc] init];
        logViewController.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.9];
        logViewController.view.frame = [UIScreen mainScreen].bounds;
        
        UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(20, 60, logViewController.view.frame.size.width - 40, logViewController.view.frame.size.height - 140)];
        textView.backgroundColor = [UIColor blackColor];
        textView.textColor = [UIColor greenColor];
        textView.font = [UIFont fontWithName:@"Courier" size:12];
        textView.editable = NO;
        textView.layer.cornerRadius = 10;
        textView.tag = 999;
        [logViewController.view addSubview:textView];
        
        UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        copyBtn.frame = CGRectMake(20, logViewController.view.frame.size.height - 70, 100, 40);
        [copyBtn setTitle:@"📋 Копировать" forState:UIControlStateNormal];
        [copyBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        copyBtn.backgroundColor = [UIColor darkGrayColor];
        copyBtn.layer.cornerRadius = 8;
        [copyBtn addTarget:self action:@selector(copyLogs) forControlEvents:UIControlEventTouchUpInside];
        [logViewController.view addSubview:copyBtn];
        
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(logViewController.view.frame.size.width - 120, logViewController.view.frame.size.height - 70, 100, 40);
        [closeBtn setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        closeBtn.backgroundColor = [UIColor redColor];
        closeBtn.layer.cornerRadius = 8;
        [closeBtn addTarget:self action:@selector(closeLogs) forControlEvents:UIControlEventTouchUpInside];
        [logViewController.view addSubview:closeBtn];
    }
    
    UITextView *tv = [logViewController.view viewWithTag:999];
    tv.text = logText;
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) rootVC = rootVC.presentedViewController;
    [rootVC presentViewController:logViewController animated:YES completion:nil];
}

- (void)copyLogs {
    UITextView *tv = [logViewController.view viewWithTag:999];
    [UIPasteboard generalPasteboard].string = tv.text;
    
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(50, 200, 200, 40)];
    toast.text = @"✅ Скопировано!";
    toast.backgroundColor = [UIColor blackColor];
    toast.textColor = [UIColor whiteColor];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 10;
    toast.clipsToBounds = YES;
    [logViewController.view addSubview:toast];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [toast removeFromSuperview];
    });
}

- (void)closeLogs {
    [logViewController dismissViewControllerAnimated:YES completion:nil];
}

@end

// ========== ТОЧКА ВХОДА ==========
__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
        [mainWindow addSubview:[[MenuButton alloc] init]];
        NSLog(@"[Aimbot] Загружено");
    });
}
