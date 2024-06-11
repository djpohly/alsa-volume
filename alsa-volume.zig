const std = @import("std");
const assert = std.debug.assert;
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const AlsaMixer = @import("AlsaMixer.zig");
const MixerElement = AlsaMixer.Element;
const alsa = @import("c.zig").alsa;
const util = @import("util.zig");

const channels = .{ alsa.SND_MIXER_SCHN_FRONT_LEFT, alsa.SND_MIXER_SCHN_FRONT_RIGHT };

const DeviceSpec = struct {
    playback: bool = false,
    capture: bool = false,

    const PLAYBACK: DeviceSpec = .{ .playback = true };
    const CAPTURE: DeviceSpec = .{ .capture = true };
    const BOTH: DeviceSpec = .{ .playback = true, .capture = true };
};

const VolumeSpec = union(enum) {
    get,
    mute,
    unmute,
    toggle,
    set: u7,
    set_raw: usize,
    change: i8,
    change_raw: isize,
};

fn get_device_spec(arg: []const u8) !DeviceSpec {
        if (arg.len == 0) return error.Usage;
        if (std.mem.startsWith(u8, "playback", arg)) return DeviceSpec.PLAYBACK;
        if (std.mem.startsWith(u8, "capture", arg)) return DeviceSpec.CAPTURE;
        if (std.mem.startsWith(u8, "both", arg)) return DeviceSpec.BOTH;
        return error.Usage;
}

fn parsePercent(str: []const u8) !u7 {
    const value = try std.fmt.parseInt(u7, str, 10);
    if (value > 100) return error.Overflow;
    return value;
}

fn get_volume_spec(arg: []const u8) !VolumeSpec {
        if (arg.len == 0) return error.Usage;
        if (std.mem.startsWith(u8, "get", arg)) return .get;
        if (std.mem.startsWith(u8, "mute", arg)) return .mute;
        if (std.mem.startsWith(u8, "unmute", arg)) return .unmute;
        if (std.mem.startsWith(u8, "toggle", arg)) return .toggle;
        if (arg[arg.len - 1] == '%') {
            const percentStr = arg[0 .. arg.len - 1];
            return switch (percentStr[0]) {
                '+' => .{ .change = parsePercent(percentStr[1..]) catch return error.Usage },
                '-' => .{ .change = -@as(i8, parsePercent(percentStr[1..]) catch return error.Usage) },
                else => .{ .set = parsePercent(percentStr) catch return error.Usage },
            };
        } else {
            return switch (arg[0]) {
                '+' => .{ .change_raw = std.fmt.parseUnsigned(isize, arg[1..], 10) catch return error.Usage },
                '-' => .{ .change_raw = -(std.fmt.parseUnsigned(isize, arg[1..], 10) catch return error.Usage) },
                else => .{ .set_raw = std.fmt.parseUnsigned(usize, arg, 10) catch return error.Usage },
            };
        }
}

pub fn real_main() !void {
    const argv = std.os.argv;
    if (argv.len > 3) return error.Usage;
    const device_spec = if (argv.len > 1) try get_device_spec(std.mem.span(argv[1])) else DeviceSpec.BOTH;
    const volume_spec = if (argv.len > 2) try get_volume_spec(std.mem.span(argv[2])) else VolumeSpec.get;

    var mixer = try AlsaMixer.init("default");
    defer mixer.deinit();

    var playback: ?MixerElement = null;
    var capture: ?MixerElement = null;

    var it = mixer.elements();
    while (it.next()) |elem| {
        switch (elem) {
            .none => {},
            .playback => playback = elem,
            .capture => capture = elem,
        }
    }

    if (device_spec.playback and playback == null) {
        return error.NoDevice;
    }
    if (device_spec.capture and capture == null) {
        return error.NoDevice;
    }
    if (device_spec.playback) {
        try do_action(volume_spec, playback.?);
    }
    if (device_spec.capture) {
        try do_action(volume_spec, capture.?);
    }
}

fn do_action(volume_spec: VolumeSpec, elem: MixerElement) !void {
    try switch (volume_spec) {
        .get => {},
        .mute => elem.setMuted(true),
        .unmute => elem.setMuted(false),
        .toggle => elem.setMuted(!try elem.isMuted()),
        .set => |volume| elem.setVolumePercent(volume),
        .set_raw => |raw| elem.setVolumeRaw(raw),
        else => std.debug.panic("not implemented", .{}),
    };

    try stdout.print("{s} {d} {s}\n", .{
        @tagName(elem),
        try elem.getVolumePercent(),
        if (try elem.isMuted()) "off" else "on",
    });
}

pub fn main() u8 {
    real_main() catch |err| switch (err) {
        error.Usage => {
            stderr.print(
                \\usage: {s} [p[layback]|c[apture]|b[oth] [g[et]|m[ute]|u[nmute]|t[oggle]|[+|-]LEVEL]
                \\   where LEVEL is either a raw value, or a percentage followed by '%'
                \\
                ,
                .{ std.os.argv[0] }) catch {};
            return 1;
        },
        else => {
            stderr.print("{!}\n", .{ err }) catch {};
            return 1;
        },
    };
    return 0;
}
