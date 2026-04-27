const std = @import("std");

const sourcemap = @import("sourcemap");

const SourceMap = sourcemap.SourceMap;

test "SourceMap emits valid sourcemap json with escaped sources and sourceRoot" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();

    sm.source_root = "src\\root";
    const source_idx = try sm.addSource("foo\\bar\".zig");
    try std.testing.expectEqual(@as(u32, 0), source_idx);

    try sm.addMapping(.{
        .gen_line = 0,
        .gen_col = 0,
        .source_idx = source_idx,
        .src_line = 0,
        .src_col = 0,
    });

    const json = try sm.toJsonAlloc();
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"version\":3,\"sourceRoot\":\"src\\\\root\",\"sources\":[\"foo\\\\bar\\\".zig\"],\"names\":[],\"mappings\":\"AAAA\"}",
        json,
    );
}

test "SourceMap sorts mappings before VLQ encoding" {
    var sm = SourceMap.init(std.testing.allocator);
    defer sm.deinit();

    const source_idx = try sm.addSource("foo.zig");

    try sm.addMapping(.{
        .gen_line = 1,
        .gen_col = 0,
        .source_idx = source_idx,
        .src_line = 1,
        .src_col = 0,
    });
    try sm.addMapping(.{
        .gen_line = 0,
        .gen_col = 3,
        .source_idx = source_idx,
        .src_line = 0,
        .src_col = 4,
    });

    const json = try sm.toJsonAlloc();
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings(
        "{\"version\":3,\"sources\":[\"foo.zig\"],\"names\":[],\"mappings\":\"GAAI;AACJ\"}",
        json,
    );
}
