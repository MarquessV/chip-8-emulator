const std = @import("std");

const raylib = @cImport({
    @cInclude("raylib.h");
});

pub const App = struct {
    scale: c_int,
    window_width: c_int,
    window_height: c_int,
    target_fps: c_int,

    /// Initialize a new App with the given configuration.
    pub fn new(config: struct { scale: c_int = 10, target_fps: c_int = 60 }) App {
        return App{
            .scale = config.scale,
            .window_width = 64 * config.scale,
            .window_height = 32 * config.scale,
            .target_fps = config.target_fps,
        };
    }

    /// Run the application. Blocks until the window is closed.
    pub fn run(self: App) !void {
        raylib.InitWindow(self.window_width, self.window_height, "raylib [core] example - basic window");
        defer raylib.CloseWindow();

        raylib.SetTargetFPS(self.target_fps);

        while (!raylib.WindowShouldClose()) {
            raylib.BeginDrawing();
            raylib.ClearBackground(raylib.RAYWHITE);
            raylib.DrawText("Congrats! You created your first window!", 190, 200, 20, raylib.LIGHTGRAY);
            raylib.EndDrawing();
        }
    }
};
