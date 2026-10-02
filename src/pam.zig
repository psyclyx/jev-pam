//! Bindings for the parts of Linux-PAM that pam_jev uses.

const std = @import("std");

pub const Result = enum(c_int) {
    success = 0,
    service_err = 3,
    auth_err = 7,
    authinfo_unavail = 9,
    conv_err = 19,
    _,
};

pub const Item = enum(c_int) { service = 1, tty = 3, rhost = 4, conv = 5 };
pub const Style = enum(c_int) { prompt_echo_off = 1, prompt_echo_on = 2, error_msg = 3, text_info = 4 };

const Message = extern struct { style: Style, msg: [*:0]const u8 };
const Response = extern struct { resp: ?[*:0]u8, retcode: c_int };
const Conv = extern struct {
    conv: *const fn (c_int, [*]const *const Message, *?[*]Response, ?*anyopaque) callconv(.c) Result,
    appdata: ?*anyopaque,
};

extern "pam" fn pam_get_user(*Handle, *?[*:0]const u8, ?[*:0]const u8) Result;
extern "pam" fn pam_get_item(*const Handle, Item, *?*const anyopaque) Result;

pub const Handle = opaque {
    pub fn getUser(h: *Handle) ?[:0]const u8 {
        var user: ?[*:0]const u8 = null;
        if (pam_get_user(h, &user, null) != .success) return null;
        return std.mem.span(user orelse return null);
    }

    pub fn getItem(h: *const Handle, item: Item) ?[:0]const u8 {
        std.debug.assert(item != .conv);
        var p: ?*const anyopaque = null;
        if (pam_get_item(h, item, &p) != .success) return null;
        return std.mem.span(@as([*:0]const u8, @ptrCast(p orelse return null)));
    }

    /// Caller frees the reply with `std.c.free`.
    pub fn prompt(h: *Handle, text: [:0]const u8) error{Conv}![:0]u8 {
        return try h.converse(.prompt_echo_on, text) orelse error.Conv;
    }

    pub fn say(h: *Handle, style: Style, text: [:0]const u8) void {
        const reply = h.converse(style, text) catch return;
        if (reply) |r| std.c.free(r.ptr);
    }

    fn converse(h: *Handle, style: Style, text: [:0]const u8) error{Conv}!?[:0]u8 {
        var p: ?*const anyopaque = null;
        if (pam_get_item(h, .conv, &p) != .success) return error.Conv;
        const conv: *const Conv = @ptrCast(@alignCast(p orelse return error.Conv));
        const msg: Message = .{ .style = style, .msg = text };
        var resp: ?[*]Response = null;
        if (conv.conv(1, &.{&msg}, &resp, conv.appdata) != .success) return error.Conv;
        const r = resp orelse return null;
        defer std.c.free(r);
        return std.mem.span(r[0].resp orelse return null);
    }
};

extern "c" fn syslog(priority: c_int, fmt: [*:0]const u8, ...) void;

pub fn log(comptime level: enum(c_int) { err = 3, notice = 5 }, comptime fmt: []const u8, args: anytype) void {
    const LOG_AUTHPRIV = 10 << 3;
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrintSentinel(&buf, fmt, args, 0) catch return;
    syslog(LOG_AUTHPRIV | @intFromEnum(level), "%s", msg.ptr);
}

const DlInfo = extern struct {
    fname: ?[*:0]const u8,
    fbase: ?*anyopaque,
    sname: ?[*:0]const u8,
    saddr: ?*anyopaque,
};
extern "c" fn dladdr(addr: *const anyopaque, info: *DlInfo) c_int;

/// Prevent the module from being unmapped by dlclose. std.Io.Threaded's
/// workers are detached and may still be executing module code after
/// deinit returns. Call before starting any.
pub fn pinSelf() void {
    var info: DlInfo = undefined;
    if (dladdr(@ptrCast(&pinSelf), &info) == 0) return;
    _ = std.c.dlopen(info.fname, .{ .NOW = true, .NOLOAD = true, .NODELETE = true });
}
