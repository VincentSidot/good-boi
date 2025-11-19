const unimplemented = @import("../../../utils.zig").unimplemented;

pub const Ppu = struct {
    const Self = @This();

    pub const VRAM_START: u16 = 0x8000;
    pub const VRAM_STOP: u16 = 0x9FFF;

    const TILE_SET_START: u16 = 0x8000;
    const TILE_SET_STOP: u16 = 0x97FF;
    const TILE_MAP_START: u16 = 0x9800;
    const TILE_MAP_STOP: u16 = 0x9FFF;

    pub fn init() Self {
        return Self{};
    }

    pub fn readVRAM(self: *const Self, address: u16) u8 {
        if (address >= TILE_SET_START and address <= TILE_SET_STOP) {} else if (address >= TILE_MAP_START and address <= TILE_MAP_STOP) {} else unreachable;
    }

    pub fn writeVRAM(self: *Self, address: u16, value: u8) void {
        _ = self;
        _ = value;

        if (address >= TILE_SET_START and address <= TILE_SET_STOP) {} else if (address >= TILE_MAP_START and address <= TILE_MAP_STOP) {} else unreachable;

        unimplemented("PPU VRAM write not implemented yet");
    }
};

pub const Tile = struct {
    const Self = @This();

    const WIDTH: usize = 8;
    const HEIGHT: usize = 8;

    // 64 pixels
    pixels: [64]u8 = undefined,

    inline fn get(self: *const Self, row: usize, col: usize) u8 {
        return self.pixels[row * WIDTH + col];
    }

    inline fn set(self: *Self, row: usize, col: usize, value: u8) void {
        self.pixels[row * WIDTH + col] = value;
    }

    pub fn init() Tile {
        return Tile{
            .pixels = [_]u8{0} ** 64,
        };
    }

    pub fn read(self: *const Self, offset: u16) u8 {
        if (offset >= 16) {
            @panic("Tile read out of bounds");
        }

        const row = offset / 2;
        const bitMask: u8 = @intCast((offset % 2) + 1); // Value is 0xb01 or 0b10 -> We can use it as mask

        var value: u8 = 0;
        for (0..8) |i| {
            value <<= 1;

            if ((self.get(row, 7 - i) & bitMask) != 0) {
                value |= 1;
            }
        }

        return value;
    }

    pub fn write(self: *Self, offset: u16, value: u8) void {
        if (offset >= 16) {
            @panic("Tile write out of bounds");
        }

        const row = offset / 2;
        const bitMask: u8 = @intCast((offset % 2) + 1); // Value is 0xb01 or 0b10 -> We can use it as mask

        for (0..8) |i| {
            const valueBit = (value & (@as(u8, 1) << @as(u3, @intCast(i)))) != 0;

            var pixelValue = self.get(row, 7 - i);
            if (valueBit) {
                pixelValue |= bitMask;
            } else {
                pixelValue &= ~bitMask;
            }

            self.set(row, 7 - i, pixelValue);
        }
    }
};
