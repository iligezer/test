#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>

// ============================================
// НАСТРОЙКИ
// ============================================
#define LOG_FILE_PATH @"/var/mobile/Documents/modern/aimbot_log.txt"

// ============================================
// ЛОГИРОВАНИЕ (проверено)
// ============================================
void writeLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[Aimbot] %@", message);
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dirPath = [LOG_FILE_PATH stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dirPath]) {
        [fm createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:LOG_FILE_PATH];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[logEntry dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [logEntry writeToFile:LOG_FILE_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

// ============================================
// СКАНИРОВАНИЕ КЛАССОВ
// ============================================
void scanClasses() {
    writeLog(@"\n=== СКАНИРОВАНИЕ КЛАССОВ ===");
    
    NSArray *classNames = @[
        @"GameManager", @"PlayerManager", @"EnemyManager",
        @"PlayerController", @"EnemyController", @"WeaponController",
        @"CameraController", @"UnityEngine_GameObject", @"UnityEngine_Transform"
    ];
    
    int found = 0;
    for (NSString *name in classNames) {
        Class cls = objc_getClass([name UTF8String]);
        if (cls) {
            writeLog([NSString stringWithFormat:@"✅ %@", name]);
            found++;
        }
    }
    
    writeLog([NSString stringWithFormat:@"📊 Найдено: %d из %lu", found, (unsigned long)classNames.count]);
}

// ============================================
// ПЛАВАЮЩАЯ КНОПКА (как в H5GG)
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
        self.layer.borderWidth = 2;
        self.layer.borderColor = [UIColor whiteColor].CGColor;
        self.userInteractionEnabled = YES;
        
        // Добавляем обработчик касания (НЕ через addTarget)
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
        
        // Добавляем перетаскивание
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)handleTap {
    writeLog(@"🔵 Кнопка нажата");
    if (self.actionBlock) {
        self.actionBlock(); // вызываем блок
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block; // просто сохраняем блок
}

@end

// ============================================
// ПРОЗРАЧНОЕ ОКНО (критически важно)
// ============================================
@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *floatButton;
@end

@implementation PassthroughWindow

// Этот метод решает, кто получит касание
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    
    // Если нажали на кнопку или её сабвью — пусть кнопка обрабатывает
    if (self.floatButton && (hitView == self.floatButton || [self.floatButton isDescendantOfView:hitView])) {
        return hitView;
    }
    
    // ВСЁ ОСТАЛЬНОЕ — возвращаем nil,
    // это значит, что касание пойдёт в окна ниже (в игру)
    return nil;
}

@end

// ============================================
// ОСНОВНОЙ КЛАСС
// ============================================
@interface AimbotUI : NSObject
@property (nonatomic, strong) PassthroughWindow *window;
@property (nonatomic, strong) FloatButton *floatButton;
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
    writeLog(@"Создание интерфейса...");
    
    // 1. Создаём прозрачное окно на весь экран
    self.window = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelAlert + 1; // выше игры, но ниже алертов
    self.window.backgroundColor = [UIColor clearColor];
    self.window.hidden = NO;
    
    // 2. Создаём кнопку
    self.floatButton = [[FloatButton alloc] init];
    
    // 3. Связываем кнопку с окном (чтобы hitTest мог её найти)
    self.window.floatButton = self.floatButton;
    
    // 4. Добавляем кнопку в окно
    [self.window addSubview:self.floatButton];
    
    // 5. Устанавливаем действие на кнопку (БЕЗ weakSelf, так как блок не держит self)
    __weak typeof(self) weakSelf = self;
    [self.floatButton setAction:^{
        // Здесь вызываем сканирование
        writeLog(@"\n🔍 Запуск сканирования по нажатию");
        scanClasses();
        writeLog(@"✅ Сканирование завершено");
    }];
    
    writeLog(@"✅ Интерфейс создан. Нажми синюю кнопку для сканирования.");
}

@end

// ============================================
// КОНСТРУКТОР (запускается при загрузке)
// ============================================
static AimbotUI *g_ui = nil;

__attribute__((constructor))
static void init() {
    writeLog(@"\n=== AIMBOT ЗАГРУЖЕН ===");
    
    // Ждём 3 секунды, чтобы игра полностью загрузилась
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_ui = [[AimbotUI alloc] init];
    });
}
