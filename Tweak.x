#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <limits.h>

// ===== ПРОТОТИПЫ ФУНКЦИЙ =====
uintptr_t safeReadPtr(uintptr_t addr);

// ===== ГЛОБАЛЬНЫЕ =====
static int serverSocket = -1;
static BOOL serverRunning = NO;
static NSMutableString *logText = nil;
static UITextView *logView = nil;
static UIWindow *win = nil;

// Хранилище списков адресов и значений
static NSMutableDictionary *savedLists = nil;
static NSMutableDictionary *savedValues = nil;
static NSMutableDictionary *savedFloatValues = nil;
static NSMutableDictionary *savedLongValues = nil;
static NSMutableDictionary *savedByteValues = nil;
static NSMutableDictionary *savedShortValues = nil;
static NSMutableDictionary *savedStringValues = nil;
static NSMutableDictionary *listTimestamps = nil;
static int nextListId = 1;

void addLog(NSString *msg) {
    if (!logText) logText = [[NSMutableString alloc] init];
    [logText appendString:msg];
    [logText appendString:@"\n"];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (logView) logView.text = logText;
        NSLog(@"[SERVER] %@", msg);
    });
}

void cleanOldLists(void) {
    if (!savedLists || !listTimestamps) return;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableArray *toRemove = [NSMutableArray array];
    for (NSNumber *key in listTimestamps) {
        NSTimeInterval timestamp = [listTimestamps[key] doubleValue];
        if (now - timestamp > 300) {
            [toRemove addObject:key];
        }
    }
    for (NSNumber *key in toRemove) {
        [savedLists removeObjectForKey:key];
        [listTimestamps removeObjectForKey:key];
        [savedValues removeObjectForKey:key];
        [savedFloatValues removeObjectForKey:key];
        [savedLongValues removeObjectForKey:key];
        [savedByteValues removeObjectForKey:key];
        [savedShortValues removeObjectForKey:key];
        [savedStringValues removeObjectForKey:key];
        addLog([NSString stringWithFormat:@"🗑️ Auto-cleaned old list %d", [key intValue]]);
    }
}

NSString* getIPAddress(void) {
    NSString *address = @"error";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    success = getifaddrs(&interfaces);
    if (success == 0) {
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr->sa_family == AF_INET) {
                if([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address;
}

// ===== БЕЗОПАСНОЕ ЧТЕНИЕ =====
int safeReadInt(uintptr_t addr) {
    if (addr == 0) return 0;
    int val = 0;
    vm_size_t read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, &read);
    if (kr != KERN_SUCCESS || read != 4) return 0;
    return val;
}

short safeReadShort(uintptr_t addr) {
    if (addr == 0) return 0;
    short val = 0;
    vm_size_t read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, 2, (vm_address_t)&val, &read);
    if (kr != KERN_SUCCESS || read != 2) return 0;
    return val;
}

char safeReadByte(uintptr_t addr) {
    if (addr == 0) return 0;
    char val = 0;
    vm_size_t read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, 1, (vm_address_t)&val, &read);
    if (kr != KERN_SUCCESS || read != 1) return 0;
    return val;
}

float safeReadFloat(uintptr_t addr) {
    if (addr == 0) return 0;
    float val = 0;
    vm_size_t read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, 4, (vm_address_t)&val, &read);
    if (kr != KERN_SUCCESS || read != 4) return 0;
    return val;
}

long long safeReadLong(uintptr_t addr) {
    if (addr == 0) return 0;
    long long val = 0;
    vm_size_t read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, 8, (vm_address_t)&val, &read);
    if (kr != KERN_SUCCESS || read != 8) return 0;
    return val;
}

uintptr_t safeReadPtr(uintptr_t addr) {
    if (addr == 0) return 0;
    uintptr_t val = 0;
    vm_size_t read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, 8, (vm_address_t)&val, &read);
    if (kr != KERN_SUCCESS || read != 8) return 0;
    return val;
}

// ===== СКАНИРОВАНИЕ С ШАГОМ =====
NSArray* scanIntRangeStep(int targetValue, uintptr_t minAddr, uintptr_t maxAddr, int step) {
    NSMutableArray *results = [NSMutableArray array];
    task_t task = mach_task_self();
    vm_address_t addr = minAddr;
    vm_size_t size = 0;
    struct vm_region_basic_info_64 info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name = MACH_PORT_NULL;
    uint8_t *buffer = malloc(0x10000);
    
    if (!buffer) return results;
    
    int regionCount = 0;
    
    while (addr < maxAddr) {
        kern_return_t kr = vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;
        
        if (size < 0x1000) {
            addr += size;
            continue;
        }
        
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE)) {
            uintptr_t scan_start = MAX(addr, minAddr);
            uintptr_t scan_end = MIN(addr + size, maxAddr);
            
            for (uintptr_t page = scan_start; page < scan_end; page += 0x10000) {
                uintptr_t pageSize = MIN(0x10000, scan_end - page);
                if (pageSize < step) continue;
                
                vm_size_t read = 0;
                kr = vm_read_overwrite(task, page, pageSize, (vm_address_t)buffer, &read);
                if (kr != KERN_SUCCESS || read < step) continue;
                
                for (uintptr_t offset = 0; offset + step <= pageSize; offset += step) {
                    int val = *(int*)(buffer + offset);
                    if (val == targetValue) {
                        [results addObject:@(page + offset)];
                    }
                }
            }
        }
        
        regionCount++;
        if (regionCount % 5 == 0) {
            usleep(10000);
        }
        
        addr += size;
        if (addr > maxAddr) break;
    }
    free(buffer);
    return results;
}

NSArray* scanFloatRangeStep(float targetValue, float tolerance, uintptr_t minAddr, uintptr_t maxAddr, int step) {
    NSMutableArray *results = [NSMutableArray array];
    task_t task = mach_task_self();
    vm_address_t addr = minAddr;
    vm_size_t size = 0;
    struct vm_region_basic_info_64 info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name = MACH_PORT_NULL;
    uint8_t *buffer = malloc(0x10000);
    if (!buffer) return results;
    
    int regionCount = 0;
    
    while (addr < maxAddr) {
        kern_return_t kr = vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;
        
        if (size < 0x1000) {
            addr += size;
            continue;
        }
        
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE)) {
            uintptr_t scan_start = MAX(addr, minAddr);
            uintptr_t scan_end = MIN(addr + size, maxAddr);
            
            for (uintptr_t page = scan_start; page < scan_end; page += 0x10000) {
                uintptr_t pageSize = MIN(0x10000, scan_end - page);
                if (pageSize < step) continue;
                
                vm_size_t read = 0;
                kr = vm_read_overwrite(task, page, pageSize, (vm_address_t)buffer, &read);
                if (kr != KERN_SUCCESS || read < step) continue;
                
                for (uintptr_t offset = 0; offset + step <= pageSize; offset += step) {
                    float val = *(float*)(buffer + offset);
                    if (fabs(val - targetValue) <= tolerance) {
                        [results addObject:@(page + offset)];
                    }
                }
            }
        }
        
        regionCount++;
        if (regionCount % 5 == 0) usleep(10000);
        
        addr += size;
        if (addr > maxAddr) break;
    }
    free(buffer);
    return results;
}

NSArray* scanLongRangeStep(long long targetValue, uintptr_t minAddr, uintptr_t maxAddr, int step) {
    NSMutableArray *results = [NSMutableArray array];
    task_t task = mach_task_self();
    vm_address_t addr = minAddr;
    vm_size_t size = 0;
    struct vm_region_basic_info_64 info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name = MACH_PORT_NULL;
    uint8_t *buffer = malloc(0x10000);
    if (!buffer) return results;
    
    int regionCount = 0;
    
    while (addr < maxAddr) {
        kern_return_t kr = vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;
        
        if (size < 0x1000) {
            addr += size;
            continue;
        }
        
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE)) {
            uintptr_t scan_start = MAX(addr, minAddr);
            uintptr_t scan_end = MIN(addr + size, maxAddr);
            
            for (uintptr_t page = scan_start; page < scan_end; page += 0x10000) {
                uintptr_t pageSize = MIN(0x10000, scan_end - page);
                if (pageSize < step) continue;
                
                vm_size_t read = 0;
                kr = vm_read_overwrite(task, page, pageSize, (vm_address_t)buffer, &read);
                if (kr != KERN_SUCCESS || read < step) continue;
                
                for (uintptr_t offset = 0; offset + step <= pageSize; offset += step) {
                    long long val = *(long long*)(buffer + offset);
                    if (val == targetValue) {
                        [results addObject:@(page + offset)];
                    }
                }
            }
        }
        
        regionCount++;
        if (regionCount % 5 == 0) usleep(10000);
        
        addr += size;
        if (addr > maxAddr) break;
    }
    free(buffer);
    return results;
}

NSArray* scanByteRangeStep(char targetValue, uintptr_t minAddr, uintptr_t maxAddr, int step) {
    NSMutableArray *results = [NSMutableArray array];
    task_t task = mach_task_self();
    vm_address_t addr = minAddr;
    vm_size_t size = 0;
    struct vm_region_basic_info_64 info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name = MACH_PORT_NULL;
    uint8_t *buffer = malloc(0x10000);
    if (!buffer) return results;
    
    int regionCount = 0;
    
    while (addr < maxAddr) {
        kern_return_t kr = vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;
        
        if (size < 0x1000) {
            addr += size;
            continue;
        }
        
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE)) {
            uintptr_t scan_start = MAX(addr, minAddr);
            uintptr_t scan_end = MIN(addr + size, maxAddr);
            
            for (uintptr_t page = scan_start; page < scan_end; page += 0x10000) {
                uintptr_t pageSize = MIN(0x10000, scan_end - page);
                if (pageSize < step) continue;
                
                vm_size_t read = 0;
                kr = vm_read_overwrite(task, page, pageSize, (vm_address_t)buffer, &read);
                if (kr != KERN_SUCCESS || read < step) continue;
                
                for (uintptr_t offset = 0; offset + step <= pageSize; offset += step) {
                    char val = *(char*)(buffer + offset);
                    if (val == targetValue) {
                        [results addObject:@(page + offset)];
                    }
                }
            }
        }
        
        regionCount++;
        if (regionCount % 5 == 0) usleep(10000);
        
        addr += size;
        if (addr > maxAddr) break;
    }
    free(buffer);
    return results;
}

NSArray* scanShortRangeStep(short targetValue, uintptr_t minAddr, uintptr_t maxAddr, int step) {
    NSMutableArray *results = [NSMutableArray array];
    task_t task = mach_task_self();
    vm_address_t addr = minAddr;
    vm_size_t size = 0;
    struct vm_region_basic_info_64 info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name = MACH_PORT_NULL;
    uint8_t *buffer = malloc(0x10000);
    if (!buffer) return results;
    
    int regionCount = 0;
    
    while (addr < maxAddr) {
        kern_return_t kr = vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;
        
        if (size < 0x1000) {
            addr += size;
            continue;
        }
        
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE)) {
            uintptr_t scan_start = MAX(addr, minAddr);
            uintptr_t scan_end = MIN(addr + size, maxAddr);
            
            for (uintptr_t page = scan_start; page < scan_end; page += 0x10000) {
                uintptr_t pageSize = MIN(0x10000, scan_end - page);
                if (pageSize < step) continue;
                
                vm_size_t read = 0;
                kr = vm_read_overwrite(task, page, pageSize, (vm_address_t)buffer, &read);
                if (kr != KERN_SUCCESS || read < step) continue;
                
                for (uintptr_t offset = 0; offset + step <= pageSize; offset += step) {
                    short val = *(short*)(buffer + offset);
                    if (val == targetValue) {
                        [results addObject:@(page + offset)];
                    }
                }
            }
        }
        
        regionCount++;
        if (regionCount % 5 == 0) usleep(10000);
        
        addr += size;
        if (addr > maxAddr) break;
    }
    free(buffer);
    return results;
}

NSArray* scanIntRange(int targetValue, uintptr_t minAddr, uintptr_t maxAddr) {
    return scanIntRangeStep(targetValue, minAddr, maxAddr, 4);
}

NSArray* scanFloatRange(float targetValue, float tolerance, uintptr_t minAddr, uintptr_t maxAddr) {
    return scanFloatRangeStep(targetValue, tolerance, minAddr, maxAddr, 4);
}

NSArray* scanLongRange(long long targetValue, uintptr_t minAddr, uintptr_t maxAddr) {
    return scanLongRangeStep(targetValue, minAddr, maxAddr, 8);
}

NSArray* scanByteRange(char targetValue, uintptr_t minAddr, uintptr_t maxAddr) {
    return scanByteRangeStep(targetValue, minAddr, maxAddr, 1);
}

NSArray* scanShortRange(short targetValue, uintptr_t minAddr, uintptr_t maxAddr) {
    return scanShortRangeStep(targetValue, minAddr, maxAddr, 2);
}

NSData* memoryDump(uintptr_t addr, int size) {
    if (size > 1024 * 1024) size = 1024 * 1024;
    if (size < 1) size = 1;
    uint8_t *buffer = malloc(size);
    if (!buffer) return nil;
    vm_size_t read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, size, (vm_address_t)buffer, &read);
    if (kr != KERN_SUCCESS) {
        free(buffer);
        return nil;
    }
    NSData *data = [NSData dataWithBytes:buffer length:read];
    free(buffer);
    return data;
}

// ===== ПОЛУЧЕНИЕ СПИСКА МОДУЛЕЙ =====
NSString* listModules(void) {
    NSMutableString *result = [NSMutableString string];
    task_t task = mach_task_self();
    vm_address_t addr = 0;
    vm_size_t size = 0;
    struct vm_region_basic_info_64 info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object_name = MACH_PORT_NULL;
    [result appendString:@"MODULES\n"];
    while (1) {
        kern_return_t kr = vm_region_64(task, &addr, &size, VM_REGION_BASIC_INFO_64,
                                         (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;
        if (addr >= 0x100000000) {
            [result appendFormat:@"0x%lx-0x%lx ", (unsigned long)addr, (unsigned long)(addr + size)];
            if (info.protection & VM_PROT_READ) [result appendString:@"r"];
            else [result appendString:@"-"];
            if (info.protection & VM_PROT_WRITE) [result appendString:@"w"];
            else [result appendString:@"-"];
            if (info.protection & VM_PROT_EXECUTE) [result appendString:@"x"];
            else [result appendString:@"-"];
            [result appendString:@"\n"];
        }
        addr += size;
        if (addr > 0x300000000) break;
    }
    return result;
}

// ===== ОБРАБОТКА КОМАНД =====
NSString* handleCommand(NSString *cmd) {
    if (!savedLists) {
        savedLists = [NSMutableDictionary dictionary];
        savedValues = [NSMutableDictionary dictionary];
        savedFloatValues = [NSMutableDictionary dictionary];
        savedLongValues = [NSMutableDictionary dictionary];
        savedByteValues = [NSMutableDictionary dictionary];
        savedShortValues = [NSMutableDictionary dictionary];
        savedStringValues = [NSMutableDictionary dictionary];
        listTimestamps = [NSMutableDictionary dictionary];
    }
    NSArray *parts = [cmd componentsSeparatedByString:@" "];
    NSString *command = [parts[0] uppercaseString];
    
    if ([command isEqualToString:@"PING"]) {
        return @"PONG";
    }
    // ===== СКАНИРОВАНИЕ =====
    else if ([command isEqualToString:@"SCAN_INT"]) {
        if (parts.count < 2) return @"ERROR: need value";
        int value = [parts[1] intValue];
        NSArray *results = scanIntRange(value, 0x100000000, 0x300000000);
        int listId = nextListId++;
        savedLists[@(listId)] = [results mutableCopy];
        listTimestamps[@(listId)] = @([[NSDate date] timeIntervalSince1970]);
        NSMutableString *response = [NSMutableString stringWithFormat:@"RESULTS %d %lu", listId, (unsigned long)results.count];
        NSUInteger maxShow = MIN(500, results.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [results[i] unsignedLongValue]];
        }
        return response;
    }
    else if ([command isEqualToString:@"SCAN_FLOAT"]) {
        if (parts.count < 2) return @"ERROR: need value";
        float value = [parts[1] floatValue];
        float tolerance = (parts.count > 2) ? [parts[2] floatValue] : 0.001;
        NSArray *results = scanFloatRange(value, tolerance, 0x100000000, 0x300000000);
        int listId = nextListId++;
        savedLists[@(listId)] = [results mutableCopy];
        listTimestamps[@(listId)] = @([[NSDate date] timeIntervalSince1970]);
        NSMutableString *response = [NSMutableString stringWithFormat:@"RESULTS %d %lu", listId, (unsigned long)results.count];
        NSUInteger maxShow = MIN(500, results.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [results[i] unsignedLongValue]];
        }
        return response;
    }
    else if ([command isEqualToString:@"SCAN_LONG"]) {
        if (parts.count < 2) return @"ERROR: need value";
        long long value = strtoll([parts[1] UTF8String], NULL, 0);
        NSArray *results = scanLongRange(value, 0x100000000, 0x300000000);
        int listId = nextListId++;
        savedLists[@(listId)] = [results mutableCopy];
        listTimestamps[@(listId)] = @([[NSDate date] timeIntervalSince1970]);
        NSMutableString *response = [NSMutableString stringWithFormat:@"RESULTS %d %lu", listId, (unsigned long)results.count];
        NSUInteger maxShow = MIN(500, results.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [results[i] unsignedLongValue]];
        }
        return response;
    }
    else if ([command isEqualToString:@"SCAN_BYTE"]) {
        if (parts.count < 2) return @"ERROR: need value";
        char value = (char)[parts[1] intValue];
        NSArray *results = scanByteRange(value, 0x100000000, 0x300000000);
        int listId = nextListId++;
        savedLists[@(listId)] = [results mutableCopy];
        listTimestamps[@(listId)] = @([[NSDate date] timeIntervalSince1970]);
        NSMutableString *response = [NSMutableString stringWithFormat:@"RESULTS %d %lu", listId, (unsigned long)results.count];
        NSUInteger maxShow = MIN(500, results.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [results[i] unsignedLongValue]];
        }
        return response;
    }
    else if ([command isEqualToString:@"SCAN_SHORT"]) {
        if (parts.count < 2) return @"ERROR: need value";
        short value = (short)[parts[1] intValue];
        NSArray *results = scanShortRange(value, 0x100000000, 0x300000000);
        int listId = nextListId++;
        savedLists[@(listId)] = [results mutableCopy];
        listTimestamps[@(listId)] = @([[NSDate date] timeIntervalSince1970]);
        NSMutableString *response = [NSMutableString stringWithFormat:@"RESULTS %d %lu", listId, (unsigned long)results.count];
        NSUInteger maxShow = MIN(500, results.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [results[i] unsignedLongValue]];
        }
        return response;
    }
    // ===== НЕИЗВЕСТНЫЙ ПОИСК С ШАГОМ =====
    else if ([command isEqualToString:@"SCAN_UNKNOWN_RANGE"]) {
        if (parts.count < 5) return @"ERROR: need min_addr, max_addr, type, step";
        uintptr_t minAddr = strtoull([parts[1] UTF8String], NULL, 16);
        uintptr_t maxAddr = strtoull([parts[2] UTF8String], NULL, 16);
        NSString *type = [parts[3] uppercaseString];
        int step = [parts[4] intValue];
        
        NSArray *results = nil;
        
        if ([type isEqualToString:@"INT"]) {
            results = scanIntRangeStep(0, minAddr, maxAddr, step);
        } else if ([type isEqualToString:@"FLOAT"]) {
            results = scanFloatRangeStep(0, 100, minAddr, maxAddr, step);
        } else if ([type isEqualToString:@"LONG"]) {
            results = scanLongRangeStep(0, minAddr, maxAddr, step);
        } else if ([type isEqualToString:@"BYTE"]) {
            results = scanByteRangeStep(0, minAddr, maxAddr, step);
        } else if ([type isEqualToString:@"SHORT"]) {
            results = scanShortRangeStep(0, minAddr, maxAddr, step);
        } else {
            results = scanIntRangeStep(0, minAddr, maxAddr, step);
        }
        
        int listId = nextListId++;
        savedLists[@(listId)] = [results mutableCopy];
        
        for (NSNumber *addrNum in results) {
            uintptr_t addr = [addrNum unsignedLongValue];
            if ([type isEqualToString:@"INT"]) {
                savedValues[addrNum] = @(safeReadInt(addr));
            } else if ([type isEqualToString:@"FLOAT"]) {
                savedFloatValues[addrNum] = @(safeReadFloat(addr));
            } else if ([type isEqualToString:@"LONG"]) {
                savedLongValues[addrNum] = @(safeReadLong(addr));
            } else if ([type isEqualToString:@"BYTE"]) {
                savedByteValues[addrNum] = @(safeReadByte(addr));
            } else if ([type isEqualToString:@"SHORT"]) {
                savedShortValues[addrNum] = @(safeReadShort(addr));
            }
        }
        
        listTimestamps[@(listId)] = @([[NSDate date] timeIntervalSince1970]);
        
        NSMutableString *response = [NSMutableString stringWithFormat:@"RESULTS %d %lu", listId, (unsigned long)results.count];
        NSUInteger maxShow = MIN(500, results.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [results[i] unsignedLongValue]];
        }
        return response;
    }
    // ===== ФИЛЬТРЫ UNKNOWN SEARCH =====
    else if ([command isEqualToString:@"FILTER_CHANGED"]) {
        if (parts.count < 3) return @"ERROR: need list_id and type";
        int listId = [parts[1] intValue];
        NSString *type = [parts[2] uppercaseString];
        
        NSMutableArray *list = savedLists[@(listId)];
        if (!list) return @"ERROR: list not found";
        
        NSMutableArray *filtered = [NSMutableArray array];
        
        for (NSNumber *addrNum in list) {
            uintptr_t addr = [addrNum unsignedLongValue];
            
            if ([type isEqualToString:@"INT"]) {
                int oldVal = [savedValues[addrNum] intValue];
                int newVal = safeReadInt(addr);
                if (newVal != oldVal) {
                    [filtered addObject:addrNum];
                    savedValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"FLOAT"]) {
                float oldVal = [savedFloatValues[addrNum] floatValue];
                float newVal = safeReadFloat(addr);
                if (fabs(newVal - oldVal) > 0.0001f) {
                    [filtered addObject:addrNum];
                    savedFloatValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"LONG"]) {
                long long oldVal = [savedLongValues[addrNum] longLongValue];
                long long newVal = safeReadLong(addr);
                if (newVal != oldVal) {
                    [filtered addObject:addrNum];
                    savedLongValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"BYTE"]) {
                char oldVal = [savedByteValues[addrNum] charValue];
                char newVal = safeReadByte(addr);
                if (newVal != oldVal) {
                    [filtered addObject:addrNum];
                    savedByteValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"SHORT"]) {
                short oldVal = [savedShortValues[addrNum] shortValue];
                short newVal = safeReadShort(addr);
                if (newVal != oldVal) {
                    [filtered addObject:addrNum];
                    savedShortValues[addrNum] = @(newVal);
                }
            }
        }
        
        savedLists[@(listId)] = filtered;
        
        NSMutableString *response = [NSMutableString stringWithFormat:@"FILTERED %d %lu", listId, (unsigned long)filtered.count];
        NSUInteger maxShow = MIN(500, filtered.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [filtered[i] unsignedLongValue]];
        }
        return response;
    }
    else if ([command isEqualToString:@"FILTER_UNCHANGED"]) {
        if (parts.count < 3) return @"ERROR: need list_id and type";
        int listId = [parts[1] intValue];
        NSString *type = [parts[2] uppercaseString];
        
        NSMutableArray *list = savedLists[@(listId)];
        if (!list) return @"ERROR: list not found";
        
        NSMutableArray *filtered = [NSMutableArray array];
        
        for (NSNumber *addrNum in list) {
            uintptr_t addr = [addrNum unsignedLongValue];
            
            if ([type isEqualToString:@"INT"]) {
                int oldVal = [savedValues[addrNum] intValue];
                int newVal = safeReadInt(addr);
                if (newVal == oldVal) {
                    [filtered addObject:addrNum];
                } else {
                    savedValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"FLOAT"]) {
                float oldVal = [savedFloatValues[addrNum] floatValue];
                float newVal = safeReadFloat(addr);
                if (fabs(newVal - oldVal) <= 0.0001f) {
                    [filtered addObject:addrNum];
                } else {
                    savedFloatValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"LONG"]) {
                long long oldVal = [savedLongValues[addrNum] longLongValue];
                long long newVal = safeReadLong(addr);
                if (newVal == oldVal) {
                    [filtered addObject:addrNum];
                } else {
                    savedLongValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"BYTE"]) {
                char oldVal = [savedByteValues[addrNum] charValue];
                char newVal = safeReadByte(addr);
                if (newVal == oldVal) {
                    [filtered addObject:addrNum];
                } else {
                    savedByteValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"SHORT"]) {
                short oldVal = [savedShortValues[addrNum] shortValue];
                short newVal = safeReadShort(addr);
                if (newVal == oldVal) {
                    [filtered addObject:addrNum];
                } else {
                    savedShortValues[addrNum] = @(newVal);
                }
            }
        }
        
        savedLists[@(listId)] = filtered;
        
        NSMutableString *response = [NSMutableString stringWithFormat:@"FILTERED %d %lu", listId, (unsigned long)filtered.count];
        NSUInteger maxShow = MIN(500, filtered.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [filtered[i] unsignedLongValue]];
        }
        return response;
    }
    else if ([command isEqualToString:@"FILTER_INCREASED"]) {
        if (parts.count < 3) return @"ERROR: need list_id and type";
        int listId = [parts[1] intValue];
        NSString *type = [parts[2] uppercaseString];
        
        NSMutableArray *list = savedLists[@(listId)];
        if (!list) return @"ERROR: list not found";
        
        NSMutableArray *filtered = [NSMutableArray array];
        
        for (NSNumber *addrNum in list) {
            uintptr_t addr = [addrNum unsignedLongValue];
            
            if ([type isEqualToString:@"INT"]) {
                int oldVal = [savedValues[addrNum] intValue];
                int newVal = safeReadInt(addr);
                if (newVal > oldVal) {
                    [filtered addObject:addrNum];
                    savedValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"FLOAT"]) {
                float oldVal = [savedFloatValues[addrNum] floatValue];
                float newVal = safeReadFloat(addr);
                if (newVal > oldVal + 0.0001f) {
                    [filtered addObject:addrNum];
                    savedFloatValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"LONG"]) {
                long long oldVal = [savedLongValues[addrNum] longLongValue];
                long long newVal = safeReadLong(addr);
                if (newVal > oldVal) {
                    [filtered addObject:addrNum];
                    savedLongValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"BYTE"]) {
                char oldVal = [savedByteValues[addrNum] charValue];
                char newVal = safeReadByte(addr);
                if (newVal > oldVal) {
                    [filtered addObject:addrNum];
                    savedByteValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"SHORT"]) {
                short oldVal = [savedShortValues[addrNum] shortValue];
                short newVal = safeReadShort(addr);
                if (newVal > oldVal) {
                    [filtered addObject:addrNum];
                    savedShortValues[addrNum] = @(newVal);
                }
            }
        }
        
        savedLists[@(listId)] = filtered;
        
        NSMutableString *response = [NSMutableString stringWithFormat:@"FILTERED %d %lu", listId, (unsigned long)filtered.count];
        NSUInteger maxShow = MIN(500, filtered.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [filtered[i] unsignedLongValue]];
        }
        return response;
    }
    else if ([command isEqualToString:@"FILTER_DECREASED"]) {
        if (parts.count < 3) return @"ERROR: need list_id and type";
        int listId = [parts[1] intValue];
        NSString *type = [parts[2] uppercaseString];
        
        NSMutableArray *list = savedLists[@(listId)];
        if (!list) return @"ERROR: list not found";
        
        NSMutableArray *filtered = [NSMutableArray array];
        
        for (NSNumber *addrNum in list) {
            uintptr_t addr = [addrNum unsignedLongValue];
            
            if ([type isEqualToString:@"INT"]) {
                int oldVal = [savedValues[addrNum] intValue];
                int newVal = safeReadInt(addr);
                if (newVal < oldVal) {
                    [filtered addObject:addrNum];
                    savedValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"FLOAT"]) {
                float oldVal = [savedFloatValues[addrNum] floatValue];
                float newVal = safeReadFloat(addr);
                if (newVal < oldVal - 0.0001f) {
                    [filtered addObject:addrNum];
                    savedFloatValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"LONG"]) {
                long long oldVal = [savedLongValues[addrNum] longLongValue];
                long long newVal = safeReadLong(addr);
                if (newVal < oldVal) {
                    [filtered addObject:addrNum];
                    savedLongValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"BYTE"]) {
                char oldVal = [savedByteValues[addrNum] charValue];
                char newVal = safeReadByte(addr);
                if (newVal < oldVal) {
                    [filtered addObject:addrNum];
                    savedByteValues[addrNum] = @(newVal);
                }
            } else if ([type isEqualToString:@"SHORT"]) {
                short oldVal = [savedShortValues[addrNum] shortValue];
                short newVal = safeReadShort(addr);
                if (newVal < oldVal) {
                    [filtered addObject:addrNum];
                    savedShortValues[addrNum] = @(newVal);
                }
            }
        }
        
        savedLists[@(listId)] = filtered;
        
        NSMutableString *response = [NSMutableString stringWithFormat:@"FILTERED %d %lu", listId, (unsigned long)filtered.count];
        NSUInteger maxShow = MIN(500, filtered.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [filtered[i] unsignedLongValue]];
        }
        return response;
    }
    // ===== ОСТАЛЬНЫЕ ФИЛЬТРЫ (по значению) =====
    else if ([command isEqualToString:@"FILTER_INT"]) {
        if (parts.count < 3) return @"ERROR: need list_id and value";
        int listId = [parts[1] intValue];
        int targetValue = [parts[2] intValue];
        NSMutableArray *list = savedLists[@(listId)];
        if (!list) return @"ERROR: list not found";
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSNumber *addrNum in list) {
            uintptr_t addr = [addrNum unsignedLongValue];
            int val = safeReadInt(addr);
            if (val == targetValue) {
                [filtered addObject:addrNum];
            }
        }
        savedLists[@(listId)] = filtered;
        listTimestamps[@(listId)] = @([[NSDate date] timeIntervalSince1970]);
        NSMutableString *response = [NSMutableString stringWithFormat:@"FILTERED %d %lu", listId, (unsigned long)filtered.count];
        NSUInteger maxShow = MIN(500, filtered.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [filtered[i] unsignedLongValue]];
        }
        return response;
    }
    else if ([command isEqualToString:@"FILTER_FLOAT"]) {
        if (parts.count < 3) return @"ERROR: need list_id and value";
        int listId = [parts[1] intValue];
        float targetValue = [parts[2] floatValue];
        float tolerance = (parts.count > 3) ? [parts[3] floatValue] : 0.001;
        NSMutableArray *list = savedLists[@(listId)];
        if (!list) return @"ERROR: list not found";
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSNumber *addrNum in list) {
            uintptr_t addr = [addrNum unsignedLongValue];
            float val = safeReadFloat(addr);
            if (fabs(val - targetValue) <= tolerance) {
                [filtered addObject:addrNum];
            }
        }
        savedLists[@(listId)] = filtered;
        listTimestamps[@(listId)] = @([[NSDate date] timeIntervalSince1970]);
        NSMutableString *response = [NSMutableString stringWithFormat:@"FILTERED %d %lu", listId, (unsigned long)filtered.count];
        NSUInteger maxShow = MIN(500, filtered.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [filtered[i] unsignedLongValue]];
        }
        return response;
    }
    else if ([command isEqualToString:@"FILTER_LONG"]) {
        if (parts.count < 3) return @"ERROR: need list_id and value";
        int listId = [parts[1] intValue];
        long long targetValue = strtoll([parts[2] UTF8String], NULL, 0);
        NSMutableArray *list = savedLists[@(listId)];
        if (!list) return @"ERROR: list not found";
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSNumber *addrNum in list) {
            uintptr_t addr = [addrNum unsignedLongValue];
            long long val = safeReadLong(addr);
            if (val == targetValue) {
                [filtered addObject:addrNum];
            }
        }
        savedLists[@(listId)] = filtered;
        listTimestamps[@(listId)] = @([[NSDate date] timeIntervalSince1970]);
        NSMutableString *response = [NSMutableString stringWithFormat:@"FILTERED %d %lu", listId, (unsigned long)filtered.count];
        NSUInteger maxShow = MIN(500, filtered.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [filtered[i] unsignedLongValue]];
        }
        return response;
    }
    else if ([command isEqualToString:@"FILTER_BYTE"]) {
        if (parts.count < 3) return @"ERROR: need list_id and value";
        int listId = [parts[1] intValue];
        char targetValue = (char)[parts[2] intValue];
        NSMutableArray *list = savedLists[@(listId)];
        if (!list) return @"ERROR: list not found";
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSNumber *addrNum in list) {
            uintptr_t addr = [addrNum unsignedLongValue];
            char val = safeReadByte(addr);
            if (val == targetValue) {
                [filtered addObject:addrNum];
            }
        }
        savedLists[@(listId)] = filtered;
        listTimestamps[@(listId)] = @([[NSDate date] timeIntervalSince1970]);
        NSMutableString *response = [NSMutableString stringWithFormat:@"FILTERED %d %lu", listId, (unsigned long)filtered.count];
        NSUInteger maxShow = MIN(500, filtered.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [filtered[i] unsignedLongValue]];
        }
        return response;
    }
    else if ([command isEqualToString:@"FILTER_SHORT"]) {
        if (parts.count < 3) return @"ERROR: need list_id and value";
        int listId = [parts[1] intValue];
        short targetValue = (short)[parts[2] intValue];
        NSMutableArray *list = savedLists[@(listId)];
        if (!list) return @"ERROR: list not found";
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSNumber *addrNum in list) {
            uintptr_t addr = [addrNum unsignedLongValue];
            short val = safeReadShort(addr);
            if (val == targetValue) {
                [filtered addObject:addrNum];
            }
        }
        savedLists[@(listId)] = filtered;
        listTimestamps[@(listId)] = @([[NSDate date] timeIntervalSince1970]);
        NSMutableString *response = [NSMutableString stringWithFormat:@"FILTERED %d %lu", listId, (unsigned long)filtered.count];
        NSUInteger maxShow = MIN(500, filtered.count);
        for (NSUInteger i = 0; i < maxShow; i++) {
            [response appendFormat:@"\n0x%lx", [filtered[i] unsignedLongValue]];
        }
        return response;
    }
    // ===== ПОИСК ЦЕПОЧКИ УКАЗАТЕЛЕЙ =====
    else if ([command isEqualToString:@"FIND_POINTER_CHAIN"]) {
        if (parts.count < 3) return @"ERROR: need target_addr, max_depth";
        uintptr_t targetAddr = strtoull([parts[1] UTF8String], NULL, 16);
        int maxDepth = [parts[2] intValue];
        
        NSMutableArray *chain = [NSMutableArray array];
        uintptr_t currentAddr = targetAddr;
        
        for (int depth = 0; depth < maxDepth; depth++) {
            uintptr_t found = 0;
            
            for (uintptr_t addr = 0x100000000; addr < 0x300000000; addr += 4) {
                uintptr_t val = safeReadPtr(addr);
                if (val == currentAddr) {
                    found = addr;
                    break;
                }
            }
            
            if (found != 0) {
                [chain addObject:@(found)];
                currentAddr = found;
            } else {
                break;
            }
        }
        
        NSMutableString *response = [NSMutableString stringWithFormat:@"POINTER_CHAIN %lu", (unsigned long)chain.count];
        for (NSNumber *addr in chain) {
            [response appendFormat:@"\n0x%lx", [addr unsignedLongValue]];
        }
        return response;
    }
    // ===== УПРАВЛЕНИЕ СПИСКАМИ =====
    else if ([command isEqualToString:@"CLEAR_LIST"]) {
        if (parts.count < 2) return @"ERROR: need list_id";
        int listId = [parts[1] intValue];
        [savedLists removeObjectForKey:@(listId)];
        [listTimestamps removeObjectForKey:@(listId)];
        [savedValues removeObjectForKey:@(listId)];
        [savedFloatValues removeObjectForKey:@(listId)];
        [savedLongValues removeObjectForKey:@(listId)];
        [savedByteValues removeObjectForKey:@(listId)];
        [savedShortValues removeObjectForKey:@(listId)];
        [savedStringValues removeObjectForKey:@(listId)];
        return @"CLEARED";
    }
    else if ([command isEqualToString:@"CLEAR_ALL_LISTS"]) {
        [savedLists removeAllObjects];
        [listTimestamps removeAllObjects];
        [savedValues removeAllObjects];
        [savedFloatValues removeAllObjects];
        [savedLongValues removeAllObjects];
        [savedByteValues removeAllObjects];
        [savedShortValues removeAllObjects];
        [savedStringValues removeAllObjects];
        nextListId = 1;
        return @"CLEARED";
    }
    else if ([command isEqualToString:@"GET_LIST_COUNT"]) {
        if (parts.count < 2) return @"ERROR: need list_id";
        int listId = [parts[1] intValue];
        NSArray *list = savedLists[@(listId)];
        if (!list) return @"COUNT 0";
        return [NSString stringWithFormat:@"COUNT %lu", (unsigned long)list.count];
    }
    // ===== LIST_MODULES =====
    else if ([command isEqualToString:@"LIST_MODULES"]) {
        return listModules();
    }
    // ===== ЧТЕНИЕ =====
    else if ([command isEqualToString:@"READ_INT"]) {
        if (parts.count < 2) return @"ERROR: need addr";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        int val = safeReadInt(addr);
        return [NSString stringWithFormat:@"INT %d", val];
    }
    else if ([command isEqualToString:@"READ_FLOAT"]) {
        if (parts.count < 2) return @"ERROR: need addr";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        float val = safeReadFloat(addr);
        return [NSString stringWithFormat:@"FLOAT %f", val];
    }
    else if ([command isEqualToString:@"READ_LONG"]) {
        if (parts.count < 2) return @"ERROR: need addr";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        long long val = safeReadLong(addr);
        return [NSString stringWithFormat:@"LONG %lld", val];
    }
    else if ([command isEqualToString:@"READ_BYTE"]) {
        if (parts.count < 2) return @"ERROR: need addr";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        char val = safeReadByte(addr);
        return [NSString stringWithFormat:@"BYTE %d", val];
    }
    else if ([command isEqualToString:@"READ_SHORT"]) {
        if (parts.count < 2) return @"ERROR: need addr";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        short val = safeReadShort(addr);
        return [NSString stringWithFormat:@"SHORT %d", val];
    }
    else if ([command isEqualToString:@"READ_PTR"]) {
        if (parts.count < 2) return @"ERROR: need addr";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        uintptr_t val = safeReadPtr(addr);
        return [NSString stringWithFormat:@"PTR 0x%lx", val];
    }
    else if ([command isEqualToString:@"READ_STRING"]) {
        if (parts.count < 2) return @"ERROR: need addr";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        int maxLen = (parts.count > 2) ? [parts[2] intValue] : 64;
        if (maxLen > 1024) maxLen = 1024;
        uint8_t *buffer = malloc(maxLen);
        if (!buffer) return @"ERROR: malloc failed";
        vm_size_t read = 0;
        kern_return_t kr = vm_read_overwrite(mach_task_self(), addr, maxLen, (vm_address_t)buffer, &read);
        if (kr != KERN_SUCCESS) {
            free(buffer);
            return @"ERROR: read failed";
        }
        NSUInteger len = 0;
        for (NSUInteger i = 0; i < read; i++) {
            if (buffer[i] == 0) break;
            len++;
        }
        NSString *str = [[NSString alloc] initWithBytes:buffer length:len encoding:NSUTF8StringEncoding];
        free(buffer);
        if (!str) str = @"";
        return [NSString stringWithFormat:@"STRING %@", str];
    }
    else if ([command isEqualToString:@"DUMP"]) {
        if (parts.count < 3) return @"ERROR: need addr and size";
        uintptr_t addr = strtoull([parts[1] UTF8String], NULL, 16);
        int size = [parts[2] intValue];
        if (size > 1048576) size = 1048576;
        NSData *data = memoryDump(addr, size);
        if (!data) return @"ERROR: dump failed";
        NSString *b64 = [data base64EncodedStringWithOptions:0];
        return [NSString stringWithFormat:@"DUMP_DATA %@", b64];
    }
    
    return @"ERROR: unknown command";
}

// ===== TCP СЕРВЕР =====
void startServer(void) {
    if (serverRunning) {
        addLog(@"⚠️ Сервер уже запущен");
        return;
    }
    serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (serverSocket < 0) {
        addLog(@"❌ Не удалось создать сокет");
        return;
    }
    int reuse = 1;
    setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(12345);
    if (bind(serverSocket, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        addLog(@"❌ Не удалось привязать порт 12345");
        close(serverSocket);
        serverSocket = -1;
        return;
    }
    if (listen(serverSocket, 5) < 0) {
        addLog(@"❌ Ошибка listen");
        close(serverSocket);
        serverSocket = -1;
        return;
    }
    serverRunning = YES;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (serverRunning) {
            sleep(60);
            cleanOldLists();
        }
    });
    NSString *ip = getIPAddress();
    addLog(@"✅ Сервер запущен на порту 12345");
    addLog([NSString stringWithFormat:@"📡 IP: %@", ip]);
    addLog(@"💡 Подключитесь с ПК");
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (serverRunning) {
            struct sockaddr_in clientAddr;
            socklen_t clientLen = sizeof(clientAddr);
            int clientSocket = accept(serverSocket, (struct sockaddr*)&clientAddr, &clientLen);
            if (clientSocket < 0) continue;
            char clientIP[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &clientAddr.sin_addr, clientIP, sizeof(clientIP));
            addLog([NSString stringWithFormat:@"🔌 Подключён клиент: %s", clientIP]);
            char buffer[16384];
            while (serverRunning) {
                memset(buffer, 0, sizeof(buffer));
                ssize_t received = recv(clientSocket, buffer, sizeof(buffer) - 1, 0);
                if (received <= 0) break;
                NSString *cmd = [NSString stringWithUTF8String:buffer];
                cmd = [cmd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSString *response = handleCommand(cmd);
                response = [response stringByAppendingString:@"\n"];
                const char *respData = [response UTF8String];
                send(clientSocket, respData, strlen(respData), 0);
            }
            close(clientSocket);
            addLog(@"🔌 Клиент отключён");
        }
    });
}

void stopServer(void) {
    serverRunning = NO;
    if (serverSocket >= 0) {
        close(serverSocket);
        serverSocket = -1;
    }
    addLog(@"🛑 Сервер остановлен");
}

// ===== КНОПКИ =====
@interface ServerController : NSObject
+ (void)startServer;
+ (void)stopServer;
+ (void)closeMenu;
@end

@implementation ServerController
+ (void)startServer { startServer(); }
+ (void)stopServer { stopServer(); }
+ (void)closeMenu {
    if (win) {
        win.hidden = YES;
        win = nil;
    }
}
@end

// ===== МЕНЮ =====
void createMenu(void) {
    UIWindow *key = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class]) {
            UIWindowScene *ws = (UIWindowScene *)s;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) { key = w; break; }
            }
        }
        if (key) break;
    }
    if (!key) return;
    CGFloat w = 260, h = 220;
    CGFloat x = (key.bounds.size.width - w) / 2;
    CGFloat y = (key.bounds.size.height - h) / 2;
    win = [[UIWindow alloc] initWithFrame:CGRectMake(x, y, w, h)];
    win.windowLevel = UIWindowLevelAlert + 2;
    win.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    win.layer.cornerRadius = 12;
    win.layer.borderWidth = 1;
    win.layer.borderColor = UIColor.systemBlueColor.CGColor;
    win.hidden = NO;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 8, w, 28)];
    title.text = @"📡 MEMORY SERVER";
    title.textColor = UIColor.systemBlueColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:14];
    [win addSubview:title];
    logView = [[UITextView alloc] initWithFrame:CGRectMake(6, 42, w-12, 100)];
    logView.backgroundColor = UIColor.blackColor;
    logView.textColor = UIColor.greenColor;
    logView.font = [UIFont fontWithName:@"Courier" size:9];
    logView.editable = NO;
    logView.layer.cornerRadius = 6;
    [win addSubview:logView];
    CGFloat btnW = (w - 30) / 2;
    UIButton *startBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    startBtn.frame = CGRectMake(10, 150, btnW, 32);
    [startBtn setTitle:@"▶️ СТАРТ" forState:UIControlStateNormal];
    startBtn.backgroundColor = UIColor.systemGreenColor;
    [startBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    startBtn.layer.cornerRadius = 6;
    [startBtn addTarget:[ServerController class] action:@selector(startServer) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:startBtn];
    UIButton *stopBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    stopBtn.frame = CGRectMake(20 + btnW, 150, btnW, 32);
    [stopBtn setTitle:@"⏹️ СТОП" forState:UIControlStateNormal];
    stopBtn.backgroundColor = UIColor.systemRedColor;
    [stopBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    stopBtn.layer.cornerRadius = 6;
    [stopBtn addTarget:[ServerController class] action:@selector(stopServer) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:stopBtn];
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(w/2-35, 190, 70, 26);
    [closeBtn setTitle:@"❌ ЗАКРЫТЬ" forState:UIControlStateNormal];
    closeBtn.backgroundColor = UIColor.systemGrayColor;
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeBtn.layer.cornerRadius = 5;
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    [closeBtn addTarget:[ServerController class] action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [win addSubview:closeBtn];
    [win makeKeyAndVisible];
}

// ===== ПЛАВАЮЩАЯ КНОПКА =====
@interface FloatBtn : UIView
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, assign) CGPoint last;
@end

@implementation FloatBtn
- (instancetype)init {
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;
    self = [super initWithFrame:CGRectMake(sw-65, sh-85, 55, 55)];
    if (self) {
        self.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.7];
        self.layer.cornerRadius = 27.5;
        self.layer.borderWidth = 2;
        self.layer.borderColor = UIColor.whiteColor.CGColor;
        self.userInteractionEnabled = YES;
        UILabel *l = [[UILabel alloc] initWithFrame:self.bounds];
        l.text = @"📡";
        l.textColor = UIColor.whiteColor;
        l.textAlignment = NSTextAlignmentCenter;
        l.font = [UIFont boldSystemFontOfSize:24];
        [self addSubview:l];
        UIPanGestureRecognizer *p = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [self addGestureRecognizer:p];
        UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap)];
        [self addGestureRecognizer:t];
    }
    return self;
}
- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.superview];
    if (g.state == UIGestureRecognizerStateBegan) self.last = self.center;
    CGPoint c = CGPointMake(self.last.x + t.x, self.last.y + t.y);
    CGFloat h = 30;
    c.x = MAX(h, MIN(self.superview.bounds.size.width - h, c.x));
    c.y = MAX(h+60, MIN(self.superview.bounds.size.height - h-60, c.y));
    self.center = c;
}
- (void)tap { if (self.onTap) self.onTap(); }
@end

@interface OverlayWin : UIWindow @property (nonatomic, weak) FloatBtn *btn; @end
@implementation OverlayWin
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    if (self.btn && !self.btn.hidden && CGRectContainsPoint(self.btn.frame, p)) return self.btn;
    return nil;
}
@end

@interface App : NSObject @property (nonatomic, strong) OverlayWin *w; @end
@implementation App
- (instancetype)init {
    self = [super init];
    if (self) {
        self.w = [[OverlayWin alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.w.windowLevel = UIWindowLevelAlert + 1;
        self.w.backgroundColor = UIColor.clearColor;
        self.w.hidden = NO;
        FloatBtn *b = [[FloatBtn alloc] init];
        self.w.btn = b;
        [self.w addSubview:b];
        b.onTap = ^{
            logText = nil;
            createMenu();
        };
    }
    return self;
}
@end

static App *app = nil;

__attribute__((constructor))
static void init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        app = [[App alloc] init];
        NSLog(@"[Memory Server] Ready");
    });
}
