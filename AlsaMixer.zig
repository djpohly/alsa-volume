const AlsaMixer = @This();

const std = @import("std");
const assert = std.debug.assert;
const alsa = @import("c.zig").alsa;
const util = @import("util.zig");

handle: *alsa.snd_mixer_t,

pub fn init(name: [:0]const u8) !AlsaMixer {
    var handle_maybe: ?*alsa.snd_mixer_t = undefined;

    // "mode" parameter is unused
    try util.errorForRet(alsa.snd_mixer_open(&handle_maybe, 0));

    // On success, handle should be non-NULL
    const self: AlsaMixer = .{ .handle = handle_maybe.? };

    try self.attach(name);
    try self.selem_register();
    try self.load();

    return self;
}

pub fn deinit(self: *AlsaMixer) void {
    const ret = alsa.snd_mixer_close(self.handle);
    assert(ret == 0);
    self.handle = undefined;
}

pub fn attach(self: AlsaMixer, name: [:0]const u8) !void {
    try util.errorForRet(alsa.snd_mixer_attach(self.handle, name.ptr));
}

pub fn selem_register(self: AlsaMixer) !void {
    try util.errorForRet(alsa.snd_mixer_selem_register(self.handle, null, null));
}

pub fn load(self: AlsaMixer) !void {
    try util.errorForRet(alsa.snd_mixer_load(self.handle));
}

pub fn elements(self: AlsaMixer) Element.Iterator {
    const handle = alsa.snd_mixer_first_elem(self.handle);
    return .{
        .nextElement = if (handle) |h| Element.init(h) else null,
    };
}

pub const Element = union(enum) {
    const Iterator = struct {
        nextElement: ?Element,

        pub fn next(self: *Iterator) ?Element {
            if (self.nextElement) |elem| {
                self.nextElement = elem.nextElement();
                return elem;
            } else return null;
        }
    };

    none: void,
    playback: *alsa.snd_mixer_elem_t,
    capture: *alsa.snd_mixer_elem_t,

    pub const Channel = enum(c_int) {
        left = alsa.SND_MIXER_SCHN_FRONT_LEFT,
        right = alsa.SND_MIXER_SCHN_FRONT_RIGHT,
    };

    pub fn init(handle: *alsa.snd_mixer_elem_t) Element {
        return
            if (alsa.snd_mixer_selem_has_playback_switch(handle) != 0 and alsa.snd_mixer_selem_has_playback_volume(handle) != 0)
                .{ .playback = handle }
            else if (alsa.snd_mixer_selem_has_capture_switch(handle) != 0 and alsa.snd_mixer_selem_has_capture_volume(handle) != 0)
                .{ .capture = handle }
            else
                .none;
    }

    fn getHandle(self: Element) *alsa.snd_mixer_elem_t {
        return switch (self) {
            .none => unreachable,
            inline else => |ptr| ptr,
        };
    }

    pub fn nextElement(self: Element) ?Element {
        const handle = self.getHandle();
        const nextHandle = alsa.snd_mixer_elem_next(handle) orelse return null;
        return Element.init(nextHandle);
    }

    pub fn isMuted(self: Element) !bool {
        return try self.isChannelMuted(.left) and try self.isChannelMuted(.right);
    }

    pub fn isChannelMuted(self: Element, channel: Channel) !bool {
        const handle = self.getHandle();
        const ch = @intFromEnum(channel);
        var value: c_int = undefined;
        const ret = switch (self) {
            .none => unreachable,
            .playback => alsa.snd_mixer_selem_get_playback_switch(handle, ch, &value),
            .capture => alsa.snd_mixer_selem_get_capture_switch(handle, ch, &value),
        };
        try util.errorForRet(ret);

        return value == 0;
    }

    pub fn setChannelMuted(self: Element, channel: Channel, muted: bool) !void {
        const handle = self.getHandle();
        const ch = @intFromEnum(channel);
        const ret = switch (self) {
            .none => unreachable,
            .playback => alsa.snd_mixer_selem_set_playback_switch(handle, ch, @intFromBool(!muted)),
            .capture => alsa.snd_mixer_selem_set_capture_switch(handle, ch, @intFromBool(!muted)),
        };
        try util.errorForRet(ret);
    }

    pub fn setMuted(self: Element, muted: bool) !void {
        try self.setChannelMuted(.left, muted);
        try self.setChannelMuted(.right, muted);
    }
};
