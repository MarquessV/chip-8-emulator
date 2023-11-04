const std = @import("std");

const raylib = @cImport({
    @cInclude("raylib.h");
});
const clap = @import("clap");

const App = @import("app.zig").App;

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help            Display this help and exit.
        \\-s, --scale <usize>   Scale the rendered output of the 64x32 CHIP-8 display. (default: 10)
        \\<str>...
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        // Report useful error and exit
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        std.debug.print("--help\n", .{});
    if (res.args.scale) |n|
        std.debug.print("--scale = {}\n", .{n});

    const scale: c_int = @intCast(res.args.scale orelse 10);

    if (scale < 1) {
        std.debug.print("error: scale must be greater than 0\n", .{});
        return error.InvalidArgument;
    }

    var app = App.new(.{ .scale = scale });
    try app.run();
}
