pub fn cast(comptime T: type, value: anytype) T {
    const in_type = @typeInfo(@TypeOf(value));
    const out_type = @typeInfo(T);
    if (in_type == .optional) {
        return cast(T, value.?);
    }
    return switch (out_type) {
        .int => switch (in_type) {
            .int => @intCast(value),
            .float => @intFromFloat(value),
            .bool => @intFromBool(value),
            .@"enum" => @intFromEnum(value),
            .pointer => @intFromPtr(value),
            else => invalid(@TypeOf(value), T),
        },
        .float => switch (in_type) {
            .int => @floatFromInt(value),
            .float => @floatCast(value),
            .bool => @floatFromInt(@intFromBool(value)),
            else => invalid(@TypeOf(value), T),
        },
        .bool => switch (in_type) {
            .int => value != 0,
            .float => value != 0,
            .bool => value,
            else => invalid(@TypeOf(value), T),
        },
        .@"enum" => switch (in_type) {
            .int => @enumFromInt(value),
            .@"enum" => @enumFromInt(@intFromEnum(value)),
            else => invalid(@TypeOf(value), T),
        },
        .pointer => switch (in_type) {
            .int => @ptrFromInt(value),
            .pointer => @ptrCast(value),
            else => invalid(@TypeOf(value), T),
        },
        else => invalid(@TypeOf(value), T),
    };
}

fn invalid(comptime in: type, comptime out: type) noreturn {
    @compileError("cast: " ++ @typeName(in) ++ " to " ++ @typeName(out) ++ " not supported");
}
