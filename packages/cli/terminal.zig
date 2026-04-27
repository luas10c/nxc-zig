const std = @import("std");

pub fn clear(io: std.Io) !void {
    try std.Io.File.stdout().writeStreamingAll(io, "\x1b[H\x1b[J\x1b[3J");
}
