//! jev: ask Jev about a login attempt from the command line.

const std = @import("std");
const jev = @import("jev.zig");

const usage =
    \\usage: jev [options] USER
    \\
    \\  --question TEXT       what the user was asked
    \\  --answer TEXT         what they said
    \\  --service NAME        PAM service
    \\  --command TEXT        command being authorized, for sudo
    \\  --instructions TEXT   the yes/no question put to Jev
    \\  --endpoint URL
    \\  --model NAME
    \\  --timeout SECS
    \\
    \\Reads the API key from TYPESAFE_API_KEY. Prints a probability.
    \\
;

const Args = struct {
    config: jev.Config,
    attempt: jev.Attempt,

    fn parse(it: *std.process.Args.Iterator) error{BadArgument}!Args {
        var config: jev.Config = .{};
        var attempt: jev.Attempt = .{ .user = "" };
        var user: ?[]const u8 = null;
        _ = it.skip();
        while (it.next()) |arg| {
            if (!std.mem.startsWith(u8, arg, "--")) {
                if (user != null) return error.BadArgument;
                user = arg;
                continue;
            }
            const value = it.next() orelse return error.BadArgument;
            const flag = arg[2..];
            if (std.mem.eql(u8, flag, "question")) {
                attempt.question = value;
            } else if (std.mem.eql(u8, flag, "answer")) {
                attempt.answer = value;
            } else if (std.mem.eql(u8, flag, "service")) {
                attempt.service = value;
            } else if (std.mem.eql(u8, flag, "command")) {
                attempt.command = value;
            } else if (std.mem.eql(u8, flag, "instructions")) {
                config.instructions = value;
            } else if (std.mem.eql(u8, flag, "endpoint")) {
                config.endpoint = value;
            } else if (std.mem.eql(u8, flag, "model")) {
                config.model = value;
            } else if (std.mem.eql(u8, flag, "timeout")) {
                const seconds = std.fmt.parseInt(u32, value, 10) catch return error.BadArgument;
                config.timeout = .fromSeconds(seconds);
            } else return error.BadArgument;
        }
        attempt.user = user orelse return error.BadArgument;
        return .{ .config = config, .attempt = attempt };
    }
};

pub fn main(init: std.process.Init) !u8 {
    var stdout_buf: [64]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buf);
    var stderr = std.Io.File.stderr().writer(init.io, &.{});

    var it = try init.minimal.args.iterateAllocator(init.arena.allocator());
    const args = Args.parse(&it) catch {
        try stderr.interface.writeAll(usage);
        return 2;
    };
    const api_key = init.environ_map.get("TYPESAFE_API_KEY") orelse {
        try stderr.interface.writeAll("jev: TYPESAFE_API_KEY is not set\n");
        return 2;
    };
    const p = jev.ask(init.gpa, init.io, api_key, args.config, args.attempt) catch |err| {
        try stderr.interface.print("jev: {t}\n", .{err});
        return 1;
    };
    try stdout.interface.print("{d:.3}\n", .{p});
    try stdout.interface.flush();
    return 0;
}

test {
    _ = jev;
}
