#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Путь для сохранения логов
#define LOG_FILE_PATH @"/var/mobile/Documents/modern/aimbot_log.txt"

// Функция для записи в лог (и в консоль, и в файл)
void writeLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[Aimbot] %@", message);
    
    // Добавляем timestamp
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    // Сохраняем в файл
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *dirPath = [LOG_FILE_PATH stringByDeletingLastPathComponent];
    
    // Создаем папку, если её нет
    if (![fileManager fileExistsAtPath:dirPath]) {
        [fileManager createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    // Добавляем запись в конец файла
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:LOG_FILE_PATH];
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[logEntry dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    } else {
        [logEntry writeToFile:LOG_FILE_PATH atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

// Плавающая кнопка
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
        
        // Тап для обработки нажатия
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        [self addGestureRecognizer:tap];
        
        // Перетаскивание
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)handleTap {
    writeLog(@"Button tapped");
    if (self.actionBlock) {
        self.actionBlock();
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.superview];
    self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.superview];
}

- (void)setAction:(void (^)(void))block {
    self.actionBlock = block;
}

@end

// Прозрачное окно, пропускающее нажатия в игру
@interface PassthroughWindow : UIWindow
@property (nonatomic, weak) FloatButton *floatButton;
@end

@implementation PassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    
    // Если нажали на кнопку — передаем ей
    if (self.floatButton && (hitView == self.floatButton || [self.floatButton isDescendantOfView:hitView])) {
        return hitView;
    }
    
    // Иначе — пропускаем в игру
    return nil;
}

@end

// Основной класс
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
    writeLog(@"Setting up UI");
    
    // Создаем прозрачное окно
    self.window = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelAlert + 1;
    self.window.backgroundColor = [UIColor clearColor];
    self.window.hidden = NO;
    
    // Создаем кнопку
    self.floatButton = [[FloatButton alloc] init];
    self.window.floatButton = self.floatButton;
    [self.window addSubview:self.floatButton];
    
    // Действие при нажатии — сразу запускаем анализ
    __weak typeof(self) weakSelf = self;
    [self.floatButton setAction:^{
        [weakSelf performAnalysis];
    }];
    
    writeLog(@"UI setup complete");
}

- (void)performAnalysis {
    writeLog(@"=== НАЧАЛО АНАЛИЗА ===");
    
    // Список классов для поиска
    NSArray *classesToScan = @[
        @"GameManager",
        @"PlayerController",
        @"PlayerManager",
        @"EnemyController",
        @"WeaponController",
        @"CameraController"
    ];
    
    int found = 0;
    for (NSString *className in classesToScan) {
        Class cls = objc_getClass([className UTF8String]);
        if (cls) {
            writeLog([NSString stringWithFormat:@"✅ Найден класс: %@", className]);
            found++;
        } else {
            writeLog([NSString stringWithFormat:@"❌ Не найден: %@", className]);
        }
    }
    
    writeLog([NSString stringWithFormat:@"📊 Итого найдено классов: %d из %lu", found, (unsigned long)classesToScan.count]);
    writeLog(@"=== ФАЙЛ СОХРАНЕН ===");
}

@end

// Конструктор
static AimbotUI *g_ui = nil;

__attribute__((constructor))
static void init() {
    writeLog(@"=== AIMBOT TWEAK ЗАГРУЖЕН ===");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_ui = [[AimbotUI alloc] init];
    });
}
