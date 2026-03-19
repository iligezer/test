// ========== ESP VIEW ==========
@interface ESPView : UIView
- (Vector3)worldToScreen:(Vector3)worldPos camera:(void*)camera;
@end

@implementation ESPView

- (Vector3)worldToScreen:(Vector3)worldPos camera:(void*)camera {
    Vector3 screen = {0, 0, 0};
    if (Camera_WorldToScreen && camera) {
        void *result = Camera_WorldToScreen(camera, &worldPos);
        if (result) {
            float *screenPos = (float*)result;
            screen.x = screenPos[0];
            screen.y = screenPos[1];
            screen.z = screenPos[2];
        }
    }
    return screen;
}

- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    
    if (!espEnabled || !foundPlayers.count) return;
    if (!Camera_main || !Camera_WorldToScreen) return;
    
    void *cam = Camera_main();
    if (!cam) return;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    // Находим своего игрока
    PlayerData *localPlayer = nil;
    for (PlayerData *p in foundPlayers) {
        if ([p.name isEqualToString:myNickname]) {
            localPlayer = p;
            break;
        }
    }
    
    for (PlayerData *player in foundPlayers) {
        if ([player.name isEqualToString:myNickname]) continue;
        
        Vector3 worldPos = {player.x, player.y, player.z};
        Vector3 screenPos = [self worldToScreen:worldPos camera:cam];
        
        if (screenPos.z <= 0) continue;
        
        float screenX = screenPos.x * rect.size.width;
        float screenY = screenPos.y * rect.size.height;
        
        // Рисуем точку
        CGContextSetFillColorWithColor(ctx, [UIColor redColor].CGColor);
        CGContextFillEllipseInRect(ctx, CGRectMake(screenX - 5, screenY - 5, 10, 10));
        
        float yOffset = 15;
        
        if (showNames && player.name.length > 0) {
            NSString *displayName = player.name;
            if (showDistance && localPlayer) {
                float dist = sqrt(pow(player.x - localPlayer.x, 2) + 
                                  pow(player.y - localPlayer.y, 2) + 
                                  pow(player.z - localPlayer.z, 2));
                displayName = [NSString stringWithFormat:@"%@ [%.1fm]", player.name, dist];
            }
            
            [displayName drawAtPoint:CGPointMake(screenX - 20, screenY - yOffset) 
                      withAttributes:@{
                NSFontAttributeName: [UIFont boldSystemFontOfSize:12],
                NSForegroundColorAttributeName: [UIColor whiteColor],
                NSStrokeColorAttributeName: [UIColor blackColor],
                NSStrokeWidthAttributeName: @-2
            }];
            yOffset += 15;
        }
        
        if (showHealth) {
            NSString *healthText = [NSString stringWithFormat:@"HP: %.0f", player.health];
            [healthText drawAtPoint:CGPointMake(screenX - 20, screenY - yOffset) 
                      withAttributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:10],
                NSForegroundColorAttributeName: [UIColor greenColor],
                NSStrokeColorAttributeName: [UIColor blackColor],
                NSStrokeWidthAttributeName: @-2
            }];
        }
    }
}
@end
