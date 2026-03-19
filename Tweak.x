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
- (id)getPlayers;
- (id)players;
@end

// ========== ПЛАВАЮЩАЯ КНОПКА ==========
@interface MenuButton : UIButton
@end

static int currentMethod = 0; // 0-3 разные методы
static BOOL espEnabled = YES;

@implementation MenuButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 50, 50)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 25;
        [self addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:pan];
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

- (void)showMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ESP Menu"
                                                                   message:[NSString stringWithFormat:@"Текущий метод: %d", currentMethod]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Вкл/Выкл ESP
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ ESP", espEnabled ? @"✅" : @"❌"]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        espEnabled = !espEnabled;
    }]];
    
    // Метод 0: Context @"Gameplay"
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ Метод 0: Context Gameplay", currentMethod == 0 ? @"▶️" : @""]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        currentMethod = 0;
        [self showToast:@"Выбран метод 0"];
    }]];
    
    // Метод 1: Context @"Battle"
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ Метод 1: Context Battle", currentMethod == 1 ? @"▶️" : @""]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        currentMethod = 1;
        [self showToast:@"Выбран метод 1"];
    }]];
    
    // Метод 2: GameManager sharedInstance
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ Метод 2: GameManager", currentMethod == 2 ? @"▶️" : @""]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        currentMethod = 2;
        [self showToast:@"Выбран метод 2"];
    }]];
    
    // Метод 3: RoomController instance
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ Метод 3: RoomController", currentMethod == 3 ? @"▶️" : @""]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        currentMethod = 3;
        [self showToast:@"Выбран метод 3"];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Закрыть" style:UIAlertActionStyleCancel handler:nil]];
    
    UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (rootVC.presentedViewController) rootVC = rootVC.presentedViewController;
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self;
        alert.popoverPresentationController.sourceRect = self.bounds;
    }
    
    [rootVC presentViewController:alert animated:YES completion:nil];
}

- (void)showToast:(NSString *)msg {
    UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(50, 200, 200, 40)];
    toast.text = msg;
    toast.backgroundColor = [UIColor blackColor];
    toast.textColor = [UIColor whiteColor];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 10;
    toast.clipsToBounds = YES;
    [[UIApplication sharedApplication].keyWindow addSubview:toast];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [toast removeFromSuperview];
    });
}
@end

// ========== ESP ВЬЮ ==========
@interface ESPView : UIView
@end

@implementation ESPView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(redraw)];
        [link addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)redraw {
    if (espEnabled) [self setNeedsDisplay];
}

- (float)distanceBetween:(id)pos1 and:(id)pos2 {
    float x1 = [[pos1 valueForKey:@"x"] floatValue];
    float y1 = [[pos1 valueForKey:@"y"] floatValue];
    float z1 = [[pos1 valueForKey:@"z"] floatValue];
    float x2 = [[pos2 valueForKey:@"x"] floatValue];
    float y2 = [[pos2 valueForKey:@"y"] floatValue];
    float z2 = [[pos2 valueForKey:@"z"] floatValue];
    return sqrt(pow(x1-x2,2) + pow(y1-y2,2) + pow(z1-z2,2));
}

- (id)getPlayersWithMethod:(int)method {
    switch(method) {
        case 0: {
            // Context Gameplay
            Class contextClass = objc_getClass("Context");
            if (!contextClass) return nil;
            Context *context = [contextClass performSelector:@selector(create:) withObject:@"Gameplay"];
            if (!context) return nil;
            Class playersClass = objc_getClass("Players");
            return [context performSelector:@selector(resolve:) withObject:playersClass];
        }
        case 1: {
            // Context Battle
            Class contextClass = objc_getClass("Context");
            if (!contextClass) return nil;
            Context *context = [contextClass performSelector:@selector(create:) withObject:@"Battle"];
            if (!context) return nil;
            Class playersClass = objc_getClass("Players");
            return [context performSelector:@selector(resolve:) withObject:playersClass];
        }
        case 2: {
            // GameManager
            Class gmClass = objc_getClass("GameManager");
            if (!gmClass) return nil;
            id gm = [gmClass performSelector:@selector(sharedInstance)];
            if (!gm) return nil;
            id players = [gm performSelector:@selector(getPlayers)];
            if (!players) players = [gm performSelector:@selector(players)];
            return players;
        }
        case 3: {
            // RoomController
            Class rcClass = objc_getClass("RoomController");
            if (!rcClass) return nil;
            id rc = [rcClass performSelector:@selector(instance)];
            if (!rc) rc = [rcClass performSelector:@selector(sharedInstance)];
            if (!rc) return nil;
            id players = [rc performSelector:@selector(getPlayers)];
            if (!players) players = [rc performSelector:@selector(players)];
            return players;
        }
        default:
            return nil;
    }
}

- (FirstPersonController *)getLocalPlayer:(id)players {
    FirstPersonController *local = nil;
    NSMethodSignature *sig = [players methodSignatureForSelector:@selector(TryGetCurrentController:)];
    if (!sig) return nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:players];
    [inv setSelector:@selector(TryGetCurrentController:)];
    [inv setArgument:&local atIndex:2];
    [inv invoke];
    BOOL hasLocal = NO;
    [inv getReturnValue:&hasLocal];
    return hasLocal ? local : nil;
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    if (!espEnabled) return;
    
    @autoreleasepool {
        id players = [self getPlayersWithMethod:currentMethod];
        if (!players) return;
        
        FirstPersonController *localPlayer = [self getLocalPlayer:players];
        if (!localPlayer) return;
        
        Camera *mainCamera = [objc_getClass("Camera") performSelector:@selector(main)];
        if (!mainCamera) return;
        
        NSArray *allPlayers = [players valueForKey:@"All"];
        if (!allPlayers) return;
        
        id localRoot = [localPlayer valueForKey:@"RootPoint"];
        if (!localRoot) return;
        id localPos = [localRoot valueForKey:@"position"];
        if (!localPos) return;
        
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        int count = 0;
        
        for (id player in allPlayers) {
            @try {
                if ([[player valueForKey:@"IsMine"] boolValue]) continue;
                if ([[player valueForKey:@"IsDead"] boolValue]) continue;
                if ([[player valueForKey:@"IsAllyOfLocalPlayer"] boolValue]) continue;
                
                id transform = [player valueForKey:@"Transform"];
                if (!transform) continue;
                id worldPos = [transform valueForKey:@"position"];
                if (!worldPos) continue;
                
                id screenPos = [mainCamera performSelector:@selector(WorldToScreenPoint:) withObject:worldPos];
                if (!screenPos) continue;
                
                float z = [[screenPos valueForKey:@"z"] floatValue];
                if (z <= 0) continue;
                
                float x = [[screenPos valueForKey:@"x"] floatValue];
                float y = [[screenPos valueForKey:@"y"] floatValue];
                y = [UIScreen mainScreen].bounds.size.height - y;
                
                float distance = [self distanceBetween:localPos and:worldPos];
                float health = [[player valueForKey:@"GetCurrentHealth"] floatValue];
                float boxSize = MIN(MAX(300.0/distance, 30), 100);
                
                CGRect box = CGRectMake(x-boxSize/2, y-boxSize/2-10, boxSize, boxSize);
                CGContextSetStrokeColorWithColor(ctx, [UIColor redColor].CGColor);
                CGContextSetLineWidth(ctx, 2);
                CGContextStrokeRect(ctx, box);
                
                CGRect healthBar = CGRectMake(x-boxSize/2, y-boxSize/2-15, boxSize*(health/100), 3);
                CGContextSetFillColorWithColor(ctx, [UIColor greenColor].CGColor);
                CGContextFillRect(ctx, healthBar);
                
                NSString *distText = [NSString stringWithFormat:@"%.0fм", distance];
                [distText drawAtPoint:CGPointMake(x-20, y-boxSize/2-30)
                        withAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12],
                                        NSForegroundColorAttributeName: [UIColor whiteColor]}];
                count++;
            } @catch (NSException *e) {}
        }
        
        if (count > 0) {
            static int lastCount = 0;
            if (count != lastCount) {
                NSLog(@"[ESP] Найдено врагов: %d (метод %d)", count, currentMethod);
                lastCount = count;
            }
        }
    }
}
@end

// ========== ТОЧКА ВХОДА ==========
__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
        [mainWindow addSubview:[[MenuButton alloc] init]];
        
        UIWindow *espWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        espWindow.windowLevel = UIWindowLevelAlert + 1;
        espWindow.backgroundColor = [UIColor clearColor];
        espWindow.userInteractionEnabled = NO;
        [espWindow addSubview:[[ESPView alloc] initWithFrame:espWindow.bounds]];
        [espWindow makeKeyAndVisible];
        
        NSLog(@"[Aimbot] Загружено");
    });
}
