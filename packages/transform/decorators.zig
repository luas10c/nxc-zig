const std = @import("std");

const ast = @import("ast");
const lexer = @import("lexer");

const NodeId = ast.NodeId;

pub const DecoratorConfig = struct {
    legacy: bool = false,
    emit_metadata: bool = false,
};

const ZERO_SPAN = lexer.token.Span{ .start = 0, .end = 0, .line = 1, .col = 1 };

// TypeScript-compatible __decorate: handles both class (2 args) and member (4 args).
const DECORATE_HELPER: []const u8 =
    "var __decorate = function(decorators, target, key, desc) { var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d; for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r; return c > 3 && r && Object.defineProperty(target, key, r), r; };";

const METADATA_HELPER: []const u8 =
    "var __metadata = function(k, v) { if (typeof Reflect === \"object\" && typeof Reflect.metadata === \"function\") return Reflect.metadata(k, v); };";

const PARAM_HELPER: []const u8 =
    "var __param = function(paramIndex, decorator) { return function(target, key) { decorator(target, key, paramIndex); }; };";

const MemberInfo = struct {
    decorators: []const NodeId,
    param_decorators: []const []const NodeId,
    param_types: []const ?NodeId,
    return_type: ?NodeId,
    key_id: NodeId,
    kind: ast.ClassMemberKind,
    is_static: bool,
    is_computed: bool,
    is_async: bool,
};

pub fn transformDecorators(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    cfg: DecoratorConfig,
    program_id: NodeId,
) !void {
    const original_body = arena.get(program_id).program.body;

    var new_body = std.ArrayListUnmanaged(NodeId).empty;
    defer new_body.deinit(alloc);

    var needs_decorate_helper = false;
    var needs_metadata_helper = false;
    var needs_param_helper = false;

    for (original_body) |stmt_id| {
        const n = arena.get(stmt_id);

        // --- export class X {} with decorators ---
        if (n.* == .export_decl) {
            switch (n.export_decl.kind) {
                .decl => |inner_id| {
                    const inner = arena.get(inner_id);
                    if (inner.* == .class_decl and cfg.legacy and
                        (classNeedsProcessing(inner.class_decl) or classHasConstructorParamDecoratorsArena(arena, inner.class_decl)))
                    {
                        try handleDecoratedExportClass(
                            arena,
                            alloc,
                            cfg,
                            inner_id,
                            inner.class_decl,
                            &new_body,
                            &needs_decorate_helper,
                            &needs_metadata_helper,
                            &needs_param_helper,
                        );
                        continue;
                    }
                },
                .default_decl => |inner_id| {
                    const inner = arena.get(inner_id);
                    if (inner.* == .class_decl and cfg.legacy and
                        (classNeedsProcessing(inner.class_decl) or classHasConstructorParamDecoratorsArena(arena, inner.class_decl)))
                    {
                        try handleDecoratedExportDefaultClass(
                            arena,
                            alloc,
                            cfg,
                            inner_id,
                            inner.class_decl,
                            &new_body,
                            &needs_decorate_helper,
                            &needs_metadata_helper,
                            &needs_param_helper,
                        );
                        continue;
                    }
                },
                else => {},
            }
        }

        // --- class X {} with decorators (no export) ---
        if (n.* == .class_decl and cfg.legacy and
            (classNeedsProcessing(n.class_decl) or classHasConstructorParamDecoratorsArena(arena, n.class_decl)))
        {
            try handleDecoratedClass(
                arena,
                alloc,
                cfg,
                stmt_id,
                n.class_decl,
                &new_body,
                &needs_decorate_helper,
                &needs_metadata_helper,
                &needs_param_helper,
            );
            continue;
        }

        try new_body.append(alloc, stmt_id);
    }

    // Prepend helpers.
    var final_body = std.ArrayListUnmanaged(NodeId).empty;
    defer final_body.deinit(alloc);
    if (needs_decorate_helper) {
        const h = try arena.push(.{ .raw_js = .{ .code = DECORATE_HELPER, .span = ZERO_SPAN } });
        try final_body.append(alloc, h);
    }
    if (needs_metadata_helper and cfg.emit_metadata) {
        const h = try arena.push(.{ .raw_js = .{ .code = METADATA_HELPER, .span = ZERO_SPAN } });
        try final_body.append(alloc, h);
    }
    if (needs_param_helper and cfg.legacy) {
        const h = try arena.push(.{ .raw_js = .{ .code = PARAM_HELPER, .span = ZERO_SPAN } });
        try final_body.append(alloc, h);
    }
    try final_body.appendSlice(alloc, new_body.items);
    arena.getMut(program_id).program.body = try final_body.toOwnedSlice(alloc);
}

// @Dec class X {} → let X = class X {}; X = __decorate([Dec], X);
fn handleDecoratedClass(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    cfg: DecoratorConfig,
    class_node_id: NodeId,
    class: ast.ClassDecl,
    new_body: *std.ArrayListUnmanaged(NodeId),
    needs_decorate_helper: *bool,
    needs_metadata_helper: *bool,
    needs_param_helper: *bool,
) !void {
    var member_infos = try captureMemberInfos(arena, alloc, class);
    defer member_infos.deinit(alloc);

    const class_name_id = class.id orelse {
        try new_body.append(alloc, class_node_id);
        return;
    };
    const class_name = arena.get(class_name_id).ident.name;

    // Strip decorators.
    {
        const node = arena.getMut(class_node_id);
        node.class_decl.decorators = &.{};
        for (node.class_decl.body) |*m| m.decorators = &.{};
    }

    // Convert class_decl → let X = class X {}
    const var_id = try classToLetExpr(arena, alloc, class_node_id, class, class_name);
    try new_body.append(alloc, var_id);

    // Member __decorate calls.
    try emitMemberDecorateStmts(arena, alloc, cfg, class_name_id, member_infos.items, new_body, needs_decorate_helper, needs_metadata_helper, needs_param_helper);

    // Class __decorate call (also fires for constructor param decorators).
    const ctor_params = try buildConstructorParamDecoratorCalls(arena, alloc, class, needs_param_helper);
    defer alloc.free(ctor_params);
    if (class.decorators.len > 0 or ctor_params.len > 0) {
        const metadata = try buildClassMetadata(arena, alloc, class, cfg, needs_metadata_helper);
        defer alloc.free(metadata);
        try emitClassDecorateStmt(arena, alloc, class_name_id, class.decorators, ctor_params, metadata, new_body);
        needs_decorate_helper.* = true;
    }
}

// @Dec export class X {} → let X = class X {}; X = __decorate([Dec], X); export { X };
fn handleDecoratedExportClass(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    cfg: DecoratorConfig,
    class_node_id: NodeId,
    class: ast.ClassDecl,
    new_body: *std.ArrayListUnmanaged(NodeId),
    needs_decorate_helper: *bool,
    needs_metadata_helper: *bool,
    needs_param_helper: *bool,
) !void {
    var member_infos = try captureMemberInfos(arena, alloc, class);
    defer member_infos.deinit(alloc);

    const class_name_id = class.id orelse return;
    const class_name = arena.get(class_name_id).ident.name;

    // Strip decorators.
    {
        const node = arena.getMut(class_node_id);
        node.class_decl.decorators = &.{};
        for (node.class_decl.body) |*m| m.decorators = &.{};
    }

    // Match TypeScript's legacy decorator lowering for exported classes:
    // let X = class X {}; X = __decorate([Dec], X); export { X };
    // Keeping `export class X {}` leaves `X` as a class lexical binding and can
    // expose TDZ failures in ESM cycles while decorators are being evaluated.
    const var_id = try classToLetExpr(arena, alloc, class_node_id, class, class_name);
    try new_body.append(alloc, var_id);

    // Member __decorate calls.
    try emitMemberDecorateStmts(arena, alloc, cfg, class_name_id, member_infos.items, new_body, needs_decorate_helper, needs_metadata_helper, needs_param_helper);

    // Class __decorate call (also fires for constructor param decorators).
    const ctor_params = try buildConstructorParamDecoratorCalls(arena, alloc, class, needs_param_helper);
    defer alloc.free(ctor_params);
    if (class.decorators.len > 0 or ctor_params.len > 0) {
        const metadata = try buildClassMetadata(arena, alloc, class, cfg, needs_metadata_helper);
        defer alloc.free(metadata);
        try emitClassDecorateStmt(arena, alloc, class_name_id, class.decorators, ctor_params, metadata, new_body);
        needs_decorate_helper.* = true;
    }

    try emitNamedExport(arena, alloc, class_name, new_body);
}

// @Dec export default class X {} → let X = class X {}; X = __decorate([Dec], X); export default X;
fn handleDecoratedExportDefaultClass(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    cfg: DecoratorConfig,
    class_node_id: NodeId,
    class: ast.ClassDecl,
    new_body: *std.ArrayListUnmanaged(NodeId),
    needs_decorate_helper: *bool,
    needs_metadata_helper: *bool,
    needs_param_helper: *bool,
) !void {
    var member_infos = try captureMemberInfos(arena, alloc, class);
    defer member_infos.deinit(alloc);

    // Strip decorators.
    {
        const node = arena.getMut(class_node_id);
        node.class_decl.decorators = &.{};
        for (node.class_decl.body) |*m| m.decorators = &.{};
    }

    if (class.id == null) {
        // Anonymous default class — can't assign back; just emit as-is.
        try new_body.append(alloc, class_node_id);
        return;
    }

    const class_name_id = class.id.?;
    const class_name = arena.get(class_name_id).ident.name;

    // let X = class X {}
    const var_id = try classToLetExpr(arena, alloc, class_node_id, class, class_name);
    try new_body.append(alloc, var_id);

    try emitMemberDecorateStmts(arena, alloc, cfg, class_name_id, member_infos.items, new_body, needs_decorate_helper, needs_metadata_helper, needs_param_helper);

    // Class __decorate call (also fires for constructor param decorators).
    const ctor_params = try buildConstructorParamDecoratorCalls(arena, alloc, class, needs_param_helper);
    defer alloc.free(ctor_params);
    if (class.decorators.len > 0 or ctor_params.len > 0) {
        const metadata = try buildClassMetadata(arena, alloc, class, cfg, needs_metadata_helper);
        defer alloc.free(metadata);
        try emitClassDecorateStmt(arena, alloc, class_name_id, class.decorators, ctor_params, metadata, new_body);
        needs_decorate_helper.* = true;
    }

    // export default X;
    const ref = try arena.push(.{ .ident = .{ .name = class_name, .span = ZERO_SPAN } });
    const exp = try arena.push(.{ .export_decl = .{
        .kind = .{ .default_expr = ref },
        .span = ZERO_SPAN,
    } });
    try new_body.append(alloc, exp);
}

fn classNeedsProcessing(class: ast.ClassDecl) bool {
    if (class.decorators.len > 0) return true;
    for (class.body) |member| {
        if (member.decorators.len > 0) return true;
    }
    return false;
}

fn classHasConstructorParamDecoratorsArena(arena: *const ast.Arena, class: ast.ClassDecl) bool {
    for (class.body) |member| {
        if (member.kind != .constructor) continue;
        const v = member.value orelse continue;
        const f = arena.get(v).fn_expr;
        for (f.param_decorators) |decs| if (decs.len > 0) return true;
    }
    return false;
}

/// Build __param(i, Dec) call nodes for each decorated constructor parameter.
fn buildConstructorParamDecoratorCalls(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    class: ast.ClassDecl,
    needs_param_helper: *bool,
) ![]NodeId {
    for (class.body) |member| {
        if (member.kind != .constructor) continue;
        const v = member.value orelse continue;
        const f = arena.get(v).fn_expr;
        var calls = std.ArrayListUnmanaged(NodeId).empty;
        for (f.param_decorators, 0..) |param_decs, index| {
            for (param_decs) |d| {
                const pc = try buildParamCall(arena, alloc, @intCast(index), d);
                try calls.append(alloc, pc);
                needs_param_helper.* = true;
            }
        }
        return calls.toOwnedSlice(alloc);
    }
    return &.{};
}

// Convert class_decl node in-place to class_expr, wrap in let VarDecl.
// Returns the VarDecl node id.
fn classToLetExpr(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    class_node_id: NodeId,
    class: ast.ClassDecl,
    class_name: []const u8,
) !NodeId {
    // Read fields before mutating.
    const body = arena.get(class_node_id).class_decl.body;
    const super_class = arena.get(class_node_id).class_decl.super_class;
    const span = arena.get(class_node_id).class_decl.span;

    // Convert node to class_expr in-place.
    arena.getMut(class_node_id).* = .{ .class_expr = .{
        .id = class.id,
        .type_params = class.type_params,
        .super_class = super_class,
        .body = body,
        .span = span,
    } };

    // let ClassName = <class_expr>
    const decl_name = try arena.push(.{ .ident = .{ .name = class_name, .span = ZERO_SPAN } });
    const declarators = try alloc.alloc(ast.VarDeclarator, 1);
    declarators[0] = .{ .id = decl_name, .init = class_node_id, .span = ZERO_SPAN };
    return arena.push(.{ .var_decl = .{
        .kind = .let,
        .declarators = declarators,
        .span = ZERO_SPAN,
    } });
}

// ClassName = __decorate([Dec1, __param(i, Dec), ...metadata], ClassName);
fn emitClassDecorateStmt(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    class_name_id: NodeId,
    decorators: []const NodeId,
    ctor_params: []const NodeId,
    metadata: []const NodeId,
    new_body: *std.ArrayListUnmanaged(NodeId),
) !void {
    var elems = std.ArrayListUnmanaged(?NodeId).empty;
    defer elems.deinit(alloc);
    for (decorators) |d| try elems.append(alloc, d);
    for (ctor_params) |p| try elems.append(alloc, p);
    for (metadata) |m| try elems.append(alloc, m);

    const dec_array = try arena.push(.{ .array_expr = .{
        .elements = try elems.toOwnedSlice(alloc),
        .span = ZERO_SPAN,
    } });

    const decorate_ident = try arena.push(.{ .ident = .{ .name = "__decorate", .span = ZERO_SPAN } });
    const call_args = try alloc.alloc(ast.Argument, 2);
    call_args[0] = .{ .expr = dec_array, .spread = false };
    call_args[1] = .{ .expr = class_name_id, .spread = false };
    const call_id = try arena.push(.{ .call_expr = .{
        .callee = decorate_ident,
        .type_args = &.{},
        .args = call_args,
        .optional = false,
        .span = ZERO_SPAN,
    } });

    const assign_id = try arena.push(.{ .assign_expr = .{
        .op = .eq,
        .left = class_name_id,
        .right = call_id,
        .span = ZERO_SPAN,
    } });
    const stmt = try arena.push(.{ .expr_stmt = .{ .expr = assign_id, .span = ZERO_SPAN } });
    try new_body.append(alloc, stmt);
}

// export { ClassName };
fn emitNamedExport(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    class_name: []const u8,
    new_body: *std.ArrayListUnmanaged(NodeId),
) !void {
    const local = try arena.push(.{ .ident = .{ .name = class_name, .span = ZERO_SPAN } });
    const exported = try arena.push(.{ .ident = .{ .name = class_name, .span = ZERO_SPAN } });
    const specs = try alloc.alloc(ast.ExportSpecifier, 1);
    specs[0] = .{ .local = local, .exported = exported, .is_type_only = false, .span = ZERO_SPAN };
    const exp = try arena.push(.{ .export_decl = .{
        .kind = .{ .named = .{ .specifiers = specs, .source = null, .is_type_only = false } },
        .span = ZERO_SPAN,
    } });
    try new_body.append(alloc, exp);
}

fn emitMemberDecorateStmts(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    cfg: DecoratorConfig,
    class_name_id: NodeId,
    member_infos: []const MemberInfo,
    new_body: *std.ArrayListUnmanaged(NodeId),
    needs_decorate_helper: *bool,
    needs_metadata_helper: *bool,
    needs_param_helper: *bool,
) !void {
    if (!cfg.legacy) return;

    for (member_infos) |info| {
        var elems = std.ArrayListUnmanaged(?NodeId).empty;
        defer elems.deinit(alloc);
        for (info.decorators) |d| try elems.append(alloc, d);
        for (info.param_decorators, 0..) |param_decs, index| {
            for (param_decs) |d| {
                const pc = try buildParamCall(arena, alloc, @intCast(index), d);
                try elems.append(alloc, pc);
                needs_param_helper.* = true;
            }
        }
        if (cfg.emit_metadata) {
            const mc = try buildMetadataCall(arena, alloc, "design:type", "Function");
            try elems.append(alloc, mc);
            const pm = try buildParamTypesMetadata(arena, alloc, info.param_types, needs_metadata_helper);
            if (pm) |m| try elems.append(alloc, m);
            const rm = try buildReturnTypeMetadata(arena, alloc, info, needs_metadata_helper);
            if (rm) |m| try elems.append(alloc, m);
            needs_metadata_helper.* = true;
        }
        const dec_array = try arena.push(.{ .array_expr = .{
            .elements = try elems.toOwnedSlice(alloc),
            .span = ZERO_SPAN,
        } });

        const target_id = if (info.is_static)
            class_name_id
        else blk: {
            const proto = try arena.push(.{ .ident = .{ .name = "prototype", .span = ZERO_SPAN } });
            break :blk try arena.push(.{ .member_expr = .{
                .object = class_name_id,
                .prop = proto,
                .computed = false,
                .optional = false,
                .span = ZERO_SPAN,
            } });
        };

        const key_id = if (info.is_computed)
            info.key_id
        else blk: {
            const key_name = getKeyName(arena, info.key_id) orelse continue;
            const key_raw = try std.fmt.allocPrint(alloc, "\"{s}\"", .{key_name});
            break :blk try arena.push(.{ .str_lit = .{ .raw = key_raw, .value = key_name, .span = ZERO_SPAN } });
        };

        const desc_id = switch (info.kind) {
            .method, .getter, .setter => try arena.push(.{ .null_lit = .{ .span = ZERO_SPAN } }),
            .field => blk: {
                const zero = try arena.push(.{ .num_lit = .{ .raw = "0", .span = ZERO_SPAN } });
                break :blk try arena.push(.{ .unary_expr = .{
                    .op = .void,
                    .prefix = true,
                    .argument = zero,
                    .span = ZERO_SPAN,
                } });
            },
            else => continue,
        };

        const decorate_ident = try arena.push(.{ .ident = .{ .name = "__decorate", .span = ZERO_SPAN } });
        const args = try alloc.alloc(ast.Argument, 4);
        args[0] = .{ .expr = dec_array, .spread = false };
        args[1] = .{ .expr = target_id, .spread = false };
        args[2] = .{ .expr = key_id, .spread = false };
        args[3] = .{ .expr = desc_id, .spread = false };
        const call_id = try arena.push(.{ .call_expr = .{
            .callee = decorate_ident,
            .type_args = &.{},
            .args = args,
            .optional = false,
            .span = ZERO_SPAN,
        } });
        const s = try arena.push(.{ .expr_stmt = .{ .expr = call_id, .span = ZERO_SPAN } });
        try new_body.append(alloc, s);
        needs_decorate_helper.* = true;
    }
}

fn buildClassMetadata(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    class: ast.ClassDecl,
    cfg: DecoratorConfig,
    needs_metadata_helper: *bool,
) ![]NodeId {
    if (!cfg.emit_metadata) return &.{};
    needs_metadata_helper.* = true;
    const mc = try buildConstructorParamTypesMetadata(arena, alloc, class, needs_metadata_helper);
    const out = try alloc.alloc(NodeId, 1);
    out[0] = mc;
    return out;
}

fn captureMemberInfos(arena: *const ast.Arena, alloc: std.mem.Allocator, class: ast.ClassDecl) !std.ArrayListUnmanaged(MemberInfo) {
    var list = std.ArrayListUnmanaged(MemberInfo).empty;
    for (class.body) |member| {
        const fn_param_decorators: []const []const NodeId = switch (member.kind) {
            .method, .getter, .setter, .constructor => blk: {
                if (member.value) |v| break :blk arena.get(v).fn_expr.param_decorators;
                break :blk &.{};
            },
            else => &.{},
        };
        const fn_param_types: []const ?NodeId = switch (member.kind) {
            .method, .getter, .setter, .constructor => blk: {
                if (member.value) |v| break :blk arena.get(v).fn_expr.param_types;
                break :blk &.{};
            },
            else => &.{},
        };
        const fn_return_type: ?NodeId = switch (member.kind) {
            .method, .getter, .setter, .constructor => blk: {
                if (member.value) |v| break :blk arena.get(v).fn_expr.return_type;
                break :blk null;
            },
            else => null,
        };
        const has_param_decorators = blk: {
            for (fn_param_decorators) |decs| if (decs.len > 0) break :blk true;
            break :blk false;
        };
        if (member.decorators.len == 0 and !has_param_decorators) continue;
        try list.append(alloc, .{
            .decorators = member.decorators,
            .param_decorators = fn_param_decorators,
            .param_types = fn_param_types,
            .return_type = fn_return_type,
            .key_id = member.key,
            .kind = member.kind,
            .is_static = member.is_static,
            .is_computed = member.is_computed,
            .is_async = switch (member.kind) {
                .method, .getter, .setter, .constructor => if (member.value) |v| arena.get(v).fn_expr.is_async else false,
                else => false,
            },
        });
    }
    return list;
}

fn buildMetadataCall(arena: *ast.Arena, alloc: std.mem.Allocator, key: []const u8, val: []const u8) !NodeId {
    const meta_ident = try arena.push(.{ .ident = .{ .name = "__metadata", .span = ZERO_SPAN } });
    const key_raw = try std.fmt.allocPrint(alloc, "\"{s}\"", .{key});
    const key_node = try arena.push(.{ .str_lit = .{ .raw = key_raw, .value = key, .span = ZERO_SPAN } });
    const val_node = try arena.push(.{ .ident = .{ .name = val, .span = ZERO_SPAN } });
    const args = try alloc.alloc(ast.Argument, 2);
    args[0] = .{ .expr = key_node, .spread = false };
    args[1] = .{ .expr = val_node, .spread = false };
    const call = try arena.push(.{ .call_expr = .{
        .callee = meta_ident,
        .type_args = &.{},
        .args = args,
        .optional = false,
        .span = ZERO_SPAN,
    } });
    return call;
}

fn buildParamCall(arena: *ast.Arena, alloc: std.mem.Allocator, index: u32, decorator: NodeId) !NodeId {
    const param_ident = try arena.push(.{ .ident = .{ .name = "__param", .span = ZERO_SPAN } });
    const index_raw = try std.fmt.allocPrint(alloc, "{d}", .{index});
    const index_node = try arena.push(.{ .num_lit = .{ .raw = index_raw, .span = ZERO_SPAN } });
    const args = try alloc.alloc(ast.Argument, 2);
    args[0] = .{ .expr = index_node, .spread = false };
    args[1] = .{ .expr = decorator, .spread = false };
    return arena.push(.{ .call_expr = .{
        .callee = param_ident,
        .type_args = &.{},
        .args = args,
        .optional = false,
        .span = ZERO_SPAN,
    } });
}

fn buildParamTypesMetadata(arena: *ast.Arena, alloc: std.mem.Allocator, param_types: []const ?NodeId, needs_metadata_helper: *bool) !?NodeId {
    if (param_types.len == 0) return null;
    needs_metadata_helper.* = true;
    const elems = try alloc.alloc(?NodeId, param_types.len);
    for (param_types, 0..) |param_type, i| {
        elems[i] = if (param_type) |ty|
            try mapTypeToRuntimeExpr(arena, alloc, ty)
        else
            try arena.push(.{ .ident = .{ .name = "Object", .span = ZERO_SPAN } });
    }
    const arr = try arena.push(.{ .array_expr = .{ .elements = elems, .span = ZERO_SPAN } });
    const call = try buildMetadataCallExpr(arena, alloc, "design:paramtypes", arr);
    return call;
}

fn buildConstructorParamTypesMetadata(arena: *ast.Arena, alloc: std.mem.Allocator, class: ast.ClassDecl, needs_metadata_helper: *bool) !NodeId {
    for (class.body) |member| {
        if (member.kind != .constructor) continue;
        if (member.value) |v| {
            if (try buildParamTypesMetadata(arena, alloc, arena.get(v).fn_expr.param_types, needs_metadata_helper)) |metadata| {
                return metadata;
            }
            break;
        }
    }
    needs_metadata_helper.* = true;
    const empty = try arena.push(.{ .array_expr = .{ .elements = &.{}, .span = ZERO_SPAN } });
    return buildMetadataCallExpr(arena, alloc, "design:paramtypes", empty);
}

fn buildReturnTypeMetadata(arena: *ast.Arena, alloc: std.mem.Allocator, info: MemberInfo, needs_metadata_helper: *bool) !?NodeId {
    if (info.kind != .method and info.kind != .getter and info.kind != .setter) return null;
    needs_metadata_helper.* = true;
    const runtime_type = if (info.return_type) |ty|
        try mapTypeToRuntimeExpr(arena, alloc, ty)
    else if (info.is_async)
        try arena.push(.{ .ident = .{ .name = "Promise", .span = ZERO_SPAN } })
    else
        try arena.push(.{ .undefined_ref = .{ .span = ZERO_SPAN } });
    const call = try buildMetadataCallExpr(arena, alloc, "design:returntype", runtime_type);
    return call;
}

fn buildMetadataCallExpr(arena: *ast.Arena, alloc: std.mem.Allocator, key: []const u8, value_expr: NodeId) !NodeId {
    const meta_ident = try arena.push(.{ .ident = .{ .name = "__metadata", .span = ZERO_SPAN } });
    const key_raw = try std.fmt.allocPrint(alloc, "\"{s}\"", .{key});
    const key_node = try arena.push(.{ .str_lit = .{ .raw = key_raw, .value = key, .span = ZERO_SPAN } });
    const args = try alloc.alloc(ast.Argument, 2);
    args[0] = .{ .expr = key_node, .spread = false };
    args[1] = .{ .expr = value_expr, .spread = false };
    return arena.push(.{ .call_expr = .{ .callee = meta_ident, .type_args = &.{}, .args = args, .optional = false, .span = ZERO_SPAN } });
}

fn mapTypeToRuntimeExpr(arena: *ast.Arena, alloc: std.mem.Allocator, type_id: NodeId) !NodeId {
    return switch (arena.get(type_id).*) {
        .ts_keyword => |kw| switch (kw.keyword) {
            .string => try arena.push(.{ .ident = .{ .name = "String", .span = ZERO_SPAN } }),
            .number => try arena.push(.{ .ident = .{ .name = "Number", .span = ZERO_SPAN } }),
            .boolean => try arena.push(.{ .ident = .{ .name = "Boolean", .span = ZERO_SPAN } }),
            else => try arena.push(.{ .ident = .{ .name = "Object", .span = ZERO_SPAN } }),
        },
        .ts_array_type, .ts_tuple => try arena.push(.{ .ident = .{ .name = "Array", .span = ZERO_SPAN } }),
        .ts_type_ref => |tr| try buildTypeRefRuntimeExpr(arena, alloc, tr.name),
        else => try arena.push(.{ .ident = .{ .name = "Object", .span = ZERO_SPAN } }),
    };
}

fn buildTypeRefRuntimeExpr(arena: *ast.Arena, alloc: std.mem.Allocator, name_id: NodeId) !NodeId {
    const root_id = qualifiedNameRoot(arena, name_id);
    const name = arena.get(root_id).ident.name;
    if (std.mem.eql(u8, name, "Promise")) return arena.push(.{ .ident = .{ .name = "Promise", .span = ZERO_SPAN } });
    const runtime_expr = try qualifiedNameToRuntimeExpr(arena, alloc, name_id);
    const typeof_expr = try arena.push(.{ .unary_expr = .{ .op = .typeof, .prefix = true, .argument = root_id, .span = ZERO_SPAN } });
    const undefined_str = try arena.push(.{ .str_lit = .{ .raw = "\"undefined\"", .value = "undefined", .span = ZERO_SPAN } });
    const cond = try arena.push(.{ .binary_expr = .{ .op = .eq3, .left = typeof_expr, .right = undefined_str, .span = ZERO_SPAN } });
    const object_ident = try arena.push(.{ .ident = .{ .name = "Object", .span = ZERO_SPAN } });
    return arena.push(.{ .cond_expr = .{ .cond = cond, .consequent = object_ident, .alternate = runtime_expr, .span = ZERO_SPAN } });
}

fn qualifiedNameRoot(arena: *ast.Arena, name_id: NodeId) NodeId {
    return switch (arena.get(name_id).*) {
        .ts_qualified_name => |q| qualifiedNameRoot(arena, q.left),
        else => name_id,
    };
}

fn qualifiedNameToRuntimeExpr(arena: *ast.Arena, alloc: std.mem.Allocator, name_id: NodeId) !NodeId {
    return switch (arena.get(name_id).*) {
        .ident => name_id,
        .ts_qualified_name => |q| blk: {
            const object = try qualifiedNameToRuntimeExpr(arena, alloc, q.left);
            break :blk try arena.push(.{ .member_expr = .{
                .object = object,
                .prop = q.right,
                .computed = false,
                .optional = false,
                .span = q.span,
            } });
        },
        else => try arena.push(.{ .ident = .{ .name = "Object", .span = ZERO_SPAN } }),
    };
}

fn getKeyName(arena: *const ast.Arena, key_id: NodeId) ?[]const u8 {
    return switch (arena.get(key_id).*) {
        .ident => |i| i.name,
        .str_lit => |s| s.value,
        else => null,
    };
}
