#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Foundation/Foundation.h>

#define LOG(fmt, ...) NSLog(@"[Aimbot] " fmt, ##__VA_ARGS__)

// Глобальные переменные для окна и логирования
static UIWindow *g_floatWindow = nil;
static UIView *g_floatButton = nil;
static UITextView *g_logTextView = nil;
static UIWindow *g_logWindow = nil;
static BOOL g_menuVisible = NO;
static NSMutableArray *g_logs = nil;
static NSString *g_logFilePath = nil;
static id g_handler = nil; // Глобальный обработчик

#pragma mark - Вспомогательный класс для обработки событий

@interface FloatButtonHandler : NSObject
@end

@implementation FloatButtonHandler

- (void)handleTap {
    g_menuVisible = !g_menuVisible;
    LOG("Меню переключено: %d", g_menuVisible);
    
    NSString *logMsg = [NSString stringWithFormat:@"Меню переключено: %@", 
                        g_menuVisible ? @"ВКЛ" : @"ВЫКЛ"];
    writeLog(logMsg);
    
    if (g_logWindow) {
        dispatch_async(dispatch_get_main_queue(), ^{
            g_logWindow.hidden = !g_menuVisible;
        });
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if (!gesture.view || !gesture.view.superview) return;
    
    CGPoint translation = [gesture translationInView:gesture.view.superview];
    gesture.view.center = CGPointMake(gesture.view.center.x + translation.x,
                                       gesture.view.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:gesture.view.superview];
}

- (void)handleClose {
    g_menuVisible = NO;
    if (g_logWindow) {
        dispatch_async(dispatch_get_main_queue(), ^{
            g_logWindow.hidden = YES;
        });
    }
    LOG("Окно логов закрыто");
    writeLog(@"Окно логов закрыто");
}

@end

#pragma mark - Логирование

void initLogging() {
    // Создаём путь для логов: /var/mobile/Documents/modern/logs.txt
    NSString *documentsPath = @"/var/mobile/Documents";
    NSString *modernPath = [documentsPath stringByAppendingPathComponent:@"modern"];
    
    // Создаём директорию, если её нет
    [[NSFileManager defaultManager] createDirectoryAtPath:modernPath 
                                  withIntermediateDirectories:YES 
                                                   attributes:nil 
                                                        error:nil];
    
    g_logFilePath = [modernPath stringByAppendingPathComponent:@"logs.txt"];
    g_logs = [[NSMutableArray alloc] init];
    
    LOG("Логирование инициализировано: %@", g_logFilePath);
}

void writeLog(NSString *message) {
    if (!g_logFilePath) return;
    
    // Добавляем в массив
    NSString *timestamp = [[NSDate date] description];
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    [g_logs addObject:logLine];
    
    // Записываем в файл
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:g_logFilePath];
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    } else {
        // Если файла нет, создаём его
        [logLine writeToFile:g_logFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    
    // Обновляем текстовое поле если оно видимо
    if (g_logTextView && !g_logTextView.hidden) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *fullLog = [NSString stringWithContentsOfFile:g_logFilePath 
                                                           encoding:NSUTF8StringEncoding 
                                                              error:nil];
            g_logTextView.text = fullLog;
            if ([fullLog length] > 0) {
                [g_logTextView scrollRangeToVisible:NSMakeRange([fullLog length] - 1, 1)];
            }
        });
    }
}

#pragma mark - Создание UI

void createFloatingButton() {
    @autoreleasepool {
        // Получаем активное окно
        UIWindow *keyWindow = nil;
        if (@available(iOS 13, *)) {
            NSArray<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes.allObjects;
            for (UIScene *scene in scenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    keyWindow = windowScene.windows.firstObject;
                    break;
                }
            }
        } else {
            keyWindow = UIApplication.sharedApplication.keyWindow;
        }
        
        if (!keyWindow) {
            LOG("Окно не найдено");
            return;
        }
        
        // Создаём окно для плавающей кнопки
        g_floatWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, 60, 60)];
        g_floatWindow.windowLevel = UIWindowLevelAlert + 1;
        g_floatWindow.backgroundColor = [UIColor clearColor];
        g_floatWindow.userInteractionEnabled = YES;
        
        // Создаём плавающую кнопку
        g_floatButton = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 60, 60)];
        g_floatButton.backgroundColor = [UIColor systemBlueColor];
        g_floatButton.layer.cornerRadius = 30;
        g_floatButton.layer.borderWidth = 2;
        g_floatButton.layer.borderColor = [UIColor whiteColor].CGColor;
        g_floatButton.userInteractionEnabled = YES;
        
        // Добавляем текст
        UILabel *label = [[UILabel alloc] initWithFrame:g_floatButton.bounds];
        label.text = @"🎯";
        label.font = [UIFont systemFontOfSize:28];
        label.textAlignment = NSTextAlignmentCenter;
        label.userInteractionEnabled = NO;
        [g_floatButton addSubview:label];
        
        // Создаём глобальный обработчик
        g_handler = [[FloatButtonHandler alloc] init];
        
        // Добавляем тап-распознаватель
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] 
                                       initWithTarget:g_handler 
                                       action:@selector(handleTap)];
        [g_floatButton addGestureRecognizer:tap];
        
        // Добавляем перетаскивание
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] 
                                       initWithTarget:g_handler 
                                       action:@selector(handlePan:)];
        [g_floatButton addGestureRecognizer:pan];
        
        [g_floatWindow addSubview:g_floatButton];
        [g_floatWindow makeKeyAndVisible];
        
        // Создаём окно логов
        g_logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(30, 200, 300, 400)];
        g_logWindow.windowLevel = UIWindowLevelAlert;
        g_logWindow.backgroundColor = [UIColor blackColor];
        g_logWindow.layer.cornerRadius = 10;
        g_logWindow.hidden = YES;
        
        // Контейнер для содержимого
        UIView *container = [[UIView alloc] initWithFrame:g_logWindow.bounds];
        container.backgroundColor = [UIColor blackColor];
        container.layer.cornerRadius = 10;
        [g_logWindow addSubview:container];
        
        // Заголовок
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 10, 280, 25)];
        titleLabel.text = @"📋 Логи Aimbot";
        titleLabel.textColor = [UIColor greenColor];
        titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [container addSubview:titleLabel];
        
        // Текстовое поле для логов
        g_logTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 40, 280, 320)];
        g_logTextView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.8];
        g_logTextView.textColor = [UIColor greenColor];
        g_logTextView.font = [UIFont systemFontOfSize:9];
        g_logTextView.editable = NO;
        g_logTextView.scrollEnabled = YES;
        [container addSubview:g_logTextView];
        
        // Кнопка закрытия
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(10, 365, 280, 25);
        [closeBtn setTitle:@"❌ Закрыть" forState:UIControlStateNormal];
        closeBtn.backgroundColor = [UIColor systemRedColor];
        closeBtn.tintColor = [UIColor whiteColor];
        
        // Добавляем действие кнопке
        [closeBtn addTarget:g_handler action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
        
        [container addSubview:closeBtn];
        
        LOG("Плавающая кнопка создана");
        writeLog(@"✅ Интерфейс инициализирован");
    }
}

#pragma mark - Конструктор

__attribute__((constructor))
static void init() {
    LOG("Твик загружен!");
    
    initLogging();
    writeLog(@"✅ Aimbot твик загружен");
    
    // Ждём 3 секунды, чтоб�� приложение загрузилось
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), 
                   dispatch_get_main_queue(), ^{
        LOG("Создаём UI...");
        createFloatingButton();
    });
}
