// ===== ПРОВЕРКА КАНДИДАТОВ С АВТОПОИСКОМ СЛЕДУЮЩЕГО УКАЗАТЕЛЯ =====
void checkCandidates() {
    if (g_candidates.count == 0) {
        addLog(@"⚠️ Нет кандидатов. Сначала нажмите ОТСЕЯТЬ");
        return;
    }
    
    addLog(@"\n🔍 ПРОВЕРКА (ПОСЛЕ ДВИЖЕНИЯ)");
    addLog(@"=================================");
    
    int changedCount = 0;
    
    for (int i = 0; i < g_candidates.count; i++) {
        NSDictionary *c = g_candidates[i];
        uintptr_t coordAddr = [c[@"coordAddr"] unsignedLongLongValue];
        float oldX = [c[@"x"] floatValue];
        float oldY = [c[@"y"] floatValue];
        float oldZ = [c[@"z"] floatValue];
        
        float newX = safeReadFloat(coordAddr);
        float newY = safeReadFloat(coordAddr + 4);
        float newZ = safeReadFloat(coordAddr + 8);
        
        addLogF(@"\n📍 КАНДИДАТ %d:", i+1);
        addLog([c[@"path"] description]);
        addLogF(@"   Было: X=%.2f Y=%.2f Z=%.2f", oldX, oldY, oldZ);
        addLogF(@"   Стало: X=%.2f Y=%.2f Z=%.2f", newX, newY, newZ);
        
        if (fabs(newX - oldX) > 0.1 || fabs(newY - oldY) > 0.1 || fabs(newZ - oldZ) > 0.1) {
            addLog(@"   ✅ ИЗМЕНИЛИСЬ! Это координаты игрока.");
            changedCount++;
            addLogF(@"   🎯 Transform: 0x%lx", [c[@"transform"] unsignedLongLongValue]);
            addLogF(@"   🎯 Координаты: X=%.2f Y=%.2f Z=%.2f", newX, newY, newZ);
        } else {
            addLog(@"   ⚠️ НЕ ИЗМЕНИЛИСЬ. Ищем следующий указатель...");
            
            // Извлекаем последний адрес из пути
            NSString *path = c[@"path"];
            NSArray *parts = [path componentsSeparatedByString:@" → "];
            if (parts.count >= 2) {
                NSString *lastPart = parts.lastObject;
                NSRange range = [lastPart rangeOfString:@"0x[0-9a-fA-F]+" options:NSRegularExpressionSearch];
                if (range.location != NSNotFound) {
                    NSString *addrStr = [lastPart substringWithRange:range];
                    unsigned long long addr = strtoull([addrStr UTF8String], NULL, 16);
                    addLogF(@"   🔍 Ищем указатели вокруг 0x%llx...", addr);
                    
                    // Ищем следующий указатель
                    BOOL found = NO;
                    for (int offset = 0x20; offset <= 0x100 && !found; offset += 8) {
                        uintptr_t nextPtr = safeReadPtr(addr + offset);
                        if (nextPtr != 0 && nextPtr > 0x100000000 && nextPtr < 0x200000000) {
                            float nx = safeReadFloat(nextPtr + 0x20);
                            float ny = safeReadFloat(nextPtr + 0x24);
                            float nz = safeReadFloat(nextPtr + 0x28);
                            if (isValidPosition(nx, ny, nz)) {
                                addLogF(@"      ✅ Найден Transform: 0x%lx", nextPtr);
                                addLogF(@"      📍 Координаты: X=%.2f Y=%.2f Z=%.2f", nx, ny, nz);
                                found = YES;
                            }
                        }
                    }
                    if (!found) {
                        addLog(@"      ❌ Следующий указатель не найден");
                    }
                }
            }
        }
    }
    
    addLogF(@"\n✅ Найдено динамических координат: %d", changedCount);
}
