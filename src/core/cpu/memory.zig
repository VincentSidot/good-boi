pub const Memory = struct {
    pub const RAM_SIZE = 0x10000; // 64KB
    pub const STACK_START: u16 = 0xFFFE;

    memory: [RAM_SIZE]u8 = undefined,

    pub fn init() Memory {
        // Return zeroed memory
        return Memory{
            .memory = [_]u8{0} ** RAM_SIZE,
        };
    }

    pub fn readByte(self: *const Memory, address: u16) u8 {
        if (address >= RAM_SIZE) {
            @panic("Memory read out of bounds");
        }
        return self.memory[address];
    }

    pub fn writeByte(self: *Memory, address: u16, value: u8) void {
        if (address >= RAM_SIZE) {
            @panic("Memory write out of bounds");
        }
        self.memory[address] = value;
    }
};
