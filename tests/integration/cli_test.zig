const std = @import("std");

const compiler = @import("compiler");
const cli = @import("cli");

const alloc = std.testing.allocator;
const io = std.testing.io;

// ── buildOutPath ──────────────────────────────────────────────────────────────

test "buildOutPath: file at root of input dir" {
    const p = try cli.buildOutPath("src/main.ts", "src", "dist", alloc);
    defer alloc.free(p);
    try std.testing.expectEqualStrings("dist/main.js", p);
}

test "buildOutPath: nested file preserves structure" {
    const p = try cli.buildOutPath("src/foo/bar.ts", "src", "dist", alloc);
    defer alloc.free(p);
    try std.testing.expectEqualStrings("dist/foo/bar.js", p);
}

test "buildOutPath: deeply nested file" {
    const p = try cli.buildOutPath("src/a/b/c.ts", "src", "dist", alloc);
    defer alloc.free(p);
    try std.testing.expectEqualStrings("dist/a/b/c.js", p);
}

test "buildOutPath: tsx extension → .js" {
    const p = try cli.buildOutPath("src/App.tsx", "src", "dist", alloc);
    defer alloc.free(p);
    try std.testing.expectEqualStrings("dist/App.js", p);
}

test "buildOutPath: .js file stays .js" {
    const p = try cli.buildOutPath("src/util.js", "src", "dist", alloc);
    defer alloc.free(p);
    try std.testing.expectEqualStrings("dist/util.js", p);
}

test "buildOutPath: single file (src_root = file path)" {
    const p = try cli.buildOutPath("src/main.ts", "src/main.ts", "dist", alloc);
    defer alloc.free(p);
    try std.testing.expectEqualStrings("dist/main.js", p);
}

test "buildOutPath: trailing slash on src_root" {
    const p = try cli.buildOutPath("src/main.ts", "src/", "dist", alloc);
    defer alloc.free(p);
    try std.testing.expectEqualStrings("dist/main.js", p);
}

test "buildOutPath: out_dir with trailing slash" {
    const p = try cli.buildOutPath("src/main.ts", "src", "dist/", alloc);
    defer alloc.free(p);
    try std.testing.expectEqualStrings("dist/main.js", p);
}

// ── isCompilable ──────────────────────────────────────────────────────────────

test "isCompilable: .ts" {
    try std.testing.expect(cli.isCompilable("main.ts"));
}

test "isCompilable: .tsx" {
    try std.testing.expect(cli.isCompilable("App.tsx"));
}

test "isCompilable: .js" {
    try std.testing.expect(cli.isCompilable("util.js"));
}

test "isCompilable: .jsx" {
    try std.testing.expect(cli.isCompilable("App.jsx"));
}

test "isCompilable: .d.ts skipped" {
    try std.testing.expect(!cli.isCompilable("types.d.ts"));
}

test "isCompilable: .css skipped" {
    try std.testing.expect(!cli.isCompilable("style.css"));
}

test "isCompilable: no extension skipped" {
    try std.testing.expect(!cli.isCompilable("Makefile"));
}

test "isCompilable: .json skipped" {
    try std.testing.expect(!cli.isCompilable("package.json"));
}

// ── collectFiles ──────────────────────────────────────────────────────────────

test "collectFiles: finds ts and tsx files recursively" {
    const tmp = "/tmp/zts_cli_test_collect";
    mkdirP(tmp);
    defer deleteTree(tmp);

    try writeFile(tmp ++ "/a.ts", "export const a = 1;");
    try writeFile(tmp ++ "/b.tsx", "export const b = 2;");
    mkdirP(tmp ++ "/sub");
    try writeFile(tmp ++ "/sub/c.ts", "export const c = 3;");
    try writeFile(tmp ++ "/style.css", ".foo {}");

    const files = try cli.collectFiles(tmp, io, alloc);
    defer {
        for (files) |f| alloc.free(f);
        alloc.free(files);
    }

    try std.testing.expectEqual(@as(usize, 3), files.len);
    try expectContains(files, tmp ++ "/a.ts");
    try expectContains(files, tmp ++ "/b.tsx");
    try expectContains(files, tmp ++ "/sub/c.ts");
}

test "collectFiles: skips .d.ts declaration files" {
    const tmp = "/tmp/zts_cli_test_dts";
    mkdirP(tmp);
    defer deleteTree(tmp);

    try writeFile(tmp ++ "/main.ts", "export const x = 1;");
    try writeFile(tmp ++ "/types.d.ts", "export declare const x: number;");

    const files = try cli.collectFiles(tmp, io, alloc);
    defer {
        for (files) |f| alloc.free(f);
        alloc.free(files);
    }

    try std.testing.expectEqual(@as(usize, 1), files.len);
    try expectContains(files, tmp ++ "/main.ts");
}

test "collectFiles: empty directory returns empty slice" {
    const tmp = "/tmp/zts_cli_test_empty";
    mkdirP(tmp);
    defer deleteTree(tmp);

    const files = try cli.collectFiles(tmp, io, alloc);
    defer alloc.free(files);
    try std.testing.expectEqual(@as(usize, 0), files.len);
}

test "compileInput: single file compiles only that file" {
    const src_dir = "/tmp/zts_cli_single_input";
    const out_dir = "/tmp/zts_cli_single_input_out";
    mkdirP(src_dir);
    mkdirP(out_dir);
    defer deleteTree(src_dir);
    defer deleteTree(out_dir);

    try writeFile(src_dir ++ "/main.ts", "export const x: number = 1;");
    try writeFile(src_dir ++ "/ignored.css", ".foo {}");

    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript } };
    try cli.compileInput(src_dir ++ "/main.ts", null, out_dir, cfg, io, alloc);

    const out = try readFile(out_dir ++ "/main.js", alloc);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "const x = 1;") != null);
    try expectMissing(out_dir ++ "/ignored.js");
}

test "compileInput: nonexistent path returns file not found" {
    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript } };
    try std.testing.expectError(error.FileNotFound, cli.compileInput("/tmp/zts_cli_missing.ts", null, "/tmp/out", cfg, io, alloc));
}

// ── Directory compilation integration ────────────────────────────────────────

test "dir compile: single file" {
    const src_dir = "/tmp/zts_cli_dir_single";
    const out_dir = "/tmp/zts_cli_dir_single_out";
    mkdirP(src_dir);
    mkdirP(out_dir);
    defer deleteTree(src_dir);
    defer deleteTree(out_dir);

    try writeFile(src_dir ++ "/main.ts", "export const x: number = 1;");

    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript } };
    try cli.compileDirAll(src_dir, out_dir, cfg, io, alloc);

    const out = try readFile(out_dir ++ "/main.js", alloc);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "const x") != null);
}

test "compileInput: directory compiles recursively" {
    const src_dir = "/tmp/zts_cli_compile_input_dir";
    const out_dir = "/tmp/zts_cli_compile_input_dir_out";
    mkdirP(src_dir);
    mkdirP(out_dir);
    defer deleteTree(src_dir);
    defer deleteTree(out_dir);

    mkdirP(src_dir ++ "/nested");
    try writeFile(src_dir ++ "/main.ts", "export const x = 1;");
    try writeFile(src_dir ++ "/nested/helper.ts", "export const y = 2;");
    try writeFile(src_dir ++ "/skip.css", ".foo {}");

    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript } };
    try cli.compileInput(src_dir, null, out_dir, cfg, io, alloc);

    const out = try readFile(out_dir ++ "/main.js", alloc);
    defer alloc.free(out);
    const nested = try readFile(out_dir ++ "/nested/helper.js", alloc);
    defer alloc.free(nested);
    try expectMissing(out_dir ++ "/skip.js");
}

test "compileInput: empty directory succeeds without outputs" {
    const src_dir = "/tmp/zts_cli_compile_input_empty";
    const out_dir = "/tmp/zts_cli_compile_input_empty_out";
    mkdirP(src_dir);
    mkdirP(out_dir);
    defer deleteTree(src_dir);
    defer deleteTree(out_dir);

    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript } };
    try cli.compileInput(src_dir, null, out_dir, cfg, io, alloc);

    const files = try cli.collectFiles(src_dir, io, alloc);
    defer alloc.free(files);
    try std.testing.expectEqual(@as(usize, 0), files.len);
}

test "dir compile: nested files preserve structure" {
    const src_dir = "/tmp/zts_cli_dir_nested";
    const out_dir = "/tmp/zts_cli_dir_nested_out";
    mkdirP(src_dir);
    mkdirP(out_dir);
    defer deleteTree(src_dir);
    defer deleteTree(out_dir);

    mkdirP(src_dir ++ "/utils");
    try writeFile(src_dir ++ "/index.ts", "export * from './utils/helper';");
    try writeFile(src_dir ++ "/utils/helper.ts", "export const help = true;");

    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript } };
    try cli.compileDirAll(src_dir, out_dir, cfg, io, alloc);

    const idx = try readFile(out_dir ++ "/index.js", alloc);
    alloc.free(idx);
    const helper = readFile(out_dir ++ "/utils/helper.js", alloc) catch |err| {
        std.debug.print("missing utils/helper.js: {}\n", .{err});
        return err;
    };
    alloc.free(helper);
}

test "dir compile: skips .css and .d.ts" {
    const src_dir = "/tmp/zts_cli_dir_skip";
    const out_dir = "/tmp/zts_cli_dir_skip_out";
    mkdirP(src_dir);
    mkdirP(out_dir);
    defer deleteTree(src_dir);
    defer deleteTree(out_dir);

    try writeFile(src_dir ++ "/main.ts", "export const x = 1;");
    try writeFile(src_dir ++ "/types.d.ts", "export declare const x: number;");
    try writeFile(src_dir ++ "/style.css", ".foo {}");

    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript } };
    try cli.compileDirAll(src_dir, out_dir, cfg, io, alloc);

    const main_out = try readFile(out_dir ++ "/main.js", alloc);
    alloc.free(main_out);
    // types.js and style.js must not exist
    try expectMissing(out_dir ++ "/types.js");
    try expectMissing(out_dir ++ "/style.js");
}

test "dir compile: .tsx enables jsx automatically" {
    const src_dir = "/tmp/zts_cli_dir_jsx";
    const out_dir = "/tmp/zts_cli_dir_jsx_out";
    mkdirP(src_dir);
    mkdirP(out_dir);
    defer deleteTree(src_dir);
    defer deleteTree(out_dir);

    try writeFile(src_dir ++ "/App.tsx", "export function App() { return <div />; }");

    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript } };
    try cli.compileDirAll(src_dir, out_dir, cfg, io, alloc);

    const out = try readFile(out_dir ++ "/App.js", alloc);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "createElement") != null);
}

test "dir compile: source maps emit sidecar file" {
    const src_dir = "/tmp/zts_cli_dir_sourcemap";
    const out_dir = "/tmp/zts_cli_dir_sourcemap_out";
    mkdirP(src_dir);
    mkdirP(out_dir);
    defer deleteTree(src_dir);
    defer deleteTree(out_dir);

    try writeFile(src_dir ++ "/main.ts", "const x: number = 1;\nconsole.log(x);");

    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript }, .source_maps = true };
    try cli.compileDirAll(src_dir, out_dir, cfg, io, alloc);

    const out = try readFile(out_dir ++ "/main.js", alloc);
    defer alloc.free(out);
    const map = try readFile(out_dir ++ "/main.js.map", alloc);
    defer alloc.free(map);

    try std.testing.expect(std.mem.indexOf(u8, out, "sourceMappingURL=main.js.map") != null);
    try std.testing.expect(std.mem.indexOf(u8, map, "\"version\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, map, "\"mappings\":\"\"") == null);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn mkdirP(path: [:0]const u8) void {
    _ = std.os.linux.mkdirat(std.posix.AT.FDCWD, path.ptr, 0o755);
}

fn deleteTree(path: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, path) catch {};
}

fn writeFile(path: []const u8, content: []const u8) !void {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    defer _ = std.os.linux.close(fd);
    var written: usize = 0;
    while (written < content.len) {
        const n = std.os.linux.write(fd, content.ptr + written, content.len - written);
        if (n == 0) break;
        written += n;
    }
}

fn readFile(path: []const u8, a: std.mem.Allocator) ![]u8 {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0);
    defer _ = std.os.linux.close(fd);
    var buf = std.ArrayListUnmanaged(u8).empty;
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = try std.posix.read(fd, &tmp);
        if (n == 0) break;
        try buf.appendSlice(a, tmp[0..n]);
    }
    return buf.toOwnedSlice(a);
}

fn expectContains(files: []const []const u8, needle: []const u8) !void {
    for (files) |f| {
        if (std.mem.eql(u8, f, needle)) return;
    }
    std.debug.print("expected to find '{s}' in file list\n", .{needle});
    return error.TestExpectedEqual;
}

fn expectMissing(path: []const u8) !void {
    const rc = std.os.linux.syscall4(.openat, @as(usize, @bitCast(@as(isize, std.posix.AT.FDCWD))), @intFromPtr(path.ptr), 0, 0);
    const err = std.posix.errno(rc);
    if (err == .NOENT) return;
    if (err == .SUCCESS) {
        _ = std.os.linux.close(@intCast(rc));
        std.debug.print("expected '{s}' to not exist\n", .{path});
        return error.TestUnexpectedFile;
    }
}
