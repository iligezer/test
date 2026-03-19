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

// ========== ПЛАВАЮЩАЯ КНОПКА (РЕАЛЬНО РАБОЧАЯ) ==========
@interface MenuButton : UIButton
@end

@implementation MenuButton
- (instancetype)init {
    self = [super initWithFrame:CGRectMake(20, 100, 50, 50)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 25;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowOpacity = 0.5;
        self.layer.shadowRadius = 4;
        [self addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [pan setMaximumNumberOfTouches:1];
        [pan setMinimumNumberOfTouches:1];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)drag:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [pan translationInView:self.superview];
        CGPoint center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
        
        CGFloat halfWidth = self.bounds.size.width / 2;
        CGFloat halfHeight = self.bounds.size.height / 2;
        center.x = MAX(halfWidth, MIN(center.x, self.superview.bounds.size.width - halfWidth));
        center.y = MAX(halfHeight, MIN(center.y, self.superview.bounds.size.height - halfHeight));
        
        self.center = center;
        [pan setTranslation:CGPointZero inView:self.superview];
    }
}

- (void)showMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Aimbot Menu"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // Состояние ESP
    BOOL espOn = [[NSUserDefaults standardUserDefaults] boolForKey:@"esp_enabled"];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ ESP", espOn ? @"✅" : @"❌"]
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
        BOOL newState = !espOn;
        [[NSUserDefaults standardUserDefaults] setBool:newState forKey:@"esp_enabled"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Закрыть"
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
        
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(update)];
        [link addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)update {
    BOOL espOn = [[NSUserDefaults standardUserDefaults] boolForKey:@"esp_enabled"];
    if (espOn) {
        [self setNeedsDisplay];
    }
}

- (float)distanceBetween:(id)pos1 and:(id)pos2 {
    float x1 = [[pos1 valueForKey:@"x"] floatValue];
    float y1 = [[pos1 valueForKey:@"y"] floatValue];
    float z1 = [[pos1 valueForKey:@"z"] floatValue];
    
    float x2 = [[pos2 valueForKey:@"x"] floatValue];
    float y2 = [[pos2 valueForKey:@"y"] floatValue];
    float z2 = [[pos2 valueForKey:@"z"] floatValue];
    
    float dx = x1 - x2;
    float dy = y1 - y2;
    float dz = z1 - z2;
    
    return sqrt(dx*dx + dy*dy + dz*dz);
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"esp_enabled"]) return;
    
    @autoreleasepool {
        Class contextClass = objc_getClass("Context");
        if (!contextClass) return;
        
        Context *context = [contextClass performSelector:@selector(create:) withObject:@"Gameplay"];
        if (!context) return;
        
        Class playersClass = objc_getClass("Players");
        if (!playersClass) return;
        
        Players *players = [context performSelector:@selector(resolve:) withObject:playersClass];
        if (!players) return;
        
        FirstPersonController *localPlayer = nil;
        NSMethodSignature *sig = [players methodSignatureForSelector:@selector(TryGetCurrentController:)];
        if (!sig) return;
        
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:players];
        [inv setSelector:@selector(TryGetCurrentController:)];
        [inv setArgument:&localPlayer atIndex:2];
        [inv invoke];
        
        BOOL hasLocal = NO;
        [inv getReturnValue:&hasLocal];
        if (!hasLocal || !localPlayer) return;
        
        Camera *mainCamera = [objc_getClass("Camera") performSelector:@selector(main)];
        if (!mainCamera) return;
        
        NSArray *allPlayers = [players valueForKey:@"All"];
        if (!allPlayers) return;
        
        id localRootPoint = [localPlayer valueForKey:@"RootPoint"];
        if (!localRootPoint) return;
        
        id localPos = [localRootPoint valueForKey:@"position"];
        if (!localPos) return;
        
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        
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
                
                float boxSize = MIN(MAX(300.0f / distance, 30.0f), 100.0f);
                CGRect box = CGRectMake(x - boxSize/2, y - boxSize/2 - 10, boxSize, boxSize);
                
                CGContextSetStrokeColorWithColor(ctx, [UIColor redColor].CGColor);
                CGContextSetLineWidth(ctx, 2);
                CGContextStrokeRect(ctx, box);
                
                CGRect healthBar = CGRectMake(x - boxSize/2, y - boxSize/2 - 15, boxSize * (health/100), 3);
                CGContextSetFillColorWithColor(ctx, [UIColor greenColor].CGColor);
                CGContextFillRect(ctx, healthBar);
                
                NSString *distText = [NSString stringWithFormat:@"%.0fм", distance];
                [distText drawAtPoint:CGPointMake(x - 20, y - boxSize/2 - 30) 
                        withAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12],
                                        NSForegroundColorAttributeName: [UIColor whiteColor]}];
            } @catch (NSException *e) {}
        }
    }
}
@end

// ========== ТОЧКА ВХОДА ==========
__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
        
        // Кнопка
        MenuButton *btn = [[MenuButton alloc] init];
        [mainWindow addSubview:btn];
        
        // ESP окно
        UIWindow *espWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        espWindow.windowLevel = UIWindowLevelAlert + 1;
        espWindow.backgroundColor = [UIColor clearColor];
        espWindow.userInteractionEnabled = NO;
        [espWindow addSubview:[[ESPView alloc] initWithFrame:espWindow.bounds]];
        [espWindow makeKeyAndVisible];
        
        NSLog(@"[Aimbot] Загружено");
    });
}
