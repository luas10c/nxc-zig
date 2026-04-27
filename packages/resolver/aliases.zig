const std = @import("std");
const ast = @import("parser").ast;

pub const PathAlias = struct {
    /// Prefix to match, for example "#/" from "#/*", or "#/config" for exact aliases.
    prefix: []const u8,
    /// Replacement prefix, for example "./src/" from "./src/*".
    replacement: []const u8,
    /// True when the original alias pattern has a wildcard.
    is_wildcard: bool = true,
};

pub const AliasConfig = struct {
    aliases: []const PathAlias = &.{},
    /// Source file path, for example "src/app.ts". Used to make alias results relative to this file.
    src_file: []const u8 = "",
};

/// Resolve a specifier using a list of normalized aliases.
/// Returns null when no alias matches.
pub fn resolvePathAlias(
    specifier: []const u8,
    cfg: AliasConfig,
    alloc: std.mem.Allocator,
) !?[]const u8 {
    for (cfg.aliases) |alias| {
        if (alias.is_wildcard) {
            if (!std.mem.startsWith(u8, specifier, alias.prefix)) continue;

            const rest = specifier[alias.prefix.len..];
            const raw_result = try std.fmt.allocPrint(alloc, "{s}{s}", .{ alias.replacement, rest });
            const normalized = try ensureRelativePrefix(raw_result, alloc);
            return try makeRelativeToSrcFile(normalized, cfg.src_file, alloc);
        }

        if (!std.mem.eql(u8, specifier, alias.prefix)) continue;

        const normalized = try ensureRelativePrefix(alias.replacement, alloc);
        return try makeRelativeToSrcFile(normalized, cfg.src_file, alloc);
    }

    return null;
}

/// Transform import/export/dynamic-import string literals by resolving only aliases.
pub fn resolvePathAliases(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    cfg: AliasConfig,
) !void {
    if (cfg.aliases.len == 0) return;

    const nodes = arena.nodes.items;
    for (0..nodes.len) |i| {
        switch (nodes[i]) {
            .import_decl => |n| try rewriteSourceAlias(arena, alloc, cfg, n.source),
            .export_decl => |n| switch (n.kind) {
                .named => |e| if (e.source) |s| try rewriteSourceAlias(arena, alloc, cfg, s),
                .all => |e| try rewriteSourceAlias(arena, alloc, cfg, e.source),
                else => {},
            },
            .import_call => |n| try rewriteSourceAlias(arena, alloc, cfg, n.source),
            else => {},
        }
    }
}

/// Resolve a module specifier against tsconfig "paths".
/// Returns null if no alias matches, so the caller can keep the original specifier.
pub fn resolveTsconfigPathAlias(
    specifier: []const u8,
    base_url: ?[]const u8,
    paths: std.StringHashMapUnmanaged([]const []const u8),
    alloc: std.mem.Allocator,
) !?[]const u8 {
    var it = paths.iterator();
    while (it.next()) |entry| {
        const pattern = entry.key_ptr.*;
        if (!matchPattern(pattern, specifier)) continue;

        const targets = entry.value_ptr.*;
        if (targets.len == 0) return null;

        const target = targets[0];
        const mapped = if (std.mem.indexOf(u8, pattern, "*")) |star| blk: {
            const prefix = pattern[0..star];
            const suffix_pattern = pattern[star + 1 ..];
            const captured_end = specifier.len - suffix_pattern.len;
            const captured = specifier[prefix.len..captured_end];
            break :blk try std.mem.replaceOwned(u8, alloc, target, "*", captured);
        } else try alloc.dupe(u8, target);

        if (base_url) |base| return try std.fs.path.join(alloc, &.{ base, mapped });
        return mapped;
    }

    return null;
}

fn rewriteSourceAlias(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    cfg: AliasConfig,
    source_id: ast.NodeId,
) !void {
    const node = arena.getMut(source_id);
    const lit = switch (node.*) {
        .str_lit => |*s| s,
        else => return,
    };

    const resolved = try resolvePathAlias(lit.value, cfg, alloc) orelse return;
    if (std.mem.eql(u8, resolved, lit.value)) return;

    lit.value = resolved;
    lit.raw = try std.fmt.allocPrint(alloc, "\"{s}\"", .{resolved});
}

fn ensureRelativePrefix(path: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    if (std.mem.startsWith(u8, path, "./") or
        std.mem.startsWith(u8, path, "../") or
        std.mem.startsWith(u8, path, "/"))
    {
        return path;
    }

    return try std.fmt.allocPrint(alloc, "./{s}", .{path});
}

/// Given a path produced by alias substitution, relative to project root,
/// return the path relative to the source file directory.
fn makeRelativeToSrcFile(path: []const u8, src_file: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    if (src_file.len == 0) return path;
    if (!std.mem.startsWith(u8, path, "./") and !std.mem.startsWith(u8, path, "../")) return path;

    const src_dir = std.fs.path.dirname(src_file) orelse return path;
    if (src_dir.len == 0 or std.mem.eql(u8, src_dir, ".")) return path;

    const to_normalized = if (std.mem.startsWith(u8, path, "./")) path[2..] else path;
    return relPath(src_dir, to_normalized, alloc);
}

fn relPath(from_dir: []const u8, to: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    var from_buf: [256][]const u8 = undefined;
    var to_buf: [256][]const u8 = undefined;
    const from_parts = splitPath(from_dir, &from_buf);
    const to_parts = splitPath(to, &to_buf);

    var common: usize = 0;
    while (common < from_parts.len and common < to_parts.len and
        std.mem.eql(u8, from_parts[common], to_parts[common]))
    {
        common += 1;
    }

    const ups = from_parts.len - common;
    const remaining = to_parts[common..];

    var result = std.ArrayListUnmanaged(u8).empty;
    if (ups > 0) {
        for (0..ups) |_| try result.appendSlice(alloc, "../");
    } else {
        try result.appendSlice(alloc, "./");
    }

    for (remaining, 0..) |part, i| {
        try result.appendSlice(alloc, part);
        if (i + 1 < remaining.len) try result.append(alloc, '/');
    }

    return result.toOwnedSlice(alloc);
}

fn splitPath(path: []const u8, buf: [][]const u8) [][]const u8 {
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        if (count >= buf.len) break;
        buf[count] = part;
        count += 1;
    }
    return buf[0..count];
}

fn matchPattern(pattern: []const u8, specifier: []const u8) bool {
    const star = std.mem.indexOf(u8, pattern, "*") orelse {
        return std.mem.eql(u8, pattern, specifier);
    };

    const prefix = pattern[0..star];
    const suffix = pattern[star + 1 ..];
    if (!std.mem.startsWith(u8, specifier, prefix)) return false;
    if (!std.mem.endsWith(u8, specifier, suffix)) return false;
    return specifier.len >= prefix.len + suffix.len;
}
