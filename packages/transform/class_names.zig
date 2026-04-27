const std = @import("std");

const ast = @import("ast");

const NodeId = ast.NodeId;

pub fn keepClassNames(arena: *ast.Arena, alloc: std.mem.Allocator, filename: []const u8, program_id: NodeId) !void {
    const default_name = try makeDefaultClassName(filename, alloc);
    const body = arena.get(program_id).program.body;
    for (body) |stmt_id| {
        try visitStmt(arena, alloc, stmt_id, default_name);
    }
}

fn visitStmt(arena: *ast.Arena, alloc: std.mem.Allocator, stmt_id: NodeId, default_name: []const u8) anyerror!void {
    switch (arena.get(stmt_id).*) {
        .block => |b| {
            for (b.body) |child_id| try visitStmt(arena, alloc, child_id, default_name);
        },
        .var_decl => |v| {
            for (v.declarators) |decl| {
                if (decl.init) |init_id| {
                    const inferred = extractIdentName(arena, decl.id) orelse continue;
                    try assignAnonymousClassName(arena, inferred, init_id);
                }
            }
        },
        .expr_stmt => |s| try visitExpr(arena, alloc, s.expr),
        .if_stmt => |s| {
            try visitStmt(arena, alloc, s.consequent, default_name);
            if (s.alternate) |alt| try visitStmt(arena, alloc, alt, default_name);
        },
        .for_stmt => |s| {
            if (s.init) |init_id| try visitStmtOrExpr(arena, alloc, init_id, default_name);
            if (s.cond) |cond_id| try visitExpr(arena, alloc, cond_id);
            if (s.update) |update_id| try visitExpr(arena, alloc, update_id);
            try visitStmt(arena, alloc, s.body, default_name);
        },
        .while_stmt => |s| try visitStmt(arena, alloc, s.body, default_name),
        .switch_stmt => |s| {
            for (s.cases) |case| {
                for (case.body) |child_id| try visitStmt(arena, alloc, child_id, default_name);
            }
        },
        .try_stmt => |s| {
            try visitStmt(arena, alloc, s.block, default_name);
            if (s.handler) |h| try visitStmt(arena, alloc, h.body, default_name);
            if (s.finalizer) |f| try visitStmt(arena, alloc, f, default_name);
        },
        .labeled_stmt => |s| try visitStmt(arena, alloc, s.body, default_name),
        .ts_namespace => |n| {
            for (n.body) |child_id| try visitStmt(arena, alloc, child_id, default_name);
        },
        .export_decl => |exp| switch (exp.kind) {
            .default_expr => |expr_id| try assignAnonymousClassName(arena, default_name, expr_id),
            .default_decl => |decl_id| try assignAnonymousClassName(arena, default_name, decl_id),
            .decl => |decl_id| try visitStmtOrExpr(arena, alloc, decl_id, default_name),
            else => {},
        },
        else => {},
    }
}

fn visitStmtOrExpr(arena: *ast.Arena, alloc: std.mem.Allocator, node_id: NodeId, default_name: []const u8) anyerror!void {
    switch (arena.get(node_id).*) {
        .var_decl, .block, .if_stmt, .for_stmt, .while_stmt, .switch_stmt, .try_stmt, .labeled_stmt, .export_decl, .ts_namespace => try visitStmt(arena, alloc, node_id, default_name),
        else => try visitExpr(arena, alloc, node_id),
    }
}

fn visitExpr(arena: *ast.Arena, alloc: std.mem.Allocator, expr_id: NodeId) anyerror!void {
    switch (arena.get(expr_id).*) {
        .assign_expr => |a| {
            if (extractIdentName(arena, a.left)) |name| {
                try assignAnonymousClassName(arena, name, a.right);
            }
            try visitExpr(arena, alloc, a.right);
        },
        .seq_expr => |s| for (s.exprs) |child_id| try visitExpr(arena, alloc, child_id),
        .cond_expr => |c| {
            try visitExpr(arena, alloc, c.consequent);
            try visitExpr(arena, alloc, c.alternate);
        },
        .call_expr => |c| {
            try visitExpr(arena, alloc, c.callee);
            for (c.args) |arg| try visitExpr(arena, alloc, arg.expr);
        },
        .new_expr => |n| {
            try visitExpr(arena, alloc, n.callee);
            for (n.args) |arg| try visitExpr(arena, alloc, arg.expr);
        },
        .array_expr => |a| {
            for (a.elements) |maybe_child| {
                if (maybe_child) |child_id| try visitExpr(arena, alloc, child_id);
            }
        },
        .object_expr => |o| {
            for (o.props) |prop| switch (prop) {
                .kv => |kv| try visitExpr(arena, alloc, kv.value),
                .spread => |child_id| try visitExpr(arena, alloc, child_id),
                .method => {},
                .shorthand => {},
            };
        },
        else => {},
    }
}

fn assignAnonymousClassName(arena: *ast.Arena, name: []const u8, node_id: NodeId) !void {
    switch (arena.get(node_id).*) {
        .class_expr => |c| {
            if (c.id != null) return;
            arena.getMut(node_id).class_expr.id = try arena.push(.{ .ident = .{ .name = name, .span = c.span } });
        },
        .class_decl => |c| {
            if (c.id != null) return;
            arena.getMut(node_id).class_decl.id = try arena.push(.{ .ident = .{ .name = name, .span = c.span } });
        },
        else => {},
    }
}

fn extractIdentName(arena: *const ast.Arena, node_id: NodeId) ?[]const u8 {
    return switch (arena.get(node_id).*) {
        .ident => |ident| ident.name,
        else => null,
    };
}

fn makeDefaultClassName(filename: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    const base = std.fs.path.basename(filename);
    const stem = std.fs.path.stem(base);
    const raw = if (stem.len == 0) "default_class" else stem;

    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(alloc);

    for (raw, 0..) |c, i| {
        const is_valid = std.ascii.isAlphanumeric(c) or c == '_' or c == '$';
        if (is_valid) {
            if (out.items.len == 0 and std.ascii.isDigit(c)) try out.append(alloc, '_');
            try out.append(alloc, c);
            continue;
        }

        if (i == 0 and out.items.len == 0) try out.append(alloc, '_') else if (out.items.len == 0 or out.items[out.items.len - 1] == '_') continue else try out.append(alloc, '_');
    }

    if (out.items.len == 0) try out.appendSlice(alloc, "default_class");
    return out.toOwnedSlice(alloc);
}
