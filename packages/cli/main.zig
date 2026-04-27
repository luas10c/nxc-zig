const std = @import("std");

const compiler = @import("compiler");
const config = @import("config");
const cli = @import("cli");
pub const ansi = @import("ansi.zig");
const terminal = @import("terminal.zig");

const Io = std.Io;

const usage =
    \\nxc - ESM-first TypeScript compiler written in Zig
    \\
    \\Usage:
    \\  nxc [options] <file|dir> [file|dir ...]
    \\
    \\Options:
    \\  --out-file <path>       Output file (single file only, default: stdout)
    \\  --out-dir  <dir>        Output directory (default: dist)
    \\  --delete-out-dir        Delete out-dir before compiling
    \\  --import-interop node|none     ESM interop strategy (default: node)
    \\  --jsx      classic|auto JSX runtime
    \\  --no-ts                 Disable TypeScript stripping
    \\  --config   <path>       Config file (default: tsconfig.json)
    \\  --watch                 Watch mode (poll-based)
    \\  -h, --help              Show help
    \\
    \\tsconfig.json keys:
    \\  compilerOptions.paths            Path aliases (e.g. {"#/*": ["./*"]})
    \\
;

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;

    const args_slice = try init.minimal.args.toSlice(alloc);
    defer alloc.free(args_slice);

    var cfg = compiler.Config{};
    var input_paths = std.ArrayListUnmanaged([]const u8).empty;
    defer input_paths.deinit(alloc);
    var out_file: ?[]const u8 = null;
    var out_dir: ?[]const u8 = "dist";
    var config_path: []const u8 = "tsconfig.json";
    var watch = false;
    var delete_out_dir = false;
    var i: usize = 1;
    while (i < args_slice.len) : (i += 1) {
        const arg: []const u8 = args_slice[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try Io.File.stdout().writeStreamingAll(io, usage);
            return;
        } else if (std.mem.eql(u8, arg, "--out-file")) {
            i += 1;
            if (i >= args_slice.len) fatal("--out-file requires value");
            out_file = args_slice[i];
        } else if (std.mem.eql(u8, arg, "--out-dir")) {
            i += 1;
            if (i >= args_slice.len) fatal("--out-dir requires value");
            out_dir = args_slice[i];
        } else if (std.mem.eql(u8, arg, "--import-interop")) {
            i += 1;
            if (i >= args_slice.len) fatal("--import-interop requires value");
            if (std.mem.eql(u8, args_slice[i], "node")) {
                cfg.module.import_interop = .node;
            } else if (std.mem.eql(u8, args_slice[i], "none")) {
                cfg.module.import_interop = .none;
            } else fatal("--import-interop must be node or none");
        } else if (std.mem.eql(u8, arg, "--jsx")) {
            i += 1;
            if (i >= args_slice.len) fatal("--jsx requires value");
            cfg.jsx = true;
            cfg.transform.react.jsx_runtime = if (std.mem.eql(u8, args_slice[i], "auto") or std.mem.eql(u8, args_slice[i], "automatic"))
                .automatic
            else
                .classic;
        } else if (std.mem.eql(u8, arg, "--no-ts")) {
            cfg.parser.syntax = .ecmascript;
        } else if (std.mem.eql(u8, arg, "--config")) {
            i += 1;
            if (i >= args_slice.len) fatal("--config requires value");
            config_path = args_slice[i];
        } else if (std.mem.eql(u8, arg, "--watch")) {
            watch = true;
        } else if (std.mem.eql(u8, arg, "--delete-out-dir")) {
            delete_out_dir = true;
        } else if (arg.len > 0 and arg[0] != '-') {
            try input_paths.append(alloc, arg);
        } else {
            std.debug.print("unknown option: {s}\n", .{arg});
            std.process.exit(1);
        }
    }

    if (config.readTsConfig(config_path, alloc) catch null) |ts| {
        applyTsConfigOverrides(&cfg, ts) catch |err| switch (err) {
            error.UnsupportedTsTarget => {
                const msg = "Unsupported tsconfig target. Only es2020, es2022, es2024, and esnext are allowed.";
                const colored = ansi.red(alloc, msg) catch {
                    std.debug.print("error: {s}\n", .{msg});
                    std.process.exit(1);
                };
                defer alloc.free(colored);
                std.debug.print("{s}\n", .{colored});
                std.process.exit(1);
            },
        };
    }

    if (input_paths.items.len == 0) {
        try Io.File.stdout().writeStreamingAll(io, usage);
        return;
    }

    if (input_paths.items.len > 1 and out_file != null) {
        fatal("--out-file can only be used with a single input");
    }

    if (delete_out_dir) {
        const od = out_dir orelse "dist";
        Io.Dir.cwd().deleteTree(io, od) catch {};
    }

    for (input_paths.items) |path| {
        switch (cli.classifyInputPath(path)) {
            .directory => {
                try cli.compileInput(path, null, out_dir orelse "dist", cfg, io, alloc);
            },
            .file => {
                cli.compileInput(path, out_file, out_dir, cfg, io, alloc) catch |err| {
                    printPathError("compile", path, err);
                    return err;
                };
            },
            .missing => {
                printPathError("compile", path, error.FileNotFound);
                return error.FileNotFound;
            },
        }
    }

    if (watch) {
        try printWatching(alloc);
        try watchInputsLoop(io, input_paths.items, out_file, out_dir, cfg, alloc);
  }
}

fn compileFile(
    io: Io,
    src_file: []const u8,
    src_root: []const u8,
    out_file: ?[]const u8,
    out_dir: ?[]const u8,
    cfg: compiler.Config,
    alloc: std.mem.Allocator,
) !void {
    try cli.compileSingle(src_file, src_root, out_file, out_dir, cfg, io, alloc);
}

pub fn applyTsConfigOverrides(cfg: *compiler.Config, ts: config.TsConfig) !void {
    if (ts.compiler_options.target) |t| {
        cfg.target = try parseSupportedTarget(t);
    }
    if (ts.compiler_options.jsx) |j| {
        if (!std.ascii.eqlIgnoreCase(j, "preserve")) cfg.jsx = true;
        if (std.mem.eql(u8, j, "react-jsx") or std.mem.eql(u8, j, "react-jsxdev")) cfg.transform.react.jsx_runtime = .automatic;
    }
    if (ts.compiler_options.jsx_import_source) |src| {
        cfg.transform.react.jsx_import_source = src;
    }
    if (ts.compiler_options.experimental_decorators) |enabled| cfg.parser.decorators = enabled;
    if (ts.compiler_options.esmodule_interop) |enabled| cfg.module.es_module_interop = enabled;
    if (ts.compiler_options.source_maps) |enabled| cfg.source_maps = enabled;
    if (ts.compiler_options.paths.len > 0) cfg.paths = ts.compiler_options.paths;
    if (ts.compiler_options.base_url) |bu| cfg.base_url = bu;
    if (ts.compiler_options.strict) |strict| cfg.module.strict = strict;
}

fn parseSupportedTarget(raw: []const u8) !config.Target {
    if (std.ascii.eqlIgnoreCase(raw, "es2020")) return .es2020;
    if (std.ascii.eqlIgnoreCase(raw, "es2022")) return .es2022;
    if (std.ascii.eqlIgnoreCase(raw, "es2024")) return .es2024;
    if (std.ascii.eqlIgnoreCase(raw, "esnext")) return .esnext;
    return error.UnsupportedTsTarget;
}

test "applyTsConfigOverrides keeps esm-only module defaults" {
    var cfg = compiler.Config{};
    const defaults = compiler.Config{};
    const ts = config.TsConfig{};

    try applyTsConfigOverrides(&cfg, ts);

    try std.testing.expectEqual(defaults.module.target, cfg.module.target);
    try std.testing.expectEqual(defaults.module.import_interop, cfg.module.import_interop);
}

test "applyTsConfigOverrides preserves default module.strict when absent" {
    var cfg = compiler.Config{};
    const defaults = compiler.Config{};
    const ts = config.TsConfig{};

    try applyTsConfigOverrides(&cfg, ts);

    try std.testing.expectEqual(defaults.module.strict, cfg.module.strict);
}

test "applyTsConfigOverrides can disable module.strict explicitly" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .strict = false },
    };

    try applyTsConfigOverrides(&cfg, ts);

    try std.testing.expectEqual(false, cfg.module.strict);
}

test "applyTsConfigOverrides can enable module.strict explicitly" {
    var cfg = compiler.Config{ .module = .{ .strict = false } };
    const ts = config.TsConfig{
        .compiler_options = .{ .strict = true },
    };

    try applyTsConfigOverrides(&cfg, ts);

    try std.testing.expectEqual(true, cfg.module.strict);
}

test "applyTsConfigOverrides preserves default decorators when experimentalDecorators is absent" {
    var cfg = compiler.Config{};
    const defaults = compiler.Config{};
    const ts = config.TsConfig{};

    try applyTsConfigOverrides(&cfg, ts);

    try std.testing.expectEqual(defaults.parser.decorators, cfg.parser.decorators);
}

test "applyTsConfigOverrides can disable decorators explicitly" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .experimental_decorators = false },
    };

    try applyTsConfigOverrides(&cfg, ts);

    try std.testing.expectEqual(false, cfg.parser.decorators);
}

test "applyTsConfigOverrides can enable decorators explicitly" {
    var cfg = compiler.Config{ .parser = .{ .decorators = false } };
    const ts = config.TsConfig{
        .compiler_options = .{ .experimental_decorators = true },
    };

    try applyTsConfigOverrides(&cfg, ts);

    try std.testing.expectEqual(true, cfg.parser.decorators);
}

test "applyTsConfigOverrides maps target string" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .target = "ES2020" },
    };
    try applyTsConfigOverrides(&cfg, ts);
    try std.testing.expectEqual(config.Target.es2020, cfg.target);
}

test "applyTsConfigOverrides maps target esnext" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .target = "ESNext" },
    };
    try applyTsConfigOverrides(&cfg, ts);
    try std.testing.expectEqual(config.Target.esnext, cfg.target);
}

test "applyTsConfigOverrides rejects tsconfig target below es2020" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .target = "ES2019" },
    };
    try std.testing.expectError(error.UnsupportedTsTarget, applyTsConfigOverrides(&cfg, ts));
}

test "applyTsConfigOverrides rejects unsupported tsconfig target" {
    var cfg = compiler.Config{};
    const ts = config.TsConfig{
        .compiler_options = .{ .target = "ES2018" },
    };
    try std.testing.expectError(error.UnsupportedTsTarget, applyTsConfigOverrides(&cfg, ts));
}

fn makeDirRecursive(io: Io, path: []const u8) !void {
    Io.Dir.cwd().createDir(io, path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        error.FileNotFound => {
            if (std.fs.path.dirname(path)) |parent| {
                try makeDirRecursive(io, parent);
                try Io.Dir.cwd().createDir(io, path, .default_dir);
            } else return err;
        },
        else => return err,
    };
}

fn sleepMs(ms: u64) void {
    const ts = std.os.linux.timespec{ .sec = 0, .nsec = @intCast(ms * std.time.ns_per_ms) };
    _ = std.os.linux.nanosleep(&ts, null);
}

fn printWatching(alloc: std.mem.Allocator) !void {
    const msg = try ansi.yellow(alloc, "Watching for changes...");
    defer alloc.free(msg);
    std.debug.print("{s}\n", .{msg});
}

fn watchInputsLoop(
    io: Io,
    input_paths: []const []const u8,
    out_file: ?[]const u8,
    out_dir: ?[]const u8,
    cfg: compiler.Config,
    alloc: std.mem.Allocator,
) !void {
    var mtimes = std.StringHashMapUnmanaged(i128).empty;
    defer {
        var it = mtimes.keyIterator();
        while (it.next()) |k| alloc.free(k.*);
        mtimes.deinit(alloc);
    }

    while (true) {
        for (input_paths) |path| {
            switch (cli.classifyInputPath(path)) {
                .file => {
                    try watchOneFile(io, &mtimes, path, path, out_file, out_dir, cfg, alloc);
                },
                .directory => {
                    const od = out_dir orelse continue;
                    const files = cli.collectFiles(path, io, alloc) catch continue;
                    defer {
                        for (files) |f| alloc.free(f);
                        alloc.free(files);
                    }

                    for (files) |src_file| {
                        try watchOneFile(io, &mtimes, src_file, path, null, od, cfg, alloc);
                    }
                },
                .missing => {},
            }
        }
    sleepMs(200);
    }
}

fn watchOneFile(
    io: Io,
    mtimes: *std.StringHashMapUnmanaged(i128),
    src_file: []const u8,
    src_root: []const u8,
    out_file: ?[]const u8,
    out_dir: ?[]const u8,
    cfg: compiler.Config,
    alloc: std.mem.Allocator,
) !void {
    const stat = Io.Dir.cwd().statFile(io, src_file, .{}) catch return;
    const mtime = stat.mtime.nanoseconds;
    const prev = mtimes.get(src_file) orelse 0;
    if (mtime == prev) return;

    const key = try alloc.dupe(u8, src_file);
    try mtimes.put(alloc, key, mtime);
    if (prev == 0) return;

    var file_cfg = cfg;
    const base = std.fs.path.basename(src_file);
    if (std.mem.endsWith(u8, base, ".jsx") or std.mem.endsWith(u8, base, ".tsx")) file_cfg.jsx = true;

    try terminal.clear(io);
    try printWatching(alloc);
    compileFile(io, src_file, src_root, out_file, out_dir, file_cfg, alloc) catch |err| {
        printPathError("compile", src_file, err);
    };
}

fn watchDirLoop(
    io: Io,
    dir_path: []const u8,
    out_dir: []const u8,
    cfg: compiler.Config,
    alloc: std.mem.Allocator,
) !void {
    var mtimes = std.StringHashMapUnmanaged(i128).empty;
    defer {
        var it = mtimes.keyIterator();
        while (it.next()) |k| alloc.free(k.*);
        mtimes.deinit(alloc);
    }

    while (true) {
        const files = cli.collectFiles(dir_path, io, alloc) catch {
            sleepMs(200);
            continue;
        };
        defer {
            for (files) |f| alloc.free(f);
            alloc.free(files);
        }

        for (files) |src_file| {
            const stat = Io.Dir.cwd().statFile(io, src_file, .{}) catch continue;
            const mtime = stat.mtime.nanoseconds;
            const prev = mtimes.get(src_file) orelse 0;
            if (mtime == prev) continue;

            const key = try alloc.dupe(u8, src_file);
            try mtimes.put(alloc, key, mtime);
            if (prev == 0) continue;

            var file_cfg = cfg;
            const base = std.fs.path.basename(src_file);
            if (std.mem.endsWith(u8, base, ".jsx") or std.mem.endsWith(u8, base, ".tsx")) file_cfg.jsx = true;

            try terminal.clear(io);
            try printWatching(alloc);
            compileFile(io, src_file, dir_path, null, out_dir, file_cfg, alloc) catch |err| {
                printPathError("compile", src_file, err);
            };
        }
        sleepMs(200);
    }
}

fn printPathError(action: []const u8, path: []const u8, err: anyerror) void {
    switch (err) {
        error.IsDir => std.debug.print("error: failed to {s} '{s}': expected a file path, but received a directory\n", .{ action, path }),
        error.FileNotFound => std.debug.print("error: failed to {s} '{s}': file not found\n", .{ action, path }),
        else => std.debug.print("error: failed to {s} '{s}': {}\n", .{ action, path, err }),
    }
}

fn fatal(msg: []const u8) noreturn {
    std.debug.print("error: {s}\n", .{msg});
    std.process.exit(1);
}
