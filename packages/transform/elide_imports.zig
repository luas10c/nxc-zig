const std = @import("std");
const ast = @import("parser").ast;

/// Mark import specifiers as type-only when their local binding is never used
/// in a value position. Must run BEFORE stripTypes so that stripTypes removes them.
pub fn elideTypeOnlyImports(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    program_id: ast.NodeId,
) !void {
    var refs = std.StringHashMapUnmanaged(void).empty;
    defer refs.deinit(alloc);

    try collectValueRefs(arena, alloc, program_id, &refs);

    for (0..arena.nodes.items.len) |i| {
        switch (arena.nodes.items[i]) {
            .import_decl => {
                const imp = &arena.getMut(@intCast(i)).import_decl;
                if (imp.is_type_only) continue;
                if (imp.attributes.len > 0) continue;

                for (imp.specifiers, 0..) |spec, j| {
                    if (spec.is_type_only) continue;
                    const name = identName(arena, spec.local);
                    if (name.len > 0 and !refs.contains(name)) {
                        imp.specifiers[j].is_type_only = true;
                    }
                }
            },
            else => {},
        }
    }
}

fn identName(arena: *ast.Arena, node_id: ast.NodeId) []const u8 {
    return switch (arena.get(node_id).*) {
        .ident => |id| id.name,
        else => "",
    };
}

// Walk the AST from the root collecting identifiers used in value positions.
// Skips all TypeScript type-only subtrees so only runtime references are counted.
fn collectValueRefs(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    node_id: ast.NodeId,
    refs: *std.StringHashMapUnmanaged(void),
) std.mem.Allocator.Error!void {
    switch (arena.get(node_id).*) {
        // ── Value leaf ────────────────────────────────────────────────────────
        .ident => |id| try refs.put(alloc, id.name, {}),

        // ── Pure type nodes — skip entirely ───────────────────────────────────
        .ts_type_annotation,
        .ts_type_ref,
        .ts_qualified_name,
        .ts_union,
        .ts_intersection,
        .ts_array_type,
        .ts_tuple,
        .ts_keyword,
        .ts_interface,
        => {},

        .ts_type_alias => {},

        // ── TS wrappers — walk value expr only ────────────────────────────────
        .ts_as_expr => |e| try collectValueRefs(arena, alloc, e.expr, refs),
        .ts_satisfies => |e| try collectValueRefs(arena, alloc, e.expr, refs),
        .ts_instantiation => |e| try collectValueRefs(arena, alloc, e.expr, refs),
        .ts_non_null => |e| try collectValueRefs(arena, alloc, e.expr, refs),
        .ts_type_assert => |e| try collectValueRefs(arena, alloc, e.expr, refs),

        // ── Program / block ───────────────────────────────────────────────────
        .program => |p| for (p.body) |s| try collectValueRefs(arena, alloc, s, refs),
        .block => |b| for (b.body) |s| try collectValueRefs(arena, alloc, s, refs),

        // ── Declarations ──────────────────────────────────────────────────────
        .var_decl => |v| for (v.declarators) |d| {
            try collectValueRefs(arena, alloc, d.id, refs);
            if (d.init) |init| try collectValueRefs(arena, alloc, init, refs);
        },
        .fn_decl => |f| {
            if (f.id) |id| try collectValueRefs(arena, alloc, id, refs);
            // skip type_params — type positions
            for (f.params) |p| try collectValueRefs(arena, alloc, p, refs);
            // skip param_types and return_type — type positions
            try collectValueRefs(arena, alloc, f.body, refs);
        },
        .class_decl => |c| {
            if (c.id) |id| try collectValueRefs(arena, alloc, id, refs);
            // skip type_params — type positions
            if (c.super_class) |s| try collectValueRefs(arena, alloc, s, refs);
            for (c.decorators) |d| try collectValueRefs(arena, alloc, d, refs);
            for (c.body) |m| try collectMember(arena, alloc, m, refs);
        },
        .ts_namespace => |n| {
            try collectValueRefs(arena, alloc, n.id, refs);
            for (n.body) |stmt| try collectValueRefs(arena, alloc, stmt, refs);
        },

        // ── Import / export ───────────────────────────────────────────────────
        // Skip import_decl — we're finding usages, not declarations.
        .import_decl => {},
        .export_decl => |e| switch (e.kind) {
            // Re-exports with a source don't reference local bindings.
            .named => |n| if (n.source == null) {
                for (n.specifiers) |s| {
                    if (!s.is_type_only) try collectValueRefs(arena, alloc, s.local, refs);
                }
            },
            .default_expr => |x| try collectValueRefs(arena, alloc, x, refs),
            .default_decl => |x| try collectValueRefs(arena, alloc, x, refs),
            .decl => |x| try collectValueRefs(arena, alloc, x, refs),
            .all => {},
        },

        // ── Statements ────────────────────────────────────────────────────────
        .expr_stmt => |s| try collectValueRefs(arena, alloc, s.expr, refs),
        .return_stmt => |s| if (s.argument) |a| try collectValueRefs(arena, alloc, a, refs),
        .throw_stmt => |s| try collectValueRefs(arena, alloc, s.argument, refs),
        .labeled_stmt => |s| try collectValueRefs(arena, alloc, s.body, refs),
        .break_continue => {},
        .debugger_stmt => {},
        .empty_stmt => {},
        .if_stmt => |s| {
            try collectValueRefs(arena, alloc, s.cond, refs);
            try collectValueRefs(arena, alloc, s.consequent, refs);
            if (s.alternate) |alt| try collectValueRefs(arena, alloc, alt, refs);
        },
        .for_stmt => |s| {
            if (s.init) |x| try collectValueRefs(arena, alloc, x, refs);
            if (s.cond) |x| try collectValueRefs(arena, alloc, x, refs);
            if (s.update) |x| try collectValueRefs(arena, alloc, x, refs);
            try collectValueRefs(arena, alloc, s.body, refs);
        },
        .while_stmt => |s| {
            try collectValueRefs(arena, alloc, s.cond, refs);
            try collectValueRefs(arena, alloc, s.body, refs);
        },
        .switch_stmt => |s| {
            try collectValueRefs(arena, alloc, s.disc, refs);
            for (s.cases) |case| {
                if (case.cond) |t| try collectValueRefs(arena, alloc, t, refs);
                for (case.body) |stmt| try collectValueRefs(arena, alloc, stmt, refs);
            }
        },
        .try_stmt => |s| {
            try collectValueRefs(arena, alloc, s.block, refs);
            if (s.handler) |h| {
                if (h.param) |p| try collectValueRefs(arena, alloc, p, refs);
                try collectValueRefs(arena, alloc, h.body, refs);
            }
            if (s.finalizer) |f| try collectValueRefs(arena, alloc, f, refs);
        },

        // ── Expressions ───────────────────────────────────────────────────────
        .binary_expr => |e| {
            try collectValueRefs(arena, alloc, e.left, refs);
            try collectValueRefs(arena, alloc, e.right, refs);
        },
        .unary_expr => |e| try collectValueRefs(arena, alloc, e.argument, refs),
        .update_expr => |e| try collectValueRefs(arena, alloc, e.argument, refs),
        .assign_expr => |e| {
            try collectValueRefs(arena, alloc, e.left, refs);
            try collectValueRefs(arena, alloc, e.right, refs);
        },
        .call_expr => |e| {
            try collectValueRefs(arena, alloc, e.callee, refs);
            // skip type_args — type positions
            for (e.args) |a| try collectValueRefs(arena, alloc, a.expr, refs);
        },
        .member_expr => |e| {
            try collectValueRefs(arena, alloc, e.object, refs);
            // only recurse into computed prop — static prop names aren't bindings
            if (e.computed) try collectValueRefs(arena, alloc, e.prop, refs);
        },
        .new_expr => |e| {
            try collectValueRefs(arena, alloc, e.callee, refs);
            // skip type_args
            for (e.args) |a| try collectValueRefs(arena, alloc, a.expr, refs);
        },
        .seq_expr => |e| for (e.exprs) |x| try collectValueRefs(arena, alloc, x, refs),
        .cond_expr => |e| {
            // Decorator metadata emits:
            // typeof Foo === "undefined" ? Object : Foo
            // This must not keep imports that are only used as TS types.
            if (isDecoratorMetadataTypeFallback(arena, e)) return;
            try collectValueRefs(arena, alloc, e.cond, refs);
            try collectValueRefs(arena, alloc, e.consequent, refs);
            try collectValueRefs(arena, alloc, e.alternate, refs);
        },
        .arrow_fn => |f| {
            // skip type_params — type positions
            for (f.params) |p| try collectValueRefs(arena, alloc, p, refs);
            try collectValueRefs(arena, alloc, f.body, refs);
        },
        .fn_expr => |f| {
            if (f.id) |id| try collectValueRefs(arena, alloc, id, refs);
            for (f.params) |p| try collectValueRefs(arena, alloc, p, refs);
            // skip param_types, return_type — type positions
            try collectValueRefs(arena, alloc, f.body, refs);
        },
        .class_expr => |c| {
            if (c.id) |id| try collectValueRefs(arena, alloc, id, refs);
            if (c.super_class) |s| try collectValueRefs(arena, alloc, s, refs);
            for (c.body) |m| try collectMember(arena, alloc, m, refs);
        },
        .object_expr => |o| for (o.props) |prop| switch (prop) {
            .kv => |kv| {
                if (kv.computed) try collectValueRefs(arena, alloc, kv.key, refs);
                try collectValueRefs(arena, alloc, kv.value, refs);
            },
            .shorthand => |s| try collectValueRefs(arena, alloc, s, refs),
            .spread => |s| try collectValueRefs(arena, alloc, s, refs),
            .method => |m| {
                if (m.computed) try collectValueRefs(arena, alloc, m.key, refs);
                try collectValueRefs(arena, alloc, m.value, refs);
            },
        },
        .array_expr => |a| for (a.elements) |el| {
            if (el) |e| try collectValueRefs(arena, alloc, e, refs);
        },
        .template_lit => |t| for (t.exprs) |e| try collectValueRefs(arena, alloc, e, refs),
        .tagged_template => |t| {
            try collectValueRefs(arena, alloc, t.tag, refs);
            try collectValueRefs(arena, alloc, t.quasi, refs);
        },
        .spread_elem => |s| try collectValueRefs(arena, alloc, s.argument, refs),
        .yield_expr => |e| if (e.argument) |a| try collectValueRefs(arena, alloc, a, refs),
        .await_expr => |e| try collectValueRefs(arena, alloc, e.argument, refs),

        // ── Patterns ──────────────────────────────────────────────────────────
        .assign_pat => |p| {
            try collectValueRefs(arena, alloc, p.left, refs);
            try collectValueRefs(arena, alloc, p.right, refs);
        },
        .rest_elem => |r| try collectValueRefs(arena, alloc, r.argument, refs),
        .object_pat => |p| {
            for (p.props) |prop| switch (prop) {
                .assign => |a| {
                    if (a.computed) try collectValueRefs(arena, alloc, a.key, refs);
                    if (a.value) |v| try collectValueRefs(arena, alloc, v, refs);
                },
                .rest => |r| try collectValueRefs(arena, alloc, r, refs),
            };
            if (p.rest) |r| try collectValueRefs(arena, alloc, r, refs);
        },
        .array_pat => |p| {
            for (p.elements) |el| if (el) |e| try collectValueRefs(arena, alloc, e, refs);
            if (p.rest) |r| try collectValueRefs(arena, alloc, r, refs);
        },

        // ── TS enum (runtime IIFE) ────────────────────────────────────────────
        .ts_enum => |e| {
            try collectValueRefs(arena, alloc, e.id, refs);
            for (e.members) |m| {
                try collectValueRefs(arena, alloc, m.id, refs);
                if (m.init) |init| try collectValueRefs(arena, alloc, init, refs);
            }
        },

        // ── JSX ───────────────────────────────────────────────────────────────
        .jsx_element => |e| {
            for (e.opening.attrs) |attr| switch (attr) {
                .named => |kv| if (kv.value) |v| try collectValueRefs(arena, alloc, v, refs),
                .spread => |s| try collectValueRefs(arena, alloc, s, refs),
            };
            for (e.children) |child| try collectValueRefs(arena, alloc, child, refs);
        },
        .jsx_fragment => |f| for (f.children) |c| try collectValueRefs(arena, alloc, c, refs),
        .jsx_expr_container => |c| if (c.expr) |e| try collectValueRefs(arena, alloc, e, refs),

        // ── Leaves with no binding refs ───────────────────────────────────────
        .num_lit,
        .str_lit,
        .bool_lit,
        .null_lit,
        .undefined_ref,
        .new_target,
        .regex_lit,
        .import_meta,
        .import_call,
        .jsx_text,
        .jsx_name,
        .jsx_member_expr,
        .raw_js,
        => {},
    }
}

fn collectMember(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    m: ast.ClassMember,
    refs: *std.StringHashMapUnmanaged(void),
) std.mem.Allocator.Error!void {
    for (m.decorators) |d| try collectValueRefs(arena, alloc, d, refs);
    if (m.is_computed) try collectValueRefs(arena, alloc, m.key, refs);
    if (m.value) |v| try collectValueRefs(arena, alloc, v, refs);
}

fn isDecoratorMetadataTypeFallback(arena: *ast.Arena, e: anytype) bool {
    if (!isIdentNamed(arena, e.consequent, "Object")) return false;

    const typeof_name = typeofUndefinedGuardName(arena, e.cond) orelse return false;
    const alternate_name = runtimeRootName(arena, e.alternate) orelse return false;

    return std.mem.eql(u8, typeof_name, alternate_name);
}

fn typeofUndefinedGuardName(arena: *ast.Arena, node_id: ast.NodeId) ?[]const u8 {
    return switch (arena.get(node_id).*) {
        .binary_expr => |b| blk: {
            if (b.op != .eq3) break :blk null;

            if (isUndefinedString(arena, b.right)) {
                break :blk typeofOperandName(arena, b.left);
            }

            if (isUndefinedString(arena, b.left)) {
                break :blk typeofOperandName(arena, b.right);
            }

            break :blk null;
        },
        else => null,
    };
}

fn typeofOperandName(arena: *ast.Arena, node_id: ast.NodeId) ?[]const u8 {
    return switch (arena.get(node_id).*) {
        .unary_expr => |u| blk: {
            if (u.op != .typeof) break :blk null;
            break :blk runtimeRootName(arena, u.argument);
        },
        else => null,
    };
}

fn runtimeRootName(arena: *ast.Arena, node_id: ast.NodeId) ?[]const u8 {
    return switch (arena.get(node_id).*) {
        .ident => |i| i.name,
        .member_expr => |m| runtimeRootName(arena, m.object),
        else => null,
    };
}

fn isIdentNamed(arena: *ast.Arena, node_id: ast.NodeId, name: []const u8) bool {
    return switch (arena.get(node_id).*) {
        .ident => |i| std.mem.eql(u8, i.name, name),
        else => false,
    };
}

fn isUndefinedString(arena: *ast.Arena, node_id: ast.NodeId) bool {
    return switch (arena.get(node_id).*) {
        .str_lit => |s| std.mem.eql(u8, s.value, "undefined"),
        else => false,
    };
}
