const Utils = @import("../utils.zig");

const r = @import("../raylib.zig").c;

const log = Utils.log;

pub const Window = struct {
    const Self = @This();

    windowWidth: u32,
    windowHeight: u32,

    scaleWidth: f32,
    scaleHeight: f32,

    title: [:0]const u8,

    const GB_SCREEN_WIDTH: u32 = 160;
    const GB_SCREEN_HEIGHT: u32 = 144;

    const BACKGROUND_COLOR: r.Color = .{
        .r = 0x18,
        .g = 0x18,
        .b = 0x18,
        .a = 0xFF,
    };

    pub fn init(width: u32, height: u32, title: [:0]const u8) Self {
        const widthScale = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(GB_SCREEN_WIDTH));
        const heightScale = @as(f32, @floatFromInt(height)) / @as(f32, @floatFromInt(GB_SCREEN_HEIGHT));

        return Self{
            .windowWidth = width,
            .windowHeight = height,
            .scaleWidth = widthScale,
            .scaleHeight = heightScale,
            .title = title,
        };
    }

    fn shouldClose(_: *const Self) bool {
        return r.WindowShouldClose();
    }

    fn render(_: *const Self) void {
        r.BeginDrawing();
        defer r.EndDrawing();

        r.ClearBackground(Self.BACKGROUND_COLOR);
    }

    pub fn run(self: *Self) void {
        r.InitWindow(@intCast(self.windowWidth), @intCast(self.windowHeight), self.title);
        log.info("Initialized window: {s} ({d}x{d})", .{ self.title, self.windowWidth, self.windowHeight });

        gameloop: while (!self.shouldClose()) {
            if (r.IsKeyPressed(r.KEY_ESCAPE)) {
                log.info("Escape key pressed, closing window", .{});
                break :gameloop;
            }

            self.render();
        }

        r.CloseWindow();
        log.info("Closed window", .{});
    }
};
