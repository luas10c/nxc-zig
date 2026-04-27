const std = @import("std");

const ast = @import("ast");
const lexer = @import("lexer");

const NodeId = ast.NodeId;

pub const JsxRuntime = enum { classic, automatic };

pub const JsxConfig = struct {
    runtime: JsxRuntime = .classic,
    factory: []const u8 = "React.createElement",
    fragment: []const u8 = "React.Fragment",
    import_source: []const u8 = "react",
};

pub fn transformJsx(arena: *ast.Arena, alloc: std.mem.Allocator, cfg: JsxConfig, program_id: NodeId) !void {
    var needs_jsx = false;
    var needs_jsxs = false;
    var needs_fragment = false;

    var i: u32 = 0;
    while (i < arena.nodes.items.len) : (i += 1) {
        switch (arena.getMut(i).*) {
            .jsx_element => |el| {
                if (cfg.runtime == .automatic) {
                    if (el.children.len > 1) {
                        needs_jsxs = true;
                    } else {
                        needs_jsx = true;
                    }
                }
                const call = try buildJsxCall(arena, alloc, cfg, el);
                arena.getMut(i).* = arena.get(call).*;
            },
            .jsx_fragment => |frag| {
                if (cfg.runtime == .automatic) {
                    needs_fragment = true;
                    if (frag.children.len > 1) {
                        needs_jsxs = true;
                    } else {
                        needs_jsx = true;
                    }
                }
                const call = try buildFragmentCall(arena, alloc, cfg, frag);
                arena.getMut(i).* = arena.get(call).*;
            },
            .jsx_expr_container => |c| {
                if (c.expr) |e| arena.getMut(i).* = arena.get(e).*;
            },
            .jsx_text => |t| {
                const raw = try std.fmt.allocPrint(alloc, "\"{s}\"", .{t.raw});
                arena.getMut(i).* = .{ .str_lit = .{ .raw = raw, .value = t.raw, .span = t.span } };
            },
            else => {},
        }
    }

    if (cfg.runtime == .automatic and (needs_jsx or needs_jsxs or needs_fragment)) {
        try injectJsxRuntimeImport(arena, alloc, cfg, program_id, needs_jsx, needs_jsxs, needs_fragment);
    }
}

fn buildJsxCall(arena: *ast.Arena, alloc: std.mem.Allocator, cfg: JsxConfig, el: ast.JsxElement) !NodeId {
    const tag_str = arena.get(el.opening.name).jsx_name.name;
    const is_component = tag_str.len > 0 and std.ascii.isUpper(tag_str[0]);

    const tag_arg = if (is_component)
        try arena.push(.{ .ident = .{ .name = tag_str, .span = el.span } })
    else blk: {
        const raw = try std.fmt.allocPrint(alloc, "\"{s}\"", .{tag_str});
        break :blk try arena.push(.{ .str_lit = .{ .raw = raw, .value = tag_str, .span = el.span } });
    };

    const props_node = try buildProps(arena, alloc, el.opening.attrs, el.children, cfg, el.span);

    if (cfg.runtime == .automatic) {
        const factory_name: []const u8 = if (el.children.len > 1) "_jsxs" else "_jsx";
        const callee = try arena.push(.{ .ident = .{ .name = factory_name, .span = el.span } });
        var args = std.ArrayListUnmanaged(ast.Argument).empty;
        try args.append(alloc, .{ .expr = tag_arg, .spread = false });
        try args.append(alloc, .{ .expr = props_node, .spread = false });
        return arena.push(.{ .call_expr = .{
            .callee = callee,
            .type_args = &.{},
            .args = try args.toOwnedSlice(alloc),
            .optional = false,
            .span = el.span,
        } });
    }

    var args = std.ArrayListUnmanaged(ast.Argument).empty;
    try args.append(alloc, .{ .expr = tag_arg, .spread = false });
    try args.append(alloc, .{ .expr = props_node, .spread = false });
    for (el.children) |child| {
        try args.append(alloc, .{ .expr = child, .spread = false });
    }

    const callee = try arena.push(.{ .ident = .{ .name = cfg.factory, .span = el.span } });
    return arena.push(.{ .call_expr = .{
        .callee = callee,
        .type_args = &.{},
        .args = try args.toOwnedSlice(alloc),
        .optional = false,
        .span = el.span,
    } });
}

fn isValidJsIdent(name: []const u8) bool {
    if (name.len == 0) return false;
    if (!(std.ascii.isAlphabetic(name[0]) or name[0] == '_' or name[0] == '$')) return false;
    for (name[1..]) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == '$')) return false;
    }
    return true;
}

fn buildProps(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    attrs: []const ast.JsxAttr,
    children: []const NodeId,
    cfg: JsxConfig,
    span: lexer.token.Span,
) !NodeId {
    if (attrs.len == 0 and (children.len == 0 or cfg.runtime == .classic)) {
        if (attrs.len == 0 and children.len == 0) {
            if (cfg.runtime == .automatic) {
                return arena.push(.{ .object_expr = .{ .props = &.{}, .span = span } });
            }
            return arena.push(.{ .null_lit = .{ .span = span } });
        }
    }

    var props = std.ArrayListUnmanaged(ast.ObjectProp).empty;

    for (attrs) |attr| {
        switch (attr) {
            .spread => |s| try props.append(alloc, .{ .spread = s }),
            .named => |n| {
                const val = n.value orelse try arena.push(.{ .bool_lit = .{ .value = true, .span = n.span } });
                const attr_name = arena.get(n.name).jsx_name.name;
                const key = if (isValidJsIdent(attr_name))
                    try arena.push(.{ .ident = .{ .name = attr_name, .span = n.span } })
                else blk: {
                    const raw = try std.fmt.allocPrint(alloc, "\"{s}\"", .{attr_name});
                    break :blk try arena.push(.{ .str_lit = .{ .raw = raw, .value = attr_name, .span = n.span } });
                };
                try props.append(alloc, .{ .kv = .{ .key = key, .value = val, .computed = false, .span = n.span } });
            },
        }
    }

    if (cfg.runtime == .automatic and children.len > 0) {
        const children_val = if (children.len == 1)
            children[0]
        else blk: {
            var elems = std.ArrayListUnmanaged(?NodeId).empty;
            for (children) |c| try elems.append(alloc, c);
            break :blk try arena.push(.{ .array_expr = .{ .elements = try elems.toOwnedSlice(alloc), .span = span } });
        };
        const children_key = try arena.push(.{ .ident = .{ .name = "children", .span = span } });
        try props.append(alloc, .{ .kv = .{ .key = children_key, .value = children_val, .computed = false, .span = span } });
    }

    if (props.items.len == 0) return arena.push(.{ .null_lit = .{ .span = span } });

    return arena.push(.{ .object_expr = .{ .props = try props.toOwnedSlice(alloc), .span = span } });
}

fn buildFragmentCall(arena: *ast.Arena, alloc: std.mem.Allocator, cfg: JsxConfig, frag: ast.JsxFragment) !NodeId {
    if (cfg.runtime == .automatic) {
        const frag_ref = try arena.push(.{ .ident = .{ .name = "_fragment", .span = frag.span } });
        const factory_name: []const u8 = if (frag.children.len > 1) "_jsxs" else "_jsx";
        const callee = try arena.push(.{ .ident = .{ .name = factory_name, .span = frag.span } });

        var props = std.ArrayListUnmanaged(ast.ObjectProp).empty;
        if (frag.children.len > 0) {
            const children_val = if (frag.children.len == 1)
                frag.children[0]
            else blk: {
                var elems = std.ArrayListUnmanaged(?NodeId).empty;
                for (frag.children) |c| try elems.append(alloc, c);
                break :blk try arena.push(.{ .array_expr = .{ .elements = try elems.toOwnedSlice(alloc), .span = frag.span } });
            };
            const key = try arena.push(.{ .ident = .{ .name = "children", .span = frag.span } });
            try props.append(alloc, .{ .kv = .{ .key = key, .value = children_val, .computed = false, .span = frag.span } });
        }
        const props_node = if (props.items.len > 0)
            try arena.push(.{ .object_expr = .{ .props = try props.toOwnedSlice(alloc), .span = frag.span } })
        else
            try arena.push(.{ .object_expr = .{ .props = &.{}, .span = frag.span } });

        var args = std.ArrayListUnmanaged(ast.Argument).empty;
        try args.append(alloc, .{ .expr = frag_ref, .spread = false });
        try args.append(alloc, .{ .expr = props_node, .spread = false });
        return arena.push(.{ .call_expr = .{
            .callee = callee,
            .type_args = &.{},
            .args = try args.toOwnedSlice(alloc),
            .optional = false,
            .span = frag.span,
        } });
    }

    const callee = try arena.push(.{ .ident = .{ .name = cfg.factory, .span = frag.span } });
    const frag_ref = try arena.push(.{ .ident = .{ .name = cfg.fragment, .span = frag.span } });
    const null_props = try arena.push(.{ .null_lit = .{ .span = frag.span } });

    var args = std.ArrayListUnmanaged(ast.Argument).empty;
    try args.append(alloc, .{ .expr = frag_ref, .spread = false });
    try args.append(alloc, .{ .expr = null_props, .spread = false });
    for (frag.children) |c| try args.append(alloc, .{ .expr = c, .spread = false });

    return arena.push(.{ .call_expr = .{
        .callee = callee,
        .type_args = &.{},
        .args = try args.toOwnedSlice(alloc),
        .optional = false,
        .span = frag.span,
    } });
}

fn injectJsxRuntimeImport(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    cfg: JsxConfig,
    program_id: NodeId,
    needs_jsx: bool,
    needs_jsxs: bool,
    needs_fragment: bool,
) !void {
    const span = lexer.token.Span{ .start = 0, .end = 0, .line = 0, .col = 0 };

    var specifiers = std.ArrayListUnmanaged(ast.ImportSpecifier).empty;

    if (needs_jsx) {
        const local = try arena.push(.{ .ident = .{ .name = "_jsx", .span = span } });
        const imported = try arena.push(.{ .ident = .{ .name = "jsx", .span = span } });
        try specifiers.append(alloc, .{
            .kind = .named,
            .local = local,
            .imported = imported,
            .is_type_only = false,
            .span = span,
        });
    }
    if (needs_jsxs) {
        const local = try arena.push(.{ .ident = .{ .name = "_jsxs", .span = span } });
        const imported = try arena.push(.{ .ident = .{ .name = "jsxs", .span = span } });
        try specifiers.append(alloc, .{
            .kind = .named,
            .local = local,
            .imported = imported,
            .is_type_only = false,
            .span = span,
        });
    }
    if (needs_fragment) {
        const local = try arena.push(.{ .ident = .{ .name = "_fragment", .span = span } });
        const imported = try arena.push(.{ .ident = .{ .name = "Fragment", .span = span } });
        try specifiers.append(alloc, .{
            .kind = .named,
            .local = local,
            .imported = imported,
            .is_type_only = false,
            .span = span,
        });
    }

    const source_val = try std.fmt.allocPrint(alloc, "{s}/jsx-runtime", .{cfg.import_source});
    const source_raw = try std.fmt.allocPrint(alloc, "\"{s}/jsx-runtime\"", .{cfg.import_source});
    const source = try arena.push(.{ .str_lit = .{ .raw = source_raw, .value = source_val, .span = span } });

    const import_id = try arena.push(.{ .import_decl = .{
        .specifiers = try specifiers.toOwnedSlice(alloc),
        .source = source,
        .is_type_only = false,
        .attributes = &.{},
        .span = span,
    } });

    const prog = &arena.getMut(program_id).program;
    const new_body = try alloc.alloc(NodeId, prog.body.len + 1);
    new_body[0] = import_id;
    @memcpy(new_body[1..], prog.body);
    prog.body = new_body;
}
