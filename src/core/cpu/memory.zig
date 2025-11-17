const Cart = @import("../cpu/cart.zig").Cart;

pub const Memory = struct {
    pub const RAM_SIZE: u16 = 0x8000; // 32KB RAM (after cartridge ROM)
    pub const STACK_START: u16 = 0xFFFE;
    pub const PROGRAM_START: u16 = 0x0100;
    pub const ROM_START: u16 = Cart.ROM_START;
    pub const ROM_STOP: u16 = Cart.ROM_STOP;
    pub const RAM_START: u16 = ROM_STOP + 1;

    cart: Cart = undefined,
    memory: [RAM_SIZE]u8 = undefined,

    pub fn init() Memory {
        // Return zeroed memory
        var mem = Memory{
            .cart = Cart.init(),
            .memory = [_]u8{0} ** RAM_SIZE,
        };

        mem.writeByte(0xFF10, 0x80);
        mem.writeByte(0xFF11, 0xBF);
        mem.writeByte(0xFF12, 0xF3);
        mem.writeByte(0xFF14, 0xBF);
        mem.writeByte(0xFF16, 0x3F);
        mem.writeByte(0xFF19, 0xBF);
        mem.writeByte(0xFF1A, 0x7F);
        mem.writeByte(0xFF1B, 0xFF);
        mem.writeByte(0xFF1C, 0x9F);
        mem.writeByte(0xFF1E, 0xBF);
        mem.writeByte(0xFF20, 0xFF);
        mem.writeByte(0xFF23, 0xBF);
        mem.writeByte(0xFF24, 0x77);
        mem.writeByte(0xFF25, 0xF3);
        mem.writeByte(0xFF26, 0xF1); // 0xF0 for SGB
        mem.writeByte(0xFF40, 0x91);
        mem.writeByte(0xFF47, 0xFC);
        mem.writeByte(0xFF48, 0xFF);
        mem.writeByte(0xFF49, 0xFF);

        return mem;
    }

    pub fn readByte(self: *const Memory, address: u16) u8 {
        if (address >= ROM_START and address <= ROM_STOP) {
            return self.cart.read(address);
        } else {
            const offset = address - ROM_STOP - 1;

            if (offset <= RAM_SIZE) {
                return self.memory[offset];
            } else {
                @panic("Memory read out of bounds");
            }
        }
    }

    pub fn writeByte(self: *Memory, address: u16, value: u8) void {
        if (address >= ROM_START and address <= ROM_STOP) {
            self.cart.write(address, value);
        } else {
            const offset = address - ROM_STOP - 1;

            if (offset <= RAM_SIZE) {
                self.memory[offset] = value;
            } else {
                @panic("Memory write out of bounds");
            }
        }
    }
};
