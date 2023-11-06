const std = @import("std");

const raylib = @cImport({
    @cInclude("raylib.h");
});
const clap = @import("clap");

const App = @import("app.zig").App;

pub fn main() !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help           Display this help and exit.
        \\-s, --scale <INT>    Scale factor to apply to the 64x32 CHIP-8 display. (default: 10)
        \\<FILE>               The CHIP-8 ROM to load and run.
    );

    const parsers = comptime .{
        .INT = clap.parsers.int(usize, 10),
        .FILE = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    if (res.args.scale) |n|
        std.log.debug("--scale = {}\n", .{n});
    for (res.positionals) |pos|
        std.log.debug("{s}\n", .{pos});

    const scale: c_int = @intCast(res.args.scale orelse 10);

    if (scale < 1) {
        std.io.getStdErr().writer().print("error: scale must be greater than 0\n", .{}) catch {};
        diag.report(std.io.getStdErr().writer(), error.InvalidArgument) catch {};
        return error.InvalidArgument;
    }

    if (res.positionals.len != 1) {
        std.io.getStdErr().writer().print("error: expected 1 positional argument, got {}\n", .{res.positionals.len}) catch {};
        diag.report(std.io.getStdErr().writer(), error.InvalidArgument) catch {};
        return error.InvalidArgument;
    }

    // TODO: Smarter path handling and title formatting.
    var title: [100]u8 = undefined;
    const result = try std.fmt.bufPrint(&title, "CHIP-8 Emulator - {s}", .{res.positionals[0]});
    title[result.len] = 0;

    var app = App.new(.{ .title = &title[0], .scale = scale });
    try app.run(res.positionals[0]);
}
