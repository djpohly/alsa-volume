const std = @import("std");
const E = std.posix.E;

pub fn errorForRet(ret: c_int) !void {
    if (ret < 0) switch (@as(E, @enumFromInt(-ret))) {
        .NODEV => return error.NoDevice,
        .NOMEM => return error.OutOfMemory,
        .INVAL => return error.InvalidArgument,
        else => unreachable,
    };
}
