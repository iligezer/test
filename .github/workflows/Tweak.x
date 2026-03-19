%hook PlayerController
- (void)update {
    %orig;
    NSLog(@"[Aimbot] Working!");
}
%end
