const std = @import("std");
const compiler = @import("compiler");
const Diag = @import("diagnostics");

pub const InputKind = enum { file, directory, missing };

pub fn isCompilable(name: []const u8) bool {
    if (std.mem.endsWith(u8, name, ".d.ts")) return false;
    if (std.mem.endsWith(u8, name, ".d.mts")) return false;
    if (std.mem.endsWith(u8, name, ".d.cts")) return false;
    return std.mem.endsWith(u8, name, ".ts") or
        std.mem.endsWith(u8, name, ".tsx") or
        std.mem.endsWith(u8, name, ".mts") or
        std.mem.endsWith(u8, name, ".cts") or
        std.mem.endsWith(u8, name, ".js") or
        std.mem.endsWith(u8, name, ".jsx");
}

/// Compute output path for src_file given a src_root and out_dir.
/// Strips src_root prefix from src_file, then changes extension to .js.
pub fn buildOutPath(src_file: []const u8, src_root: []const u8, out_dir: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const root = std.mem.trimEnd(u8, src_root, "/");
    const out = std.mem.trimEnd(u8, out_dir, "/");

    var rel: []const u8 = std.fs.path.basename(src_file);
    if (std.mem.startsWith(u8, src_file, root)) {
        const after = src_file[root.len..];
        const trimmed = std.mem.trimStart(u8, after, "/");
        if (trimmed.len > 0) rel = trimmed;
    }

    const dot = std.mem.lastIndexOfScalar(u8, rel, '.');
    const stem = if (dot) |d| rel[0..d] else rel;

    return std.fmt.allocPrint(alloc, "{s}/{s}.js", .{ out, stem });
}

pub fn buildMapPath(out_path: []const u8, alloc: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(alloc, "{s}.map", .{out_path});
}

pub fn appendSourceMapComment(code: []const u8, out_path: []const u8, alloc: std.mem.Allocator) ![]u8 {
    const map_path = try buildMapPath(out_path, alloc);
    defer alloc.free(map_path);
    return std.fmt.allocPrint(alloc, "{s}\n//# sourceMappingURL={s}", .{ code, std.fs.path.basename(map_path) });
}

pub fn classifyInputPath(path: []const u8) InputKind {
    var buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (path.len >= buf.len) return .missing;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;

    var stx: std.os.linux.Statx = undefined;
    const rc = std.os.linux.statx(std.posix.AT.FDCWD, &buf, 0, std.os.linux.STATX{ .TYPE = true }, &stx);
    const err = std.posix.errno(rc);
    if (err != .SUCCESS) return .missing;
    return if ((stx.mode & std.os.linux.S.IFMT) == std.os.linux.S.IFDIR) .directory else .file;
}

pub fn compileInput(path: []const u8, out_file: ?[]const u8, out_dir: ?[]const u8, cfg: compiler.Config, io: std.Io, alloc: std.mem.Allocator) !void {
    switch (classifyInputPath(path)) {
        .missing => return error.FileNotFound,
        .directory => {
            const od = out_dir orelse return error.MissingOutDir;
            try compileDirAll(path, od, cfg, io, alloc);
        },
        .file => {
            var file_cfg = cfg;
            if (std.mem.endsWith(u8, path, ".jsx") or std.mem.endsWith(u8, path, ".tsx")) file_cfg.jsx = true;
            try compileSingle(path, path, out_file, out_dir, file_cfg, io, alloc);
        },
    }
}

/// Collect all compilable files in dir_path recursively. Caller frees each string and the slice.
pub fn collectFiles(dir_path: []const u8, io: std.Io, alloc: std.mem.Allocator) ![][]const u8 {
    var result = std.ArrayListUnmanaged([]const u8).empty;
    errdefer {
        for (result.items) |f| alloc.free(f);
        result.deinit(alloc);
    }

    const fd = try std.posix.openat(std.posix.AT.FDCWD, dir_path, .{ .ACCMODE = .RDONLY, .DIRECTORY = true }, 0);
    defer _ = std.os.linux.close(fd);
    var dir = std.Io.Dir{ .handle = fd };
    var walker = try dir.walk(alloc);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!isCompilable(entry.basename)) continue;
        const full = try std.fs.path.join(alloc, &.{ dir_path, entry.path });
        try result.append(alloc, full);
    }

    return result.toOwnedSlice(alloc);
}

/// Compile all compilable files in src_dir into out_dir, preserving subdirectory structure.
pub fn compileDirAll(src_dir: []const u8, out_dir: []const u8, cfg: compiler.Config, io: std.Io, alloc: std.mem.Allocator) !void {
    const files = try collectFiles(src_dir, io, alloc);
    defer {
        for (files) |f| alloc.free(f);
        alloc.free(files);
    }

    for (files) |src_file| {
        var file_cfg = cfg;
        const base = std.fs.path.basename(src_file);
        if (std.mem.endsWith(u8, base, ".jsx") or std.mem.endsWith(u8, base, ".tsx")) {
            file_cfg.jsx = true;
        }

        const out_path = try buildOutPath(src_file, src_dir, out_dir, alloc);
        defer alloc.free(out_path);

        if (std.fs.path.dirname(out_path)) |dir| {
            makeDirAll(dir) catch {};
        }

        compileSingle(src_file, src_dir, null, out_dir, file_cfg, io, alloc) catch |err| {
            switch (err) {
                error.IsDir => std.debug.print("error compiling {s}: expected a file path, but received a directory\n", .{src_file}),
                error.FileNotFound => std.debug.print("error compiling {s}: file not found\n", .{src_file}),
                else => std.debug.print("error compiling {s}: {}\n", .{ src_file, err }),
            }
        };
    }
}

pub fn compileSingle(src_file: []const u8, src_root: []const u8, out_file: ?[]const u8, out_dir: ?[]const u8, cfg: compiler.Config, io: std.Io, alloc: std.mem.Allocator) !void {
    const result = try compiler.compileFile(src_file, cfg, io, alloc);
    defer alloc.free(result.code);
    defer if (result.map) |m| alloc.free(m);
    defer if (result.diagnostics.len > 0) alloc.free(result.diagnostics);

    Diag.printDiagnostics(result.diagnostics);

    if (out_file) |of| {
        if (result.map) |map| {
            const map_path = try buildMapPath(of, alloc);
            defer alloc.free(map_path);
            const code_with_comment = try appendSourceMapComment(result.code, of, alloc);
            defer alloc.free(code_with_comment);
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = of, .data = code_with_comment });
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = map_path, .data = map });
        } else {
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = of, .data = result.code });
        }
    } else if (out_dir) |od| {
        const out_path = try buildOutPath(src_file, src_root, od, alloc);
        defer alloc.free(out_path);
        if (std.fs.path.dirname(out_path)) |dir| {
            makeDirAll(dir) catch {};
        }
        if (result.map) |map| {
            const map_path = try buildMapPath(out_path, alloc);
            defer alloc.free(map_path);
            const code_with_comment = try appendSourceMapComment(result.code, out_path, alloc);
            defer alloc.free(code_with_comment);
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = code_with_comment });
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = map_path, .data = map });
        } else {
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = result.code });
        }
    } else {
        try std.Io.File.stdout().writeStreamingAll(io, result.code);
    }
}

fn makeDirAll(path: []const u8) !void {
    const rc = std.os.linux.mkdirat(std.posix.AT.FDCWD, &(try toCstr(path)), 0o755);
    switch (std.posix.errno(rc)) {
        .SUCCESS => {},
        .EXIST => {},
        .NOENT => {
            if (std.fs.path.dirname(path)) |parent| {
                try makeDirAll(parent);
                const rc2 = std.os.linux.mkdirat(std.posix.AT.FDCWD, &(try toCstr(path)), 0o755);
                switch (std.posix.errno(rc2)) {
                    .SUCCESS, .EXIST => {},
                    else => |e| return std.posix.unexpectedErrno(e),
                }
            } else return error.FileNotFound;
        },
        else => |e| return std.posix.unexpectedErrno(e),
    }
}

fn toCstr(s: []const u8) ![std.fs.max_path_bytes:0]u8 {
    var buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (s.len >= buf.len) return error.NameTooLong;
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    return buf;
}
