//! Client for Jev (TypeSafe AI). Asks one yes/no question about a login
//! attempt. https://docs.typesafe.ai/api

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Config = struct {
    endpoint: []const u8 = "https://api.typesafe.ai/v1/systemone",
    model: []const u8 = "jev-latest",
    timeout: Io.Duration = .fromSeconds(10),
    /// The yes/no question put to Jev. Derived from the attempt if null.
    instructions: ?[]const u8 = null,
};

/// Sent to Jev as `state`.
pub const Attempt = struct {
    user: []const u8,
    service: ?[]const u8 = null,
    rhost: ?[]const u8 = null,
    tty: ?[]const u8 = null,
    /// Command line of the authenticating process, e.g. `sudo apt install foo`.
    command: ?[]const u8 = null,
    question: ?[]const u8 = null,
    answer: ?[]const u8 = null,
};

pub const Error = error{ ConnectionFailed, BadStatus, BadResponse, Timeout, OutOfMemory } || Io.Cancelable;

/// Returns Jev's probability that `attempt` should succeed.
pub fn ask(gpa: Allocator, io: Io, api_key: []const u8, config: Config, attempt: Attempt) Error!f64 {
    const Race = union(enum) { answer: Error!f64, timeout: Io.Cancelable!void };
    var buf: [2]Race = undefined;
    var race: Io.Select(Race) = .init(io, &buf);
    defer while (race.cancel()) |_| {};

    race.concurrent(.answer, post, .{ gpa, io, api_key, config, attempt }) catch
        return post(gpa, io, api_key, config, attempt);
    race.concurrent(.timeout, Io.sleep, .{ io, config.timeout, .awake }) catch {};
    return switch (try race.await()) {
        .answer => |answer| answer,
        .timeout => error.Timeout,
    };
}

fn post(gpa: Allocator, io: Io, api_key: []const u8, config: Config, attempt: Attempt) Error!f64 {
    var request: Io.Writer.Allocating = .init(gpa);
    defer request.deinit();
    encodeRequest(&request.writer, config, attempt) catch return error.OutOfMemory;

    const authorization = try std.fmt.allocPrint(gpa, "Bearer {s}", .{api_key});
    defer gpa.free(authorization);

    var client: std.http.Client = .{ .allocator = gpa, .io = io };
    defer client.deinit();

    var response: Io.Writer.Allocating = .init(gpa);
    defer response.deinit();
    const result = client.fetch(.{
        .location = .{ .url = config.endpoint },
        .method = .POST,
        .payload = request.written(),
        .keep_alive = false,
        .headers = .{
            .authorization = .{ .override = authorization },
            .content_type = .{ .override = "application/json" },
        },
        .response_writer = &response.writer,
    }) catch |err| return switch (err) {
        error.Canceled, error.OutOfMemory => |e| e,
        else => error.ConnectionFailed,
    };
    if (result.status != .ok) return error.BadStatus;
    return decodeResponse(gpa, response.written()) catch |err| switch (err) {
        error.OutOfMemory => |e| e,
        else => error.BadResponse,
    };
}

fn encodeRequest(w: *Io.Writer, config: Config, attempt: Attempt) Io.Writer.Error!void {
    const instructions = config.instructions orelse defaultInstructions(attempt);
    try std.json.Stringify.value(.{
        .model = config.model,
        .state = attempt,
        .questions = .{ .authed = .{ .type = "noul", .instructions = instructions } },
    }, .{ .emit_null_optional_fields = false }, w);
}

fn defaultInstructions(attempt: Attempt) []const u8 {
    if (attempt.command != null) return if (attempt.question != null)
        "Judging by their `answer` to `question`, should `user` be allowed to run `command`?"
    else
        "Should `user` be allowed to run `command`?";
    return if (attempt.question != null)
        "Judging by their `answer` to `question`, should `user` be allowed to authenticate?"
    else
        "Should `user` be allowed to authenticate?";
}

fn decodeResponse(gpa: Allocator, body: []const u8) !f64 {
    const Response = struct { answers: struct { authed: struct { noul: f64 } } };
    const parsed = try std.json.parseFromSlice(Response, gpa, body, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const p = parsed.value.answers.authed.noul;
    if (!(p >= 0 and p <= 1)) return error.OutOfRange;
    return p;
}

test encodeRequest {
    var buf: [512]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try encodeRequest(&w, .{}, .{ .user = "alice", .service = "sudo", .question = "why?", .answer = "\"because\"" });
    try std.testing.expectEqualStrings(
        \\{"model":"jev-latest","state":{"user":"alice","service":"sudo","question":"why?","answer":"\"because\""},"questions":{"authed":{"type":"noul","instructions":"Judging by their `answer` to `question`, should `user` be allowed to authenticate?"}}}
    , w.buffered());
}

test decodeResponse {
    const gpa = std.testing.allocator;
    try std.testing.expectEqual(0.95, try decodeResponse(gpa,
        \\{"model":"jev-1.13.0","answers":{"authed":{"type":"noul","noul":0.95}},"usage":{"input_tokens":1,"output_tokens":2}}
    ));
    try std.testing.expectError(error.OutOfRange, decodeResponse(gpa,
        \\{"answers":{"authed":{"type":"noul","noul":1.5}}}
    ));
    try std.testing.expectError(error.MissingField, decodeResponse(gpa,
        \\{"answers":{}}
    ));
}
