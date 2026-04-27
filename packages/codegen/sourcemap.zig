const std = @import("std");

const base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub const SourceMap = struct {
    mappings: std.ArrayListUnmanaged(Mapping),
    sources: std.ArrayListUnmanaged([]const u8),
    source_root: ?[]const u8 = null,
    alloc: std.mem.Allocator,

    pub const Mapping = struct {
        gen_line: u32,
        gen_col: u32,
        src_line: u32,
        src_col: u32,
        source_idx: u32,
    };

    pub fn init(alloc: std.mem.Allocator) SourceMap {
        return .{ .mappings = .empty, .sources = .empty, .alloc = alloc };
    }

    pub fn deinit(self: *SourceMap) void {
        self.mappings.deinit(self.alloc);
        self.sources.deinit(self.alloc);
    }

    pub fn addSource(self: *SourceMap, source: []const u8) !u32 {
        for (self.sources.items, 0..) |existing, i| {
            if (std.mem.eql(u8, existing, source)) return @intCast(i);
        }
        try self.sources.append(self.alloc, source);
        return @intCast(self.sources.items.len - 1);
    }

    pub fn addMapping(self: *SourceMap, mapping: Mapping) !void {
        try self.mappings.append(self.alloc, mapping);
    }

    pub fn toJsonAlloc(self: *const SourceMap) ![]const u8 {
        const sources_json = try encodeSourcesAlloc(self);
        defer self.alloc.free(sources_json);

        const mappings_json = try encodeMappingsAlloc(self);
        defer self.alloc.free(mappings_json);

        if (self.source_root) |root| {
            var root_escaped = std.ArrayListUnmanaged(u8).empty;
            defer root_escaped.deinit(self.alloc);
            try appendJsonEscaped(&root_escaped, self.alloc, root);
            return std.fmt.allocPrint(
                self.alloc,
                "{{\"version\":3,\"sourceRoot\":\"{s}\",\"sources\":[{s}],\"names\":[],\"mappings\":\"{s}\"}}",
                .{ root_escaped.items, sources_json, mappings_json },
            );
        }
        return std.fmt.allocPrint(
            self.alloc,
            "{{\"version\":3,\"sources\":[{s}],\"names\":[],\"mappings\":\"{s}\"}}",
            .{ sources_json, mappings_json },
        );
    }
};

fn encodeSourcesAlloc(sm: *const SourceMap) ![]const u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    for (sm.sources.items, 0..) |source, i| {
        if (i > 0) try out.append(sm.alloc, ',');
        try out.append(sm.alloc, '"');
        try appendJsonEscaped(&out, sm.alloc, source);
        try out.append(sm.alloc, '"');
    }
    return out.toOwnedSlice(sm.alloc);
}

fn encodeMappingsAlloc(sm: *const SourceMap) ![]const u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    const mappings = try sm.alloc.dupe(SourceMap.Mapping, sm.mappings.items);
    defer sm.alloc.free(mappings);

    std.mem.sort(SourceMap.Mapping, mappings, {}, lessThanMapping);

    var current_line: u32 = 0;
    var first_in_line = true;
    var prev_gen_col: i64 = 0;
    var prev_src_idx: i64 = 0;
    var prev_src_line: i64 = 0;
    var prev_src_col: i64 = 0;

    for (mappings) |mapping| {
        while (current_line < mapping.gen_line) : (current_line += 1) {
            try out.append(sm.alloc, ';');
            first_in_line = true;
            prev_gen_col = 0;
        }

        if (!first_in_line) try out.append(sm.alloc, ',');
        first_in_line = false;

        try appendVlq(&out, sm.alloc, @as(i64, mapping.gen_col) - prev_gen_col);
        try appendVlq(&out, sm.alloc, @as(i64, mapping.source_idx) - prev_src_idx);
        try appendVlq(&out, sm.alloc, @as(i64, mapping.src_line) - prev_src_line);
        try appendVlq(&out, sm.alloc, @as(i64, mapping.src_col) - prev_src_col);

        prev_gen_col = mapping.gen_col;
        prev_src_idx = mapping.source_idx;
        prev_src_line = mapping.src_line;
        prev_src_col = mapping.src_col;
    }

    return out.toOwnedSlice(sm.alloc);
}

fn lessThanMapping(_: void, lhs: SourceMap.Mapping, rhs: SourceMap.Mapping) bool {
    if (lhs.gen_line != rhs.gen_line) return lhs.gen_line < rhs.gen_line;
    return lhs.gen_col < rhs.gen_col;
}

fn appendJsonEscaped(out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, value: []const u8) !void {
    for (value) |c| {
        switch (c) {
            '\\' => try out.appendSlice(alloc, "\\\\"),
            '"' => try out.appendSlice(alloc, "\\\""),
            '\n' => try out.appendSlice(alloc, "\\n"),
            '\r' => try out.appendSlice(alloc, "\\r"),
            '\t' => try out.appendSlice(alloc, "\\t"),
            else => try out.append(alloc, c),
        }
    }
}

fn appendVlq(out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, value: i64) !void {
    var n = toVlqSigned(value);
    while (true) {
        var digit: u8 = @intCast(n & 31);
        n >>= 5;
        if (n != 0) digit |= 32;
        try out.append(alloc, base64_chars[digit]);
        if (n == 0) break;
    }
}

fn toVlqSigned(value: i64) u64 {
    if (value < 0) return (@as(u64, @intCast(-value)) << 1) | 1;
    return @as(u64, @intCast(value)) << 1;
}
