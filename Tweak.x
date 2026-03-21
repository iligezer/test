#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>

// ===== ПРОСТОЕ ОКНО =====
static UIWindow *simpleWindow = nil;
static UITextView *logView = nil;
static NSMutableString *logText = nil;

void addLog(NSString *msg) {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendString:msg];
    [logText appendString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        logView.text = logText;
    });
}

// ===== ПОИСК =====
void findRoomController() {
    addLog(@"🔍 ПОИСК...");
    
    uintptr_t start = 0x100000000;
    uintptr_t end = 0x180000000;
    int found = 0;
    
    for (uintptr_t addr = start; addr < end && found < 20; addr += 0x10000) {
        uintptr_t ptr = 0;
        vm_size_t read;
        vm_read_overwrite(mach_task_self(), addr, 8, (vm_address_t)&ptr, &read);
        if (ptr < start || ptr > end) continue;
        
        int team = 0, id = 0;
        vm_read_overwrite(mach_task_self(), ptr + 0x34, 4, (vm_address_t)&team, &read);
        vm_read_overwrite(mach_task_self(), ptr + 0x10, 4, (vm_address_t)&id, &read);
        
        if ((team == 0 || team == 1) && id > 1000000) {
            addLog([NSString stringWithFormat:@"🎮 0x%lx ID:%d Team:%d", ptr, id, team]);
            
            // Ищем RoomController
            for (uintptr_t a = start; a < start + 0x2000000; a += 8) {
                uintptr_t p = 0;
                vm_read_overwrite(mach_task_self(), a, 8, (vm_address_t)&p, &read);
                if (p == ptr) {
                    uintptr_t arr = 0;
                    vm_read_overwrite(mach_task_self(), a + 0x140, 8, (vm_address_t)&arr, &read);
                    addLog([NSString stringWithFormat:@"✅ RC:0x%lx ARR:0x%lx", a, arr]);
                    found = 100;
                    break;
                }
            }
        }
    }
    
    addLog(@"🏁 ГОТОВО");
}

// ===== КНОПКА =====
@interface MyButton : UIButton
@end

@implementation MyButton
- (instancetype)init {
    self = [super initWithFrame:CGRectMake([UIScreen mainScreen].bounds.size.width - 70, [UIScreen mainScreen].bounds.size.height - 100, 55, 55)];
    if (self) {
        self.backgroundColor = [UIColor systemBlueColor];
        self.layer.cornerRadius = 27.5;
        [self setTitle:@"🔍" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:28];
        [self addTarget:self action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}
- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint p = [g translationInView:self.superview];
    static CGPoint last;
    if (g.state == UIGestureRecognizerStateBegan) last = self.center;
    CGPoint new = CGPointMake(last.x + p.x, last.y + p.y);
    CGFloat h = self.frame.size.width/2;
    new.x = MAX(h, MIN(self.superview.bounds.size.width - h, new.x));
    new.y = MAX(h + 50, MIN(self.superview.bounds.size.height - h - 50, new.y));
    self.center = new;
}
- (void)tap {
    if (!simpleWindow) {
        UIWindow *w = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class]) {
                for (UIWindow *win in [(UIWindowScene*)s windows]) {
                    if (win.isKeyWindow) { w = win; break; }
                }
            }
        }
        if (!w) return;
        
        simpleWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 80, w.frame.size.width - 40, 400)];
        simpleWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
        simpleWindow.layer.cornerRadius = 15;
        simpleWindow.windowLevel = UIWindowLevelAlert + 2;
        simpleWindow.hidden = NO;
        
        logView = [[UITextView alloc] initWithFrame:CGRectMake(10, 40, simpleWindow.frame.size.width - 20, 300)];
        logView.backgroundColor = [UIColor blackColor];
        logView.textColor = [UIColor greenColor];
        logView.font = [UIFont fontWithName:@"Courier" size:12];
        logView.editable = NO;
        [simpleWindow addSubview:logView];
        
        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(simpleWindow.frame.size.width/2 - 50, 350, 100, 35);
        [close setTitle:@"ЗАКРЫТЬ" forState:UIControlStateNormal];
        close.backgroundColor = [UIColor systemRedColor];
        [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        close.layer.cornerRadius = 8;
        [close addTarget:simpleWindow action:@selector(setHidden:) forControlEvents:UIControlEventTouchUpInside];
        [simpleWindow addSubview:close];
        
        [simpleWindow makeKeyAndVisible];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_global_queue(0, 0), ^{
            findRoomController();
        });
    } else {
        simpleWindow.hidden = !simpleWindow.hidden;
        if (!simpleWindow.hidden) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_global_queue(0, 0), ^{
                findRoomController();
            });
        }
    }
}
@end

// ===== ЗАПУСК =====
__attribute__((constructor))
static void init() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        MyButton *btn = [[MyButton alloc] init];
        UIWindow *w = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class]) {
                w = [(UIWindowScene*)s windows].firstObject;
                break;
            }
        }
        [w addSubview:btn];
    });
}
