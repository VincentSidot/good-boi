const unimplemented = @import("../../utils.zig").unimplemented;

pub const Cart = struct {
    pub const ROM_START: u16 = 0x0000;
    pub const ROM_STOP: u16 = 0x7FFF;

    rom: []const u8 = undefined,

    pub fn init() Cart {
        return Cart{};
    }

    pub fn loadRom(self: *Cart, data: []const u8) void {
        self.rom = data;
    }

    pub fn read(self: *const Cart, address: u16) u8 {
        return self.rom[@intCast(address)];
    }

    pub fn write(self: *Cart, address: u16, value: u8) void {
        _ = self;
        _ = address;
        _ = value;

        unimplemented("Writing to cartridge ROM is not supported");
    }
};
