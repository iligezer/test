#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Foundation/Foundation.h>

#define LOG(fmt, ...) NSLog(@"[Aimbot] " fmt, ##__VA_ARGS__)

// Глобальные переменные для окна и логирования
static UIWindow *g_floatWindow = nil;
static UIView *g_floatButton = nil;
static UITextView *g_logTextView = nil;
static BOOL g_menuVisible = NO;
static NSMutableArray *g_logs = nil;
static NSString *g_logFilePath = nil;

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
            g_logTextView.text = [NSString stringWithContentsOfFile:g_logFilePath 
                                                              encoding:NSUTF8StringEncoding 
                                                                 error:nil];
            [g_logTextView scrollRangeToVisible:NSMakeRange([g_logTextView.text length], 0)];
        });
    }
}

#pragma mark - Действия кнопок

void toggleMenu() {
    g_menuVisible = !g_menuVisible;
    LOG("Меню переключено: %d", g_menuVisible);
    writeLog([NSString stringWithFormat:@"Меню переключено: %@", g_menuVisible ? @"ВКЛ" : @"ВЫКЛ"]);
}

void showLogs() {
    writeLog(@"Открываем окно логов");
    LOG("Окно логов открыто");
}

void clearLogs() {
    writeLog(@"Логи очищены");
    [[NSFileManager defaultManager] removeItemAtPath:g_logFilePath error:nil];
    [g_logs removeAllObjects];
    LOG("Логи удалены");
}

#pragma mark - Создание UI

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
            LOG("Окно не найдено");
            return;
        }
        
        // Создаём окно для плавающей кнопки
        g_floatWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, 60, 60)];
        g_floatWindow.windowLevel = UIWindowLevelAlert + 1;
        g_floatWindow.backgroundColor = [UIColor clearColor];
        
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
        
        // Добавляем тап-распознаватель
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self 
                                                                               action:@selector(toggleMenu)];
        [g_floatButton addGestureRecognizer:tap];
        
        // Добавляем перетаскивание
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self 
                                                                               action:@selector(dragButton:)];
        [g_floatButton addGestureRecognizer:pan];
        
        // Используем блок вместо nil target!
        tap = [[UITapGestureRecognizer alloc] 
               initWithTarget:self 
               action:@selector(handleTap)];
        [g_floatButton addGestureRecognizer:tap];
        
        [g_floatWindow addSubview:g_floatButton];
        [g_floatWindow makeKeyAndVisible];
        
        // Создаём окно логов
        UIWindow *logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 300, 400)];
        logWindow.windowLevel = UIWindowLevelAlert;
        logWindow.backgroundColor = [UIColor blackColor];
        logWindow.layer.cornerRadius = 10;
        
        // Текстовое поле для логов
        g_logTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 40, 280, 350)];
        g_logTextView.backgroundColor = [UIColor darkGrayColor];
        g_logTextView.textColor = [UIColor greenColor];
        g_logTextView.font = [UIFont systemFontOfSize:10];
        g_logTextView.editable = NO;
        [logWindow addSubview:g_logTextView];
        
        // Кнопка закрытия
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(10, 10, 280, 25);
        [closeBtn setTitle:@"Закрыть" forState:UIControlStateNormal];
        closeBtn.backgroundColor = [UIColor systemRedColor];
        [closeBtn addTarget:self action:@selector(closeLogWindow) forControlEvents:UIControlEventTouchUpInside];
        [logWindow addSubview:closeBtn];
        
        LOG("Плавающая кнопка создана");
        writeLog(@"Интерфейс инициализирован");
    }
}

#pragma mark - Обработчики событий

void handleTap() {
    LOG("Кнопка нажата!");
    writeLog(@"Кнопка нажата");
    toggleMenu();
}

void dragButton(UIPanGestureRecognizer *gesture) {
    if (!gesture.view) return;
    
    CGPoint translation = [gesture translationInView:gesture.view.superview];
    gesture.view.center = CGPointMake(gesture.view.center.x + translation.x,
                                       gesture.view.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:gesture.view.superview];
}

void closeLogWindow() {
    g_logTextView.hidden = YES;
    LOG("Окно логов закрыто");
}

#pragma mark - Конструктор

__attribute__((constructor))
static void init() {
    LOG("Твик загружен!");
    
    initLogging();
    writeLog(@"✅ Aimbot твик загружен");
    
    // Ждём 3 секунды, чтобы приложение загрузилось
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), 
                   dispatch_get_main_queue(), ^{
        LOG("Создаём UI...");
        createFloatingButton();
    });
}
