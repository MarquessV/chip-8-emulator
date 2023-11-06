const std = @import("std");
const Chip8 = @import("chip8.zig").Chip8;

const raylib = @cImport({
    @cInclude("raylib.h");
});

pub const App = struct {
    pub const DEFAULT_FG_COLOR = raylib.Color{ .r = 100, .g = 230, .b = 92, .a = 255 };
    pub const DEFAULT_BG_COLOR = raylib.Color{ .r = 40, .g = 40, .b = 40, .a = 255 };

    // Configuration
    title: [*c]const u8, // The name of the window.
    scale: c_int, // The resolution scaling factor.
    target_fps: c_int, // The target FPS for rendering.
    fg_color: raylib.Color, // The color of foreground or "on" pixels.
    bg_color: raylib.Color, // The color of background or "off" pixels.

    // Internal state
    chip8: Chip8, // The CHIP-8 emulator.
    // The width and height of the window in pixels, after scaling.
    window_width: c_int,
    window_height: c_int,

    const LOGGER = std.log.scoped(.app);

    /// Initialize a new App with the given configuration.
    pub fn new(config: struct { title: [*c]const u8, scale: c_int = 10, target_fps: c_int = 60, fg_color: raylib.Color = DEFAULT_FG_COLOR, bg_color: raylib.Color = DEFAULT_BG_COLOR }) App {
        return App{
            .title = config.title,
            .scale = config.scale,
            .window_width = 64 * config.scale,
            .window_height = 32 * config.scale,
            .target_fps = config.target_fps,
            .fg_color = config.fg_color,
            .bg_color = config.bg_color,
            .chip8 = undefined,
        };
    }

    /// Run the application. Blocks until the window is closed.
    pub fn run(self: *App, rom_path: []const u8) !void {
        raylib.InitWindow(self.window_width, self.window_height, self.title);
        defer raylib.CloseWindow();

        raylib.SetTargetFPS(self.target_fps);

        self.chip8 = try Chip8.load(rom_path);

        while (!raylib.WindowShouldClose()) {
            raylib.BeginDrawing();
            defer raylib.EndDrawing();

            try self.chip8.cycle();
            self.draw_screen(self.chip8.screen);
        }
    }

    /// Draws a CHIP-8 screen to the window using the configured scale.
    fn draw_screen(self: App, screen: [32][64]u1) void {
        raylib.ClearBackground(self.bg_color);

        for (screen, 0..) |row, row_index| {
            for (row, 0..) |pixel, col_index| {
                if (pixel == 1) {
                    const x = @as(c_int, @intCast(col_index)) * self.scale;
                    const y = @as(c_int, @intCast(row_index)) * self.scale;
                    raylib.DrawRectangle(x, y, self.scale, self.scale, self.fg_color);
                }
            }
        }
    }
};
