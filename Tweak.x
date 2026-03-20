// ========== НАСТРОЙКИ ==========
#define COPY_COUNT 4               // количество копий координат
#define COPY_OFFSET 0x108          // смещение между копиями (264 байта)
#define STRUCT_SIZE 0x800          // размер структуры игрока

// ========== ПОИСК ИГРОКОВ ПО КОПИЯМ КООРДИНАТ ==========
+ (void)findPlayersByCopies {
    players = [NSMutableArray array];
    baseAddr = [self getBaseAddress];
    
    [self addLog:@"\n🔍 ПОИСК ПО 4 КОПИЯМ КООРДИНАТ"];
    [self addLog:@"==========================="];
    [self addLog:[NSString stringWithFormat:@"📌 База: 0x%llx", baseAddr]];
    
    task_t task = mach_task_self();
    vm_address_t addr = 0;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name;
    
    int found = 0;
    int scanned = 0;
    
    while (vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object_name) == KERN_SUCCESS && found < 30) {
        
        if (size > 4096 && size < 10*1024*1024 && (info.protection & VM_PROT_READ)) {
            
            uint8_t *buffer = malloc(size);
            vm_size_t read;
            
            if (vm_read_overwrite(task, addr, size, (vm_address_t)buffer, &read) == KERN_SUCCESS) {
                
                for (int i = 0; i < size - (COPY_COUNT * COPY_OFFSET); i += 8) {
                    scanned++;
                    
                    BOOL valid = YES;
                    float coords[COPY_COUNT][3]; // X,Y,Z для каждой копии
                    
                    // Проверяем все копии координат
                    for (int c = 0; c < COPY_COUNT; c++) {
                        int offset = c * COPY_OFFSET;
                        
                        float *x = (float*)(buffer + i + offset);
                        float *y = (float*)(buffer + i + offset + 4);
                        float *z = (float*)(buffer + i + offset + 8);
                        
                        // Сохраняем координаты
                        coords[c][0] = *x;
                        coords[c][1] = *y;
                        coords[c][2] = *z;
                        
                        // Проверяем, что координаты разумные
                        if (fabs(*x) > 10000 || fabs(*y) > 10000 || fabs(*z) > 10000) {
                            valid = NO;
                            break;
                        }
                        if (fabs(*x) < 0.1 && fabs(*y) < 0.1 && fabs(*z) < 0.1) {
                            valid = NO;
                            break;
                        }
                    }
                    
                    if (valid) {
                        // Нашли игрока! Берём первую копию координат
                        Player *p = [[Player alloc] init];
                        p.x = coords[0][0];
                        p.y = coords[0][1];
                        p.z = coords[0][2];
                        p.health = 100;
                        p.isLocal = (found == 0);
                        
                        [players addObject:p];
                        found++;
                        
                        [self addLog:[NSString stringWithFormat:@"✅ Игрок %d: (%.1f,%.1f,%.1f) [%d копий]",
                                      found, p.x, p.y, p.z, COPY_COUNT]];
                        
                        i += COPY_OFFSET * 2; // пропускаем структуру
                        if (found >= 20) break;
                    }
                }
            }
            free(buffer);
        }
        addr += size;
        if (scanned % 100000 == 0) usleep(1000);
    }
    
    [self addLog:[NSString stringWithFormat:@"📊 Проверено адресов: %d", scanned]];
    [self addLog:[NSString stringWithFormat:@"🎯 Найдено игроков: %d", found]];
    [overlayWindow.subviews.firstObject setNeedsDisplay];
    [self showLog];
}
