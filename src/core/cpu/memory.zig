const utils = @import("../../utils.zig");

const Cart = @import("./memory/cart.zig").Cart;
const Ppu = @import("./memory/ppu.zig").Ppu;

pub const Memory = MemoryBuilder(if (utils.IS_TEST) .TESTING else .EMULATION);

const MemoryEmulation = struct {
    const Self = @This();

    pub const RAM_SIZE: u16 = 0x6000; // 32KB RAM (after cartridge ROM)
    pub const STACK_START: u16 = 0xFFFE;
    pub const PROGRAM_START: u16 = 0x0100;

    pub const ROM_START: u16 = Cart.ROM_START;
    pub const ROM_STOP: u16 = Cart.ROM_STOP;

    pub const VRAM_START: u16 = Ppu.VRAM_START;
    pub const VRAM_STOP: u16 = Ppu.VRAM_STOP;

    cart: Cart = undefined,
    ppu: Ppu = undefined,

    memory: [RAM_SIZE]u8 = undefined,

    pub fn init() Self {
        // Return zeroed memory
        var mem = Self{
            .cart = Cart.init(),
            .ppu = Ppu.init(),
            .memory = [_]u8{0} ** RAM_SIZE,
        };

        mem.write(0xFF10, 0x80);
        mem.write(0xFF11, 0xBF);
        mem.write(0xFF12, 0xF3);
        mem.write(0xFF14, 0xBF);
        mem.write(0xFF16, 0x3F);
        mem.write(0xFF19, 0xBF);
        mem.write(0xFF1A, 0x7F);
        mem.write(0xFF1B, 0xFF);
        mem.write(0xFF1C, 0x9F);
        mem.write(0xFF1E, 0xBF);
        mem.write(0xFF20, 0xFF);
        mem.write(0xFF23, 0xBF);
        mem.write(0xFF24, 0x77);
        mem.write(0xFF25, 0xF3);
        mem.write(0xFF26, 0xF1); // 0xF0 for SGB
        mem.write(0xFF40, 0x91);
        mem.write(0xFF47, 0xFC);
        mem.write(0xFF48, 0xFF);
        mem.write(0xFF49, 0xFF);

        return mem;
    }

    pub fn read(self: *const Self, address: u16) u8 {
        if (address >= ROM_START and address <= ROM_STOP) {
            return self.cart.readROM(address);
        } else if (address >= VRAM_START and address <= VRAM_STOP) {
            return self.ppu.readVRAM(address);
        } else {
            return self.readMemory(address);
        }
    }

    pub fn write(self: *Self, address: u16, value: u8) void {
        if (address >= ROM_START and address <= ROM_STOP) {
            self.cart.writeROM(address, value);
        } else if (address >= VRAM_START and address <= VRAM_STOP) {
            self.ppu.writeVRAM(address, value);
        } else {
            self.writeMemory(address, value);
        }
    }

    fn readMemory(self: *const Self, address: u16) u8 {
        const offset = address - VRAM_STOP - 1;

        if (offset <= RAM_SIZE) {
            return self.memory[offset];
        } else {
            @panic("Memory read out of bounds");
        }
    }

    fn writeMemory(self: *Self, address: u16, value: u8) void {
        const offset = address - VRAM_STOP - 1;

        if (offset <= RAM_SIZE) {
            self.memory[offset] = value;
        } else {
            @panic("Memory write out of bounds");
        }
    }
};

// End of MemoryEmulation struct

const MemoryPurpose = enum {
    TESTING,
    EMULATION,
};

fn MemoryBuilder(purpose: MemoryPurpose) type {
    if (purpose == .TESTING) {
        return struct {
            const Self = @This();

            pub const RAM_SIZE = 0x10000; // 64KB RAM for testing
            pub const STACK_START: u16 = 0xFFFE;
            pub const PROGRAM_START: u16 = 0x0100;
            pub const ROM_START: u16 = Cart.ROM_START;
            pub const ROM_STOP: u16 = Cart.ROM_STOP;
            pub const RAM_START: u16 = ROM_STOP + 1;

            memory: [RAM_SIZE]u8 = undefined,

            pub fn init() Self {
                // Return zeroed memory
                return Self{
                    .memory = [_]u8{0} ** RAM_SIZE,
                };
            }

            pub fn read(self: *const Self, address: u16) u8 {
                return self.memory[@intCast(address)];
            }

            pub fn write(self: *Self, address: u16, value: u8) void {
                self.memory[@intCast(address)] = value;
            }
        };
    }

    return MemoryEmulation;
}
