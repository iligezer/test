# ===== НОВЫЕ ФУНКЦИИ ДЛЯ ВЫЗОВА ФУНКЦИЙ =====

def call_function(self, addr):
    """Вызов функции без аргументов"""
    resp = self.parent.send(f"CALL_FUNC {hex(addr)}")
    if resp and resp.startswith("RESULT"):
        return int(resp.split()[1], 16)
    return 0

def call_function_arg(self, addr, arg):
    """Вызов функции с одним аргументом"""
    resp = self.parent.send(f"CALL_FUNC_ARG {hex(addr)} {hex(arg)}")
    if resp and resp.startswith("RESULT"):
        return int(resp.split()[1], 16)
    return 0

def call_function_2args(self, addr, arg1, arg2):
    """Вызов функции с двумя аргументами"""
    resp = self.parent.send(f"CALL_FUNC_2 {hex(addr)} {hex(arg1)} {hex(arg2)}")
    if resp and resp.startswith("RESULT"):
        return int(resp.split()[1], 16)
    return 0

def call_function_3args(self, addr, arg1, arg2, arg3):
    """Вызов функции с тремя аргументами"""
    resp = self.parent.send(f"CALL_FUNC_3 {hex(addr)} {hex(arg1)} {hex(arg2)} {hex(arg3)}")
    if resp and resp.startswith("RESULT"):
        return int(resp.split()[1], 16)
    return 0

def find_symbol(self, symbol_name):
    """Поиск символа по имени"""
    resp = self.parent.send(f"FIND_SYMBOL {symbol_name}")
    if resp and resp.startswith("SYMBOL"):
        return int(resp.split()[1], 16)
    return 0

def write_int(self, addr, value):
    """Запись int значения"""
    resp = self.parent.send(f"WRITE_INT {hex(addr)} {value}")
    return resp == "OK"

def write_float(self, addr, value):
    """Запись float значения"""
    resp = self.parent.send(f"WRITE_FLOAT {hex(addr)} {value}")
    return resp == "OK"

def write_ptr(self, addr, value):
    """Запись указателя"""
    resp = self.parent.send(f"WRITE_PTR {hex(addr)} {hex(value)}")
    return resp == "OK"
