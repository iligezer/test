// СМЕЩЕНИЯ (ЗАПОЛНИ ИЗ IGG)
#define OFFSET_Y         0x54   // ТЫ ЭТО ЗНАЕШЬ!
#define OFFSET_HEALTH    0x28   // ТЫ ЭТО ЗНАЕШЬ!
#define OFFSET_ID        0x08   // ТЫ ЭТО ЗНАЕШЬ!
#define OFFSET_X         0x50   // УТОЧНИ
#define OFFSET_Z         0x58   // УТОЧНИ

+ (void)findPlayers {
    players = [NSMutableArray array];
    
    // Проходим по регионам памяти
    vm_address_t addr = 0;
    vm_size_t size;
    while (vm_region_64(...)) {
        if (!(info.protection & VM_PROT_READ)) continue;
        if (size > 10*1024*1024) continue; // слишком большой регион
        
        uint8_t *buffer = malloc(size);
        if (vm_read_overwrite(task, addr, size, (vm_address_t)buffer, &read) != KERN_SUCCESS) {
            free(buffer);
            continue;
        }
        
        // Ищем паттерн
        for (int i = 0; i < size - 0x100; i += 4) {
            float y = *(float*)(buffer + i + OFFSET_Y);
            if (y < 1 || y > 100) continue; // не высота
            
            float health = *(float*)(buffer + i + OFFSET_HEALTH);
            if (health < 1 || health > 200) continue; // не здоровье
            
            uint32_t id = *(uint32_t*)(buffer + i + OFFSET_ID);
            if (id < 1000000) continue; // не ID
            
            // Нашли игрока!
            Player *p = [Player new];
            p.address = addr + i;
            p.health = health;
            p.y = y;
            p.x = *(float*)(buffer + i + OFFSET_X);
            p.z = *(float*)(buffer + i + OFFSET_Z);
            p.playerId = id;
            p.isLocal = (id == MY_ID);
            
            [players addObject:p];
            i += 0x80; // пропускаем структуру
            if (players.count > 20) break; // лимит
        }
        free(buffer);
    }
    
    // Рисуем ESP
    [overlayView setNeedsDisplay];
}
