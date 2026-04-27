const std = @import("std");
const ast = @import("parser").ast;
const NodeId = ast.NodeId;

pub fn stripTypes(arena: *ast.Arena, alloc: std.mem.Allocator) !void {
    var i: u32 = 0;
    while (i < arena.nodes.items.len) : (i += 1) {
        const node = arena.getMut(i);
        switch (node.*) {
            .ts_interface, .ts_type_alias => {
                node.* = .{ .empty_stmt = .{ .span = node.span() } };
            },
            .ts_enum => {
                // Emit both `enum` and `const enum` as runtime enums.
                // This keeps output valid and preserves references even though
                // we don't currently inline const-enum members.
            },
            .class_decl => |*c| {
                var kept = std.ArrayListUnmanaged(ast.ClassMember).empty;
                for (c.body) |m| {
                    const is_callable = m.kind == .method or m.kind == .getter or m.kind == .setter or m.kind == .constructor;
                    const skip = (m.value == null and is_callable) or m.is_declare;
                    if (!skip) try kept.append(alloc, m);
                }
                c.body = try kept.toOwnedSlice(alloc);
            },
            .import_decl => |*imp| {
                if (imp.is_type_only) {
                    node.* = .{ .empty_stmt = .{ .span = imp.span } };
                    continue;
                }
                var kept = std.ArrayListUnmanaged(ast.ImportSpecifier).empty;
                for (imp.specifiers) |s| {
                    if (!s.is_type_only) try kept.append(alloc, s);
                }
                imp.specifiers = try kept.toOwnedSlice(alloc);
                if (imp.specifiers.len == 0 and imp.attributes.len == 0) {
                    node.* = .{ .empty_stmt = .{ .span = imp.span } };
                }
            },
            .export_decl => |*exp| {
                switch (exp.kind) {
                    .decl => |decl_id| {
                        switch (arena.get(decl_id).*) {
                            .empty_stmt, .ts_interface, .ts_type_alias => {
                                node.* = .{ .empty_stmt = .{ .span = exp.span } };
                                continue;
                            },
                            else => {},
                        }
                    },
                    .named => |*n| {
                        if (n.is_type_only) {
                            node.* = .{ .empty_stmt = .{ .span = exp.span } };
                            continue;
                        }
                        var kept = std.ArrayListUnmanaged(ast.ExportSpecifier).empty;
                        for (n.specifiers) |s| {
                            if (!s.is_type_only) try kept.append(alloc, s);
                        }
                        n.specifiers = try kept.toOwnedSlice(alloc);
                        if (n.specifiers.len == 0 and n.source == null) {
                            node.* = .{ .empty_stmt = .{ .span = exp.span } };
                        }
                    },
                    .all => |a| {
                        if (a.is_type_only) {
                            node.* = .{ .empty_stmt = .{ .span = exp.span } };
                            continue;
                        }
                    },
                    else => {},
                }
            },
            .ts_as_expr => |e| node.* = arena.get(e.expr).*,
            .ts_satisfies => |e| node.* = arena.get(e.expr).*,
            .ts_instantiation => |e| node.* = arena.get(e.expr).*,
            .ts_non_null => |e| node.* = arena.get(e.expr).*,
            .ts_type_assert => |e| node.* = arena.get(e.expr).*,
            else => {},
        }
    }
}

pub fn lowerUsingDecls(arena: *ast.Arena, alloc: std.mem.Allocator) !void {
    var i: u32 = 0;
    while (i < arena.nodes.items.len) : (i += 1) {
        const node = arena.getMut(i);
        switch (node.*) {
            .var_decl => |*v| {
                if (v.kind == .using) {
                    v.kind = .@"const";
                    v.is_await = false;
                }
            },
            .class_decl => |*c| {
                var kept = std.ArrayListUnmanaged(ast.ClassMember).empty;
                for (c.body) |m| {
                    var mm = m;
                    if (mm.kind == .auto_accessor) {
                        mm.kind = .field;
                    }
                    try kept.append(alloc, mm);
                }
                c.body = try kept.toOwnedSlice(alloc);
            },
            else => {},
        }
    }
}
