const std = @import("std");

const paths = @import("paths");

const resolveFullPath = paths.resolveFullPath;

fn mkdirP(path: [:0]const u8) void {
    _ = std.os.linux.mkdirat(std.posix.AT.FDCWD, path.ptr, 0o755);
}

fn deleteTree(path: []const u8) void {
    std.Io.Dir.cwd().deleteTree(std.testing.io, path) catch {};
}

fn writeFile(path: []const u8, content: []const u8) !void {
    const fd = try std.posix.openat(
        std.posix.AT.FDCWD,
        path,
        .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true },
        0o644,
    );
    defer _ = std.os.linux.close(fd);

    var written: usize = 0;
    while (written < content.len) {
        const n = std.os.linux.write(fd, content.ptr + written, content.len - written);
        if (n == 0) break;
        written += n;
    }
}

test "resolveFullPath resolves dot import to index.js" {
    const alloc = std.testing.allocator;

    const root = "/tmp/zts_paths_dot_import";
    mkdirP(root);
    mkdirP(root ++ "/src");
    defer deleteTree(root);

    try writeFile(root ++ "/src/index.ts", "export default 1;");

    const resolved = try resolveFullPath(".", .{
        .add_js_extension = true,
        .src_dir = root ++ "/src",
    }, alloc);
    defer if (resolved.ptr != ".".ptr) alloc.free(resolved);

    try std.testing.expectEqualStrings("./index.js", resolved);
}

test "resolveFullPath preserves suffix when resolving dot import to index.js" {
    const alloc = std.testing.allocator;

    const root = "/tmp/zts_paths_dot_import_suffix";
    mkdirP(root);
    mkdirP(root ++ "/src");
    defer deleteTree(root);

    try writeFile(root ++ "/src/index.tsx", "export default 1;");

    const resolved = try resolveFullPath(".?raw", .{
        .add_js_extension = true,
        .src_dir = root ++ "/src",
    }, alloc);
    defer if (resolved.ptr != ".?raw".ptr) alloc.free(resolved);

    try std.testing.expectEqualStrings("./index.js?raw", resolved);
}

test "resolveFullPath resolves parent directory import to parent index.js" {
    const alloc = std.testing.allocator;

    const root = "/tmp/zts_paths_parent_import";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/src/feature");
    defer deleteTree(root);

    try writeFile(root ++ "/src/index.ts", "export default 1;");

    const resolved = try resolveFullPath("..", .{
        .add_js_extension = true,
        .src_dir = root ++ "/src/feature",
    }, alloc);
    defer if (resolved.ptr != "..".ptr) alloc.free(resolved);

    try std.testing.expectEqualStrings("../index.js", resolved);
}
