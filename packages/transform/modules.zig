const std = @import("std");

const ast = @import("ast");
const lexer = @import("lexer");
const module_interop = @import("module_interop");

const Span = lexer.token.Span;
const NodeId = ast.NodeId;

pub const ModuleTarget = enum { esm };
pub const ImportInterop = module_interop.ImportInterop;
pub const transformEsmInterop = module_interop.transformEsmInterop;
pub const ensureUseStrict = module_interop.ensureUseStrict;

pub const ModuleConfig = struct {
    strict: bool = false,
    esmodule_interop: bool = false,
    import_interop: ImportInterop = .node,
};

const InteropUsage = struct {
    needs_import_default: bool = false,
    needs_import_star: bool = false,
};

fn scanInteropUsage(arena: *ast.Arena, body: []const NodeId) InteropUsage {
    var usage = InteropUsage{};
    for (body) |stmt_id| {
        const node = arena.get(stmt_id);
        if (node.* != .import_decl) continue;
        for (node.import_decl.specifiers) |spec| {
            switch (spec.kind) {
                .default => usage.needs_import_default = true,
                .namespace => usage.needs_import_star = true,
                .named => {},
            }
        }
    }
    return usage;
}

fn transformImport(arena: *ast.Arena, alloc: std.mem.Allocator, imp: ast.ImportDecl, span: Span, esmodule_interop: bool) ![]NodeId {
    var stmts = std.ArrayListUnmanaged(NodeId).empty;
    const source_val = arena.get(imp.source).str_lit.value;
    const tmp_name = try std.fmt.allocPrint(alloc, "_nxc_{s}", .{sanitizeName(source_val)});

    const require_call = try buildRequire(arena, alloc, arena.get(imp.source).str_lit.raw, span);
    const tmp_id = try arena.push(.{ .ident = .{ .name = tmp_name, .span = span } });
    try stmts.append(alloc, try arena.push(.{ .var_decl = .{
        .kind = .@"const",
        .declarators = try alloc.dupe(ast.VarDeclarator, &.{.{ .id = tmp_id, .init = require_call, .span = span }}),
        .span = span,
    } }));

    for (imp.specifiers) |spec| {
        switch (spec.kind) {
            .default => {
                const init = if (esmodule_interop)
                    try buildInteropDefault(arena, alloc, tmp_id, span)
                else
                    try buildDefaultMember(arena, tmp_id, span);
                try stmts.append(alloc, try buildConst(arena, alloc, spec.local, init, span));
            },
            .namespace => {
                const init = if (esmodule_interop)
                    try buildInteropStar(arena, alloc, tmp_id, span)
                else
                    tmp_id;
                try stmts.append(alloc, try buildConst(arena, alloc, spec.local, init, span));
            },
            .named => {
                const imported_name = if (spec.imported) |im| arena.get(im).ident.name else arena.get(spec.local).ident.name;
                const member = try arena.push(.{ .member_expr = .{
                    .object = tmp_id,
                    .prop = try arena.push(.{ .ident = .{ .name = imported_name, .span = span } }),
                    .computed = false,
                    .optional = false,
                    .span = span,
                } });
                try stmts.append(alloc, try buildConst(arena, alloc, spec.local, member, span));
            },
        }
    }

    const owned = try stmts.toOwnedSlice(alloc);
    return owned;
}

fn buildDefaultMember(arena: *ast.Arena, object: NodeId, span: Span) !NodeId {
    return arena.push(.{ .member_expr = .{
        .object = object,
        .prop = try arena.push(.{ .ident = .{ .name = "default", .span = span } }),
        .computed = false,
        .optional = false,
        .span = span,
    } });
}

fn buildInteropDefault(arena: *ast.Arena, alloc: std.mem.Allocator, object: NodeId, span: Span) !NodeId {
    const helper = try arena.push(.{ .ident = .{ .name = "__importDefault", .span = span } });
    var args = try alloc.alloc(ast.Argument, 1);
    args[0] = .{ .expr = object, .spread = false };
    const call = try arena.push(.{ .call_expr = .{ .callee = helper, .type_args = &.{}, .args = args, .optional = false, .span = span } });
    return buildDefaultMember(arena, call, span);
}

fn buildInteropStar(arena: *ast.Arena, alloc: std.mem.Allocator, object: NodeId, span: Span) !NodeId {
    const helper = try arena.push(.{ .ident = .{ .name = "__importStar", .span = span } });
    var args = try alloc.alloc(ast.Argument, 1);
    args[0] = .{ .expr = object, .spread = false };
    return arena.push(.{ .call_expr = .{ .callee = helper, .type_args = &.{}, .args = args, .optional = false, .span = span } });
}

fn transformExport(arena: *ast.Arena, alloc: std.mem.Allocator, exp: ast.ExportDecl, span: Span) ![]NodeId {
    var stmts = std.ArrayListUnmanaged(NodeId).empty;
    switch (exp.kind) {
        .decl => |decl_id| {
            try stmts.append(alloc, decl_id);
            if (extractDeclName(arena, decl_id)) |name| {
                try stmts.append(alloc, try buildExportsAssign(arena, alloc, name, name, span));
            }
        },
        .default_expr => |expr_id| {
            const lhs = try arena.push(.{ .member_expr = .{
                .object = try arena.push(.{ .ident = .{ .name = "exports", .span = span } }),
                .prop = try arena.push(.{ .ident = .{ .name = "default", .span = span } }),
                .computed = false,
                .optional = false,
                .span = span,
            } });
            const assign = try arena.push(.{ .assign_expr = .{ .op = .eq, .left = lhs, .right = expr_id, .span = span } });
            try stmts.append(alloc, try arena.push(.{ .expr_stmt = .{ .expr = assign, .span = span } }));
        },
        .default_decl => |decl_id| {
            try stmts.append(alloc, decl_id);
            try stmts.append(alloc, try buildExportsAssign(arena, alloc, "default", "default", span));
        },
        .named => |n| {
            for (n.specifiers) |spec| {
                const local_name = arena.get(spec.local).ident.name;
                const exported_name = arena.get(spec.exported).ident.name;
                try stmts.append(alloc, try buildExportsAssign(arena, alloc, exported_name, local_name, span));
            }
        },
        .all => {},
    }
    const owned = try stmts.toOwnedSlice(alloc);
    return owned;
}

fn buildRequire(arena: *ast.Arena, alloc: std.mem.Allocator, raw_source: []const u8, span: Span) !NodeId {
    const req = try arena.push(.{ .ident = .{ .name = "require", .span = span } });
    const src = try arena.push(.{ .str_lit = .{
        .raw = raw_source,
        .value = if (raw_source.len >= 2) raw_source[1 .. raw_source.len - 1] else raw_source,
        .span = span,
    } });
    var args = try alloc.alloc(ast.Argument, 1);
    args[0] = .{ .expr = src, .spread = false };
    return arena.push(.{ .call_expr = .{ .callee = req, .type_args = &.{}, .args = args, .optional = false, .span = span } });
}

fn buildConst(arena: *ast.Arena, alloc: std.mem.Allocator, id: NodeId, init: NodeId, span: Span) !NodeId {
    return arena.push(.{ .var_decl = .{
        .kind = .@"const",
        .declarators = try alloc.dupe(ast.VarDeclarator, &.{.{ .id = id, .init = init, .span = span }}),
        .span = span,
    } });
}

fn buildExportsAssign(arena: *ast.Arena, _: std.mem.Allocator, exported: []const u8, local: []const u8, span: Span) !NodeId {
    const exports_obj = try arena.push(.{ .ident = .{ .name = "exports", .span = span } });
    const prop = try arena.push(.{ .ident = .{ .name = exported, .span = span } });
    const lhs = try arena.push(.{ .member_expr = .{ .object = exports_obj, .prop = prop, .computed = false, .optional = false, .span = span } });
    const rhs = try arena.push(.{ .ident = .{ .name = local, .span = span } });
    const assign = try arena.push(.{ .assign_expr = .{ .op = .eq, .left = lhs, .right = rhs, .span = span } });
    return arena.push(.{ .expr_stmt = .{ .expr = assign, .span = span } });
}

fn extractDeclName(arena: *const ast.Arena, id: NodeId) ?[]const u8 {
    return switch (arena.get(id).*) {
        .fn_decl => |f| if (f.id) |n| arena.get(n).ident.name else null,
        .class_decl => |c| if (c.id) |n| arena.get(n).ident.name else null,
        .var_decl => |v| if (v.declarators.len > 0) arena.get(v.declarators[0].id).ident.name else null,
        else => null,
    };
}

fn sanitizeName(s: []const u8) []const u8 {
    var i = s.len;
    while (i > 0) : (i -= 1) {
        if (s[i - 1] == '/' or s[i - 1] == '@') return s[i..];
    }
    return s;
}
