const std = @import("std");
const ansi = @import("cli_main").ansi;

const alloc = std.testing.allocator;

test "yellow wraps text with yellow ANSI code" {
    const out = try ansi.yellow(alloc, "hello");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("\x1b[33mhello\x1b[0m", out);
}

test "red wraps text with red ANSI code" {
    const out = try ansi.red(alloc, "error");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("\x1b[31merror\x1b[0m", out);
}

test "green wraps text with green ANSI code" {
    const out = try ansi.green(alloc, "ok");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("\x1b[32mok\x1b[0m", out);
}

test "blue wraps text with blue ANSI code" {
    const out = try ansi.blue(alloc, "info");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("\x1b[34minfo\x1b[0m", out);
}

test "gray wraps text with gray ANSI code" {
    const out = try ansi.gray(alloc, "dim");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("\x1b[90mdim\x1b[0m", out);
}

test "cyan wraps text with cyan ANSI code" {
    const out = try ansi.cyan(alloc, "hint");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("\x1b[96mhint\x1b[0m", out);
}

test "white wraps text with bright white ANSI code" {
    const out = try ansi.white(alloc, "msg");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("\x1b[97mmsg\x1b[0m", out);
}

test "bold wraps text with bold ANSI code" {
    const out = try ansi.bold(alloc, "strong");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("\x1b[1mstrong\x1b[0m", out);
}

test "accent wraps text with bold+cyan ANSI codes" {
    const out = try ansi.accent(alloc, "key");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("\x1b[1;36mkey\x1b[0m", out);
}

test "yellow empty string" {
    const out = try ansi.yellow(alloc, "");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("\x1b[33m\x1b[0m", out);
}

test "yellow preserves special characters" {
    const out = try ansi.yellow(alloc, "Watching for changes...");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("\x1b[33mWatching for changes...\x1b[0m", out);
}
