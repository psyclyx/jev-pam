//! pam_jev.so. Asks the user an optional question, then asks Jev whether
//! to let them in.
//!
//!   question=TEXT       shown to the user; the answer is sent to Jev
//!   send_cmdline        send the calling process's command line (for sudo)
//!   color               color messages with ANSI escapes
//!   instructions=TEXT   the yes/no question put to Jev
//!   threshold=P         minimum probability (default 0.5)
//!   key_file=PATH       API key (default /etc/jev/api-key)
//!   endpoint=URL  model=NAME  timeout=SECS

const std = @import("std");
const jev = @import("jev.zig");
const pam = @import("pam.zig");

const Options = struct {
    config: jev.Config = .{},
    key_file: []const u8 = "/etc/jev/api-key",
    question: ?[]const u8 = null,
    send_cmdline: bool = false,
    color: bool = false,
    threshold: f64 = 0.5,

    fn parse(args: []const [*:0]const u8) error{BadArgument}!Options {
        var o: Options = .{};
        for (args) |arg_z| {
            const arg = std.mem.span(arg_z);
            if (std.mem.eql(u8, arg, "send_cmdline")) {
                o.send_cmdline = true;
                continue;
            }
            if (std.mem.eql(u8, arg, "color")) {
                o.color = true;
                continue;
            }
            const eq = std.mem.indexOfScalar(u8, arg, '=') orelse return error.BadArgument;
            const key = arg[0..eq];
            const value = arg[eq + 1 ..];
            if (std.mem.eql(u8, key, "question")) {
                o.question = value;
            } else if (std.mem.eql(u8, key, "instructions")) {
                o.config.instructions = value;
            } else if (std.mem.eql(u8, key, "threshold")) {
                o.threshold = std.fmt.parseFloat(f64, value) catch return error.BadArgument;
            } else if (std.mem.eql(u8, key, "key_file")) {
                o.key_file = value;
            } else if (std.mem.eql(u8, key, "endpoint")) {
                o.config.endpoint = value;
            } else if (std.mem.eql(u8, key, "model")) {
                o.config.model = value;
            } else if (std.mem.eql(u8, key, "timeout")) {
                const seconds = std.fmt.parseInt(u32, value, 10) catch return error.BadArgument;
                o.config.timeout = .fromSeconds(seconds);
            } else return error.BadArgument;
        }
        return o;
    }
};

export fn pam_sm_authenticate(pamh: *pam.Handle, flags: c_int, argc: c_int, argv: [*]const [*:0]const u8) callconv(.c) pam.Result {
    _ = flags;
    const o = Options.parse(argv[0..@intCast(argc)]) catch {
        pam.log(.err, "pam_jev: bad module arguments", .{});
        return .service_err;
    };
    const user = pamh.getUser() orelse return .service_err;

    pam.pinSelf();
    const gpa = std.heap.c_allocator;
    var threaded: std.Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var key_buf: [512]u8 = undefined;
    const key = std.Io.Dir.cwd().readFile(io, o.key_file, &key_buf) catch {
        pam.log(.err, "pam_jev: cannot read {s}", .{o.key_file});
        return .authinfo_unavail;
    };

    var cmdline_buf: [1024]u8 = undefined;
    const command = if (o.send_cmdline) readCmdline(io, &cmdline_buf) else null;

    var prompt_buf: [512]u8 = undefined;
    const answer = if (o.question) |q| answer: {
        const label = paint(o.color, "1;36", "Jev asks:");
        const prompt = std.fmt.bufPrintSentinel(&prompt_buf, "{s} {s}\n> ", .{ label, q }, 0) catch return .service_err;
        break :answer pamh.prompt(prompt) catch return .conv_err;
    } else null;
    defer if (answer) |a| std.c.free(a.ptr);

    pamh.say(.text_info, paint(o.color, "2", "Asking Jev..."));
    const p = jev.ask(gpa, io, std.mem.trim(u8, key, &std.ascii.whitespace), o.config, .{
        .user = user,
        .service = pamh.getItem(.service),
        .rhost = pamh.getItem(.rhost),
        .tty = pamh.getItem(.tty),
        .command = command,
        .question = o.question,
        .answer = answer,
    }) catch |err| {
        pam.log(.err, "pam_jev: {s}: {t}", .{ user, err });
        pamh.say(.error_msg, paint(o.color, "1;33", "Jev is not available."));
        return .authinfo_unavail;
    };
    if (p < o.threshold) {
        pam.log(.notice, "pam_jev: {s}: denied (p={d:.3})", .{ user, p });
        pamh.say(.error_msg, paint(o.color, "1;31", "Jev says no."));
        return .auth_err;
    }
    pam.log(.notice, "pam_jev: {s}: approved (p={d:.3})", .{ user, p });
    return .success;
}

fn paint(color: bool, comptime sgr: []const u8, comptime text: [:0]const u8) [:0]const u8 {
    return if (color) "\x1b[" ++ sgr ++ "m" ++ text ++ "\x1b[0m" else text;
}

/// Arguments joined by spaces. Null if unreadable.
fn readCmdline(io: std.Io, buf: []u8) ?[]const u8 {
    const raw = std.Io.Dir.cwd().readFile(io, "/proc/self/cmdline", buf) catch return null;
    const cmdline = raw[0..std.mem.trimEnd(u8, raw, "\x00").len];
    std.mem.replaceScalar(u8, cmdline, 0, ' ');
    return cmdline;
}

export fn pam_sm_setcred(_: *pam.Handle, _: c_int, _: c_int, _: [*]const [*:0]const u8) callconv(.c) pam.Result {
    return .success;
}

test "Options.parse" {
    const o = try Options.parse(&.{ "question=Why?", "send_cmdline", "color", "threshold=0.9", "timeout=3" });
    try std.testing.expectEqualStrings("Why?", o.question.?);
    try std.testing.expect(o.send_cmdline);
    try std.testing.expect(o.color);
    try std.testing.expectEqual(0.9, o.threshold);
    try std.testing.expectEqual(std.Io.Duration.fromSeconds(3), o.config.timeout);
    try std.testing.expectError(error.BadArgument, Options.parse(&.{"bogus"}));
    try std.testing.expectError(error.BadArgument, Options.parse(&.{"bogus=1"}));
}
