const std = @import("std");
const Chip8 = @import("chip8.zig").Chip8;

const raylib = @cImport({
    @cInclude("raylib.h");
});

pub const App = struct {
    pub const DEFAULT_FG_COLOR = raylib.Color{ .r = 100, .g = 230, .b = 92, .a = 255 };
    pub const DEFAULT_BG_COLOR = raylib.Color{ .r = 40, .g = 40, .b = 40, .a = 255 };
    pub const DEFAULT_KEY_MAP = [16]c_int{ raylib.KEY_X, raylib.KEY_ONE, raylib.KEY_TWO, raylib.KEY_THREE, raylib.KEY_Q, raylib.KEY_W, raylib.KEY_E, raylib.KEY_A, raylib.KEY_S, raylib.KEY_D, raylib.KEY_Z, raylib.KEY_C, raylib.KEY_FOUR, raylib.KEY_R, raylib.KEY_F, raylib.KEY_V };

    // Configuration
    title: [*c]const u8, // The name of the window.
    scale: c_int, // The resolution scaling factor.
    target_fps: c_int, // The target FPS for rendering.
    fg_color: raylib.Color, // The color of foreground or "on" pixels.
    bg_color: raylib.Color, // The color of background or "off" pixels.
    keymap: [16]c_int, // The keymap for the CHIP-8 keypad.

    // Internal state
    chip8: Chip8, // The CHIP-8 emulator.
    // The width and height of the window in pixels, after scaling.
    window_width: c_int,
    window_height: c_int,

    frequency: f32,
    time_since_last_cycle: f32,

    const LOGGER = std.log.scoped(.app);

    /// Initialize a new App with the given configuration.
    pub fn new(config: struct { title: [*c]const u8, scale: c_int = 10, target_fps: c_int = 0, frequency: f32 = 500.0, fg_color: raylib.Color = DEFAULT_FG_COLOR, bg_color: raylib.Color = DEFAULT_BG_COLOR, keymap: [16]c_int = DEFAULT_KEY_MAP }) App {
        return App{
            .title = config.title,
            .scale = config.scale,
            .window_width = 64 * config.scale,
            .window_height = 32 * config.scale,
            .target_fps = config.target_fps,
            .fg_color = config.fg_color,
            .bg_color = config.bg_color,
            .keymap = config.keymap,
            .frequency = config.frequency,
            .time_since_last_cycle = 0.0,
            .chip8 = undefined,
        };
    }

    /// Run the application. Blocks until the window is closed.
    pub fn run(self: *App, rom_path: []const u8) !void {
        raylib.InitWindow(self.window_width, self.window_height, self.title);
        defer raylib.CloseWindow();

        raylib.SetTargetFPS(self.target_fps);

        self.chip8 = try Chip8.load(rom_path, .{});

        while (!raylib.WindowShouldClose()) {
            self.time_since_last_cycle += raylib.GetFrameTime();
            raylib.BeginDrawing();
            defer raylib.EndDrawing();
            if (self.time_since_last_cycle >= (1.0 / self.frequency)) {
                self.handle_input();
                try self.chip8.cycle();
                self.time_since_last_cycle = 0.0;
                self.draw_screen(self.chip8.screen);
            }
        }
    }

    fn handle_input(self: *App) void {
        for (self.keymap, 0..) |key, i| {
            if (raylib.IsKeyDown(key)) {
                LOGGER.debug("Received press: {}, sending key press: {}", .{ key, i });
                self.chip8.keys[i] = true;
            } else if (raylib.IsKeyUp(key)) {
                self.chip8.keys[i] = false;
            }
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
