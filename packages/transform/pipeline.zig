const std = @import("std");

const ast = @import("ast");
const paths = @import("paths");
const aliases = @import("aliases");
const class_names = @import("class_names");
const modules = @import("modules");
const decorators = @import("decorators");
const json5 = @import("json5");
const jsx = @import("jsx");

const strip = @import("strip_types.zig");
const elide = @import("elide_imports.zig");

const NodeId = ast.NodeId;

pub const Target = enum { es2020, es2022, es2024, esnext };

pub const PipelineConfig = struct {
    typescript: bool = true,
    jsx: bool = false,
    jsx_cfg: jsx.JsxConfig = .{},
    src_file: []const u8 = "",
    module_strict: bool = false,
    esmodule_interop: bool = false,
    import_interop: modules.ImportInterop = .node,
    decorators: bool = false,
    legacy_decorator: bool = false,
    decorator_metadata: bool = false,
    aliases_cfg: aliases.AliasConfig = .{},
    paths_cfg: paths.FullPathsConfig = .{},
    remove_comments: bool = true,
    target: Target = .es2024,
};

pub fn run(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    cfg: PipelineConfig,
    program_id: u32,
) !void {
    if (cfg.decorators) try decorators.transformDecorators(arena, alloc, .{
        .legacy = cfg.legacy_decorator,
        .emit_metadata = cfg.decorator_metadata,
    }, program_id);
    if (cfg.typescript) try elide.elideTypeOnlyImports(arena, alloc, program_id);
    if (cfg.typescript) try strip.stripTypes(arena, alloc);
    if (cfg.target != .esnext) try strip.lowerUsingDecls(arena, alloc);
    if (cfg.jsx) try jsx.transformJsx(arena, alloc, cfg.jsx_cfg, program_id);
    try aliases.resolvePathAliases(arena, alloc, cfg.aliases_cfg);
    try paths.resolveFullPaths(arena, alloc, cfg.paths_cfg);
    if (cfg.esmodule_interop) {
        try modules.transformEsmInterop(arena, alloc, cfg.src_file, cfg.import_interop, program_id);
    }
    if (cfg.remove_comments) try removeCommentNodes(arena, alloc, program_id);
}

fn removeCommentNodes(arena: *ast.Arena, alloc: std.mem.Allocator, program_id: NodeId) !void {
    try removeCommentsFromNode(arena, alloc, program_id);
}

fn removeCommentsFromNode(arena: *ast.Arena, alloc: std.mem.Allocator, node_id: NodeId) !void {
    switch (arena.getMut(node_id).*) {
        .program => |*program| {
            var filtered = std.ArrayListUnmanaged(NodeId).empty;
            for (program.body) |stmt_id| {
                try removeCommentsFromNode(arena, alloc, stmt_id);
                if (!isCommentStatement(arena, stmt_id)) try filtered.append(alloc, stmt_id);
            }
            program.body = try filtered.toOwnedSlice(alloc);
        },
        .block => |*block| {
            var filtered = std.ArrayListUnmanaged(NodeId).empty;
            for (block.body) |stmt_id| {
                try removeCommentsFromNode(arena, alloc, stmt_id);
                if (!isCommentStatement(arena, stmt_id)) try filtered.append(alloc, stmt_id);
            }
            block.body = try filtered.toOwnedSlice(alloc);
        },
        .if_stmt => |stmt| {
            try removeCommentsFromNode(arena, alloc, stmt.consequent);
            if (stmt.alternate) |alt| try removeCommentsFromNode(arena, alloc, alt);
        },
        .for_stmt => |stmt| try removeCommentsFromNode(arena, alloc, stmt.body),
        .while_stmt => |stmt| try removeCommentsFromNode(arena, alloc, stmt.body),
        .switch_stmt => |*stmt| {
            for (stmt.cases) |*case| {
                var filtered = std.ArrayListUnmanaged(NodeId).empty;
                for (case.body) |stmt_id| {
                    try removeCommentsFromNode(arena, alloc, stmt_id);
                    if (!isCommentStatement(arena, stmt_id)) try filtered.append(alloc, stmt_id);
                }
                case.body = try filtered.toOwnedSlice(alloc);
            }
        },
        .try_stmt => |stmt| {
            try removeCommentsFromNode(arena, alloc, stmt.block);
            if (stmt.handler) |handler| try removeCommentsFromNode(arena, alloc, handler.body);
            if (stmt.finalizer) |finalizer| try removeCommentsFromNode(arena, alloc, finalizer);
        },
        .labeled_stmt => |stmt| try removeCommentsFromNode(arena, alloc, stmt.body),
        else => {},
    }
}

fn isCommentStatement(arena: *ast.Arena, node_id: NodeId) bool {
    return switch (arena.get(node_id).*) {
        .raw_js => |raw| std.mem.startsWith(u8, raw.code, "//") or std.mem.startsWith(u8, raw.code, "/*"),
        else => false,
    };
}
