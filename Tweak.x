#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ==================== ОБЪЯВЛЕНИЕ КЛАССОВ (IL2CPP) ====================

// BehaviourInject
@interface Context : NSObject
+ (instancetype)create:(NSString *)name;
- (id)resolve:(Class)type;
@end

// Основные классы игры
@class FirstPersonController;
@class INetworkPlayer;
@class QuarkRoomPlayer;
@class Camera;
@class Players;
@class Transform;
@class Vector3;

// ==================== ПРОСТОЙ ESP ВЬЮ ====================
@interface ESPView : UIView {
    NSMutableArray *_enemies;
    UIFont *_espFont;
}
@property (nonatomic, retain) NSMutableArray *enemies;
- (void)updateEnemies:(NSArray *)enemies;
@end

@implementation ESPView
@synthesize enemies = _enemies;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        _enemies = [[NSMutableArray alloc] init];
        _espFont = [UIFont boldSystemFontOfSize:14];
    }
    return self;
}

- (void)dealloc {
    [_enemies release];
    [super dealloc];
}

- (void)updateEnemies:(NSArray *)enemies {
    @synchronized(self) {
        [_enemies removeAllObjects];
        [_enemies addObjectsFromArray:enemies];
    }
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    @synchronized(self) {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        
        for (NSDictionary *enemy in _enemies) {
            NSValue *screenPosValue = [enemy objectForKey:@"screenPos"];
            if (!screenPosValue) continue;
            
            CGPoint screenPos = [screenPosValue CGPointValue];
            float distance = [[enemy objectForKey:@"distance"] floatValue];
            BOOL isBot = [[enemy objectForKey:@"isBot"] boolValue];
            float health = [[enemy objectForKey:@"health"] floatValue];
            
            // Проверяем, что позиция в пределах экрана
            if (screenPos.x < 0 || screenPos.x > self.frame.size.width || 
                screenPos.y < 0 || screenPos.y > self.frame.size.height) {
                continue;
            }
            
            // Цвет: красный для врагов, оранжевый для ботов
            UIColor *color = isBot ? [UIColor orangeColor] : [UIColor redColor];
            
            // Размер бокса зависит от расстояния
            float boxSize = 60.0f;
            if (distance > 0) {
                boxSize = MIN(MAX(300.0f / distance, 30.0f), 120.0f);
            }
            
            CGRect box = CGRectMake(screenPos.x - boxSize/2, 
                                    screenPos.y - boxSize/2 - 15, 
                                    boxSize, boxSize);
            
            // Рисуем прямоугольник
            CGContextSetStrokeColorWithColor(ctx, color.CGColor);
            CGContextSetLineWidth(ctx, 2.0f);
            CGContextStrokeRect(ctx, box);
            
            // Рисуем линию от верха бокса до низа
            CGContextSetStrokeColorWithColor(ctx, color.CGColor);
            CGContextSetLineWidth(ctx, 1.5f);
            CGContextMoveToPoint(ctx, screenPos.x, screenPos.y - boxSize/2 - 15);
            CGContextAddLineToPoint(ctx, screenPos.x, screenPos.y + boxSize/2 - 15);
            CGContextStrokePath(ctx);
            
            // Рисуем здоровье (полоска сверху)
            if (health > 0) {
                CGRect healthBar = CGRectMake(screenPos.x - boxSize/2, 
                                              screenPos.y - boxSize/2 - 25, 
                                              boxSize * (health / 100.0f), 3);
                CGContextSetFillColorWithColor(ctx, [UIColor greenColor].CGColor);
                CGContextFillRect(ctx, healthBar);
            }
            
            // Рисуем дистанцию и тип
            NSString *distanceText = [NSString stringWithFormat:@"%.1fм%@", distance, isBot ? @" (бот)" : @""];
            NSDictionary *attrs = @{
                NSFontAttributeName: _espFont,
                NSForegroundColorAttributeName: [UIColor whiteColor]
            };
            [distanceText drawAtPoint:CGPointMake(screenPos.x - 40, screenPos.y - boxSize/2 - 40) 
                        withAttributes:attrs];
        }
    }
}

@end

// ==================== ОСНОВНОЙ ТВИК ====================
@interface AimbotTweak : NSObject
@property (nonatomic, retain) UIWindow *espWindow;
@property (nonatomic, retain) ESPView *espView;
@property (nonatomic, assign) BOOL espEnabled;
@property (nonatomic, retain) NSTimer *updateTimer;
@end

@implementation AimbotTweak

+ (instancetype)sharedInstance {
    static AimbotTweak *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AimbotTweak alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        _espEnabled = YES;
    }
    return self;
}

- (void)setupESP {
    if (_espWindow) return;
    
    _espWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _espWindow.windowLevel = UIWindowLevelAlert + 1;
    _espWindow.backgroundColor = [UIColor clearColor];
    _espWindow.userInteractionEnabled = NO;
    
    _espView = [[ESPView alloc] initWithFrame:_espWindow.bounds];
    _espView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_espWindow addSubview:_espView];
    
    [_espWindow makeKeyAndVisible];
    
    NSLog(@"[Aimbot] ESP window created");
}

- (void)startESP {
    [self setupESP];
    
    // Запускаем таймер обновления 30 FPS
    _updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.033
                                                     target:self
                                                   selector:@selector(updateESP)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (void)updateESP {
    if (!_espEnabled || !_espView) return;
    
    @autoreleasepool {
        // Получаем контекст Gameplay
        Context *context = [Context create:@"Gameplay"];
        if (!context) return;
        
        // Получаем Players
        Players *players = [context resolve:objc_getClass("Players")];
        if (!players) return;
        
        // Получаем локального игрока
        FirstPersonController *localPlayer = nil;
        BOOL hasLocal = [players performSelector:@selector(TryGetCurrentController:) withObject:&localPlayer];
        if (!hasLocal || !localPlayer) return;
        
        // Получаем камеру
        Camera *mainCamera = [Camera main];
        if (!mainCamera) return;
        
        // Получаем список всех игроков
        NSArray *allPlayers = [players valueForKey:@"All"]; // public readonly List<INetworkPlayer> All;
        if (!allPlayers) return;
        
        NSMutableArray *enemiesData = [NSMutableArray array];
        
        for (id player in allPlayers) {
            // Проверяем через IsMine
            BOOL isMine = [[player performSelector:@selector(IsMine)] boolValue];
            if (isMine) continue;
            
            // Проверяем жив ли
            BOOL isDead = [[player performSelector:@selector(IsDead)] boolValue];
            if (isDead) continue;
            
            // Проверяем, враг ли
            BOOL isAlly = [[player performSelector:@selector(IsAllyOfLocalPlayer)] boolValue];
            if (isAlly) continue; // пропускаем союзников
            
            // Получаем позицию
            Transform *transform = [player performSelector:@selector(Transform)];
            if (!transform) continue;
            
            Vector3 worldPos = [transform performSelector:@selector(position)];
            
            // Конвертируем в экранные координаты
            Vector3 screenPos = [mainCamera performSelector:@selector(WorldToScreenPoint:) withObject:worldPos];
            
            // Проверяем, что игрок перед камерой
            float z = [screenPos performSelector:@selector(z)];
            if (z <= 0) continue;
            
            float x = [screenPos performSelector:@selector(x)];
            float y = [screenPos performSelector:@selector(y)];
            
            // Конвертируем в CGPoint (UIKit Y перевёрнута)
            CGPoint point = CGPointMake(x, [UIScreen mainScreen].bounds.size.height - y);
            
            // Вычисляем дистанцию
            Transform *localTransform = [localPlayer performSelector:@selector(RootPoint)];
            Vector3 localPos = [localTransform performSelector:@selector(position)];
            
            float dx = [localPos performSelector:@selector(x)] - [worldPos performSelector:@selector(x)];
            float dy = [localPos performSelector:@selector(y)] - [worldPos performSelector:@selector(y)];
            float dz = [localPos performSelector:@selector(z)] - [worldPos performSelector:@selector(z)];
            float distance = sqrt(dx*dx + dy*dy + dz*dz);
            
            // Получаем здоровье
            float health = [[player performSelector:@selector(GetCurrentHealth)] floatValue];
            
            // Проверяем, бот ли (через QuarkPlayer)
            BOOL isBot = NO;
            id quarkPlayer = [player performSelector:@selector(QuarkPlayer)];
            if (quarkPlayer) {
                isBot = [[quarkPlayer performSelector:@selector(IsBot)] boolValue];
            }
            
            [enemiesData addObject:@{
                @"screenPos": [NSValue valueWithCGPoint:point],
                @"distance": @(distance),
                @"isBot": @(isBot),
                @"health": @(health)
            }];
        }
        
        [_espView updateEnemies:enemiesData];
    }
}

@end

// ==================== ТОЧКА ВХОДА ====================
__attribute__((constructor))
static void init() {
    NSLog(@"[Aimbot] Загружается...");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSLog(@"[Aimbot] Инициализация...");
        
        AimbotTweak *tweak = [AimbotTweak sharedInstance];
        [tweak startESP];
        
        NSLog(@"[Aimbot] ESP запущен");
    });
}
