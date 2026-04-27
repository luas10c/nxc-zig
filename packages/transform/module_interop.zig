const std = @import("std");

const ast = @import("ast");
const lexer = @import("lexer");
const json5 = @import("json5");

const Span = lexer.token.Span;
const NodeId = ast.NodeId;

pub const ImportInterop = enum { node, none };

fn hasEsModuleFlag(code: []const u8) bool {
    if (std.mem.indexOf(u8, code, "Object.defineProperty(exports, \"__esModule\", { value: true })") != null) return true;
    if (std.mem.indexOf(u8, code, "exports.__esModule = true") != null) return true;
    return false;
}

// Returns true when Node ESM can statically resolve named exports from this CJS file.
// Packages using `exports.name = ...` or `module.exports.name = ...` are resolvable.
// Packages using only `module.exports = { ... }` are not — need interop.
fn hasNamedExports(code: []const u8) bool {
    var i: usize = 0;
    while (i < code.len) {
        // match "exports." but not "module.exports."
        if (std.mem.startsWith(u8, code[i..], "exports.")) {
            // ensure not preceded by "module."
            const preceded_by_module = i >= 7 and std.mem.eql(u8, code[i - 7 .. i], "module.");
            if (!preceded_by_module) return true;
        }
        // match "module.exports." (property assignment, not module.exports = )
        if (std.mem.startsWith(u8, code[i..], "module.exports.")) return true;
        i += 1;
    }
    return false;
}

const IMPORT_DEFAULT_HELPER: []const u8 =
    "var __importDefault = function(mod) { return mod && mod.__esModule ? mod : { \"default\": mod }; };";

const IMPORT_STAR_HELPER: []const u8 =
    "var __createBinding = Object.create ? function(o, m, k, k2) { if (k2 === undefined) k2 = k; var desc = Object.getOwnPropertyDescriptor(m, k); if (!desc || (\"get\" in desc ? !m.__esModule : desc.writable || desc.configurable)) desc = { enumerable: true, get: function() { return m[k]; } }; Object.defineProperty(o, k2, desc); } : function(o, m, k, k2) { if (k2 === undefined) k2 = k; o[k2] = m[k]; };\nvar __setModuleDefault = Object.create ? function(o, v) { Object.defineProperty(o, \"default\", { enumerable: true, value: v }); } : function(o, v) { o[\"default\"] = v; };\nvar __importStar = function(mod) { if (mod && mod.__esModule) return mod; var result = {}; if (mod != null) for (var k in mod) if (k !== \"default\" && Object.prototype.hasOwnProperty.call(mod, k)) __createBinding(result, mod, k); __setModuleDefault(result, mod); return result; };";

pub fn ensureUseStrict(arena: *ast.Arena, alloc: std.mem.Allocator, program_id: NodeId) !void {
    if (hasUseStrict(arena, program_id)) return;

    const old_body = arena.getMut(program_id).program.body;
    var new_body = std.ArrayListUnmanaged(NodeId).empty;
    try new_body.append(alloc, try buildUseStrictStmt(arena));
    for (old_body) |stmt_id| {
        try new_body.append(alloc, stmt_id);
    }
    arena.getMut(program_id).program.body = try new_body.toOwnedSlice(alloc);
}

pub fn transformEsmInterop(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    src_file: []const u8,
    mode: ImportInterop,
    program_id: NodeId,
) !void {
    if (src_file.len == 0) return;

    const original_body = arena.get(program_id).program.body;
    var new_body = std.ArrayListUnmanaged(NodeId).empty;
    var needs_node_interop_helpers = false;

    for (original_body) |stmt_id| {
        const node = arena.get(stmt_id);
        switch (node.*) {
            .import_decl => |imp| {
                const rewritten = try rewriteEsmInteropImport(arena, alloc, src_file, stmt_id, imp, mode);
                if (rewritten) |stmts| {
                    if (try importUsesNodeInterop(arena, src_file, imp, mode, alloc)) needs_node_interop_helpers = true;
                    try new_body.appendSlice(alloc, stmts);
                } else {
                    try new_body.append(alloc, stmt_id);
                }
            },
            .export_decl => |exp| {
                const rewritten = try rewriteEsmInteropExport(arena, alloc, src_file, exp, mode);
                if (rewritten) |stmts| {
                    if (try exportUsesNodeInterop(arena, src_file, exp, mode, alloc)) needs_node_interop_helpers = true;
                    try new_body.appendSlice(alloc, stmts);
                } else {
                    try new_body.append(alloc, stmt_id);
                }
            },
            else => try new_body.append(alloc, stmt_id),
        }
    }

    if (needs_node_interop_helpers) {
        const zs = Span{ .start = 0, .end = 0, .line = 1, .col = 1 };
        var final_body = std.ArrayListUnmanaged(NodeId).empty;
        try final_body.appendSlice(alloc, try buildNodeInteropHelpers(arena, alloc, zs));
        try final_body.appendSlice(alloc, new_body.items);
        arena.getMut(program_id).program.body = try final_body.toOwnedSlice(alloc);
        return;
    }

    arena.getMut(program_id).program.body = try new_body.toOwnedSlice(alloc);
}

fn hasUseStrict(arena: *ast.Arena, program_id: NodeId) bool {
    const body = arena.get(program_id).program.body;
    for (body) |stmt_id| {
        if (isCommentStmt(arena, stmt_id)) continue;
        return isUseStrictStmt(arena, stmt_id);
    }
    return false;
}

fn isUseStrictStmt(arena: *ast.Arena, stmt_id: NodeId) bool {
    const first = arena.get(stmt_id);
    return switch (first.*) {
        .expr_stmt => |stmt| switch (arena.get(stmt.expr).*) {
            .str_lit => |lit| std.mem.eql(u8, lit.value, "use strict"),
            else => false,
        },
        else => false,
    };
}

fn isCommentStmt(arena: *ast.Arena, stmt_id: NodeId) bool {
    return switch (arena.get(stmt_id).*) {
        .raw_js => |raw| std.mem.startsWith(u8, raw.code, "//") or std.mem.startsWith(u8, raw.code, "/*"),
        else => false,
    };
}

fn buildUseStrictStmt(arena: *ast.Arena) !NodeId {
    const zs = Span{ .start = 0, .end = 0, .line = 1, .col = 1 };
    return arena.push(.{ .expr_stmt = .{
        .expr = try arena.push(.{ .str_lit = .{ .raw = "\"use strict\"", .value = "use strict", .span = zs } }),
        .span = zs,
    } });
}

fn buildEsModuleMark(arena: *ast.Arena, alloc: std.mem.Allocator, span: Span) !NodeId {
    const obj = try arena.push(.{ .ident = .{ .name = "Object", .span = span } });
    const def = try arena.push(.{ .ident = .{ .name = "defineProperty", .span = span } });
    const callee = try arena.push(.{ .member_expr = .{ .object = obj, .prop = def, .computed = false, .optional = false, .span = span } });
    const exports_arg = try arena.push(.{ .ident = .{ .name = "exports", .span = span } });
    const key_arg = try arena.push(.{ .str_lit = .{ .raw = "\"__esModule\"", .value = "__esModule", .span = span } });
    const val_key = try arena.push(.{ .ident = .{ .name = "value", .span = span } });
    const val_val = try arena.push(.{ .bool_lit = .{ .value = true, .span = span } });
    const opts_arg = try arena.push(.{ .object_expr = .{
        .props = try alloc.dupe(ast.ObjectProp, &.{.{ .kv = .{ .key = val_key, .value = val_val, .computed = false, .span = span } }}),
        .span = span,
    } });
    var args = try alloc.alloc(ast.Argument, 3);
    args[0] = .{ .expr = exports_arg, .spread = false };
    args[1] = .{ .expr = key_arg, .spread = false };
    args[2] = .{ .expr = opts_arg, .spread = false };
    const call = try arena.push(.{ .call_expr = .{ .callee = callee, .type_args = &.{}, .args = args, .optional = false, .span = span } });
    return arena.push(.{ .expr_stmt = .{ .expr = call, .span = span } });
}

fn rewriteEsmInteropImport(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    src_file: []const u8,
    stmt_id: NodeId,
    imp: ast.ImportDecl,
    mode: ImportInterop,
) !?[]NodeId {
    _ = stmt_id;
    if (imp.is_type_only) return null;
    if (imp.specifiers.len == 0) return null;

    const source_val = arena.get(imp.source).str_lit.value;
    if (!isBarePackageSpecifier(source_val)) return null;
    const resolved_mode = try resolveImportInterop(source_val, src_file, mode, alloc);

    var has_named = false;
    var has_namespace = false;
    var default_local: ?NodeId = null;
    for (imp.specifiers) |spec| {
        switch (spec.kind) {
            .default => default_local = spec.local,
            .namespace => has_namespace = true,
            .named => has_named = true,
        }
    }

    if (!has_named or has_namespace) return null;

    if (resolved_mode == .node) return rewriteNodeInteropImport(arena, alloc, imp);

    // package has real named exports — leave import as-is
    if (default_local == null) return null;

    const base_local = default_local.?;

    var import_specs = try alloc.alloc(ast.ImportSpecifier, 1);
    import_specs[0] = .{
        .kind = .default,
        .local = base_local,
        .imported = null,
        .is_type_only = false,
        .span = arena.get(base_local).span(),
    };

    var stmts = std.ArrayListUnmanaged(NodeId).empty;
    try stmts.append(alloc, try arena.push(.{ .import_decl = .{
        .specifiers = import_specs,
        .source = imp.source,
        .is_type_only = false,
        .attributes = &.{},
        .span = imp.span,
    } }));

    for (imp.specifiers) |spec| {
        if (spec.kind != .named) continue;

        const imported_name = if (spec.imported) |im| arena.get(im).ident.name else arena.get(spec.local).ident.name;
        const init = if (std.mem.eql(u8, imported_name, "default"))
            base_local
        else
            try arena.push(.{ .member_expr = .{
                .object = base_local,
                .prop = try arena.push(.{ .ident = .{ .name = imported_name, .span = spec.span } }),
                .computed = false,
                .optional = false,
                .span = spec.span,
            } });

        try stmts.append(alloc, try buildConst(arena, alloc, spec.local, init, spec.span));
    }

    const owned = try stmts.toOwnedSlice(alloc);
    return owned;
}

fn rewriteEsmInteropExport(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    src_file: []const u8,
    exp: ast.ExportDecl,
    mode: ImportInterop,
) !?[]NodeId {
    switch (exp.kind) {
        .named => |named| {
            const source = named.source orelse return null;
            if (named.is_type_only or named.specifiers.len == 0) return null;

            const source_val = arena.get(source).str_lit.value;
            if (!try shouldRewriteExportSourceForNodeInterop(source_val, src_file, mode, alloc)) return null;
            return rewriteNodeInteropExport(arena, alloc, src_file, exp);
        },
        .all => |all| {
            const source_val = arena.get(all.source).str_lit.value;
            if (!try shouldRewriteExportSourceForNodeInterop(source_val, src_file, mode, alloc)) return null;
            return rewriteNodeInteropExport(arena, alloc, src_file, exp);
        },
        else => return null,
    }
}

fn shouldRewriteExportSourceForNodeInterop(
    source_val: []const u8,
    src_file: []const u8,
    mode: ImportInterop,
    alloc: std.mem.Allocator,
) !bool {
    if (!isBarePackageSpecifier(source_val)) return false;
    return try resolveImportInterop(source_val, src_file, mode, alloc) == .node;
}

fn rewriteNodeInteropImport(arena: *ast.Arena, alloc: std.mem.Allocator, imp: ast.ImportDecl) !?[]NodeId {
    var stmts = std.ArrayListUnmanaged(NodeId).empty;
    const require_ident = try makeNodeRequireIdent(arena, imp.span);
    const require_call = try buildNamedRequireCall(arena, alloc, require_ident, imp.source, imp.span);

    var default_local: ?NodeId = null;
    var named_specs = std.ArrayListUnmanaged(ast.ImportSpecifier).empty;
    defer named_specs.deinit(alloc);

    for (imp.specifiers) |spec| {
        switch (spec.kind) {
            .default => default_local = spec.local,
            .named => try named_specs.append(alloc, spec),
            .namespace => return null,
        }
    }

    if (default_local) |local| {
        try stmts.append(alloc, try buildConst(arena, alloc, local, require_call, imp.span));
    }

    if (named_specs.items.len > 0) {
        const named_init = if (default_local) |local| local else require_call;
        const pattern = try buildObjectPatternFromImportSpecifiers(arena, alloc, named_specs.items, imp.span);
        try stmts.append(alloc, try buildConst(arena, alloc, pattern, named_init, imp.span));
    }

    const owned = try stmts.toOwnedSlice(alloc);
    return owned;
}

fn rewriteNodeInteropExport(
    arena: *ast.Arena,
    alloc: std.mem.Allocator,
    src_file: []const u8,
    exp: ast.ExportDecl,
) !?[]NodeId {
    _ = src_file;
    switch (exp.kind) {
        .named => |named| {
            const source = named.source orelse return null;
            if (named.is_type_only or named.specifiers.len == 0) return null;

            const source_val = arena.get(source).str_lit.value;
            if (!isBarePackageSpecifier(source_val)) return null;

            var stmts = std.ArrayListUnmanaged(NodeId).empty;
            const require_ident = try makeNodeRequireIdent(arena, exp.span);
            const require_call = try buildNamedRequireCall(arena, alloc, require_ident, source, exp.span);

            var default_local: ?NodeId = null;
            var pattern_specs = std.ArrayListUnmanaged(ast.ExportSpecifier).empty;
            defer pattern_specs.deinit(alloc);

            for (named.specifiers) |spec| {
                const local_name = arena.get(spec.local).ident.name;
                if (std.mem.eql(u8, local_name, "default")) {
                    default_local = spec.local;
                } else {
                    try pattern_specs.append(alloc, spec);
                }
            }

            if (default_local) |local| {
                try stmts.append(alloc, try buildConst(arena, alloc, local, require_call, exp.span));
            }

            if (pattern_specs.items.len > 0) {
                const pattern_init = if (default_local) |local| local else require_call;
                const pattern = try buildObjectPatternFromExportSpecifiers(arena, alloc, pattern_specs.items, exp.span);
                try stmts.append(alloc, try buildConst(arena, alloc, pattern, pattern_init, exp.span));
            }

            try stmts.append(alloc, try arena.push(.{ .export_decl = .{
                .kind = .{ .named = .{
                    .specifiers = named.specifiers,
                    .source = null,
                    .is_type_only = false,
                } },
                .span = exp.span,
            } }));

            const owned = try stmts.toOwnedSlice(alloc);
            return owned;
        },
        .all => |all| {
            const source_val = arena.get(all.source).str_lit.value;
            if (!isBarePackageSpecifier(source_val)) return null;

            const exported = all.exported orelse return null;
            const local = try arena.push(.{ .ident = .{ .name = arena.get(exported).ident.name, .span = exp.span } });
            const require_ident = try makeNodeRequireIdent(arena, exp.span);
            const require_call = try buildNamedRequireCall(arena, alloc, require_ident, all.source, exp.span);

            var stmts = std.ArrayListUnmanaged(NodeId).empty;
            try stmts.append(alloc, try buildConst(arena, alloc, local, require_call, exp.span));

            var specs = try alloc.alloc(ast.ExportSpecifier, 1);
            specs[0] = .{ .local = local, .exported = exported, .is_type_only = false, .span = exp.span };
            try stmts.append(alloc, try arena.push(.{ .export_decl = .{
                .kind = .{ .named = .{
                    .specifiers = specs,
                    .source = null,
                    .is_type_only = false,
                } },
                .span = exp.span,
            } }));

            const owned = try stmts.toOwnedSlice(alloc);
            return owned;
        },
        else => return null,
    }
}

fn buildNodeInteropHelpers(arena: *ast.Arena, alloc: std.mem.Allocator, span: Span) ![]NodeId {
    const create_require_imported = try arena.push(.{ .ident = .{ .name = "createRequire", .span = span } });
    const create_require_local = try arena.push(.{ .ident = .{ .name = "createRequire", .span = span } });
    const module_source = try arena.push(.{ .str_lit = .{ .raw = "\"node:module\"", .value = "node:module", .span = span } });

    var import_specs = try alloc.alloc(ast.ImportSpecifier, 1);
    import_specs[0] = .{
        .kind = .named,
        .local = create_require_local,
        .imported = create_require_imported,
        .is_type_only = false,
        .span = span,
    };

    const import_decl = try arena.push(.{ .import_decl = .{
        .specifiers = import_specs,
        .source = module_source,
        .is_type_only = false,
        .attributes = &.{},
        .span = span,
    } });

    const import_meta = try arena.push(.{ .import_meta = .{ .span = span } });
    const dirname_ident = try arena.push(.{ .ident = .{ .name = "dirname", .span = span } });
    const import_meta_dirname = try arena.push(.{ .member_expr = .{ .object = import_meta, .prop = dirname_ident, .computed = false, .optional = false, .span = span } });

    var args = try alloc.alloc(ast.Argument, 1);
    args[0] = .{ .expr = import_meta_dirname, .spread = false };
    const create_require_call = try arena.push(.{ .call_expr = .{ .callee = create_require_imported, .type_args = &.{}, .args = args, .optional = false, .span = span } });
    const require_ident = try makeNodeRequireIdent(arena, span);
    const require_decl = try buildConst(arena, alloc, require_ident, create_require_call, span);

    return alloc.dupe(NodeId, &.{ import_decl, require_decl });
}

fn makeNodeRequireIdent(arena: *ast.Arena, span: Span) !NodeId {
    return arena.push(.{ .ident = .{ .name = "require", .span = span } });
}

fn buildNamedRequireCall(arena: *ast.Arena, alloc: std.mem.Allocator, require_ident: NodeId, source: NodeId, span: Span) !NodeId {
    var args = try alloc.alloc(ast.Argument, 1);
    args[0] = .{ .expr = source, .spread = false };
    return arena.push(.{ .call_expr = .{ .callee = require_ident, .type_args = &.{}, .args = args, .optional = false, .span = span } });
}

fn buildObjectPatternFromImportSpecifiers(arena: *ast.Arena, alloc: std.mem.Allocator, specs: []const ast.ImportSpecifier, span: Span) !NodeId {
    var props = try alloc.alloc(ast.ObjectPatProp, specs.len);
    for (specs, 0..) |spec, i| {
        const local_name = arena.get(spec.local).ident.name;
        const key_name = if (spec.imported) |im| arena.get(im).ident.name else local_name;
        const key = try arena.push(.{ .ident = .{ .name = key_name, .span = spec.span } });
        props[i] = .{ .assign = .{
            .key = key,
            .value = if (std.mem.eql(u8, key_name, local_name)) null else spec.local,
            .computed = false,
            .span = spec.span,
        } };
    }
    return arena.push(.{ .object_pat = .{ .props = props, .rest = null, .span = span } });
}

fn buildObjectPatternFromExportSpecifiers(arena: *ast.Arena, alloc: std.mem.Allocator, specs: []const ast.ExportSpecifier, span: Span) !NodeId {
    var props = try alloc.alloc(ast.ObjectPatProp, specs.len);
    for (specs, 0..) |spec, i| {
        const key_name = arena.get(spec.local).ident.name;
        const key = try arena.push(.{ .ident = .{ .name = key_name, .span = spec.span } });
        props[i] = .{ .assign = .{ .key = key, .value = null, .computed = false, .span = spec.span } };
    }
    return arena.push(.{ .object_pat = .{ .props = props, .rest = null, .span = span } });
}

fn makeInteropLocal(arena: *ast.Arena, alloc: std.mem.Allocator, source_val: []const u8, span: Span) !NodeId {
    const name = try makeGeneratedModuleName(source_val, alloc);
    return arena.push(.{ .ident = .{ .name = name, .span = span } });
}

fn buildDefaultImportDecl(arena: *ast.Arena, alloc: std.mem.Allocator, local: NodeId, source: NodeId, span: Span) !NodeId {
    var specs = try alloc.alloc(ast.ImportSpecifier, 1);
    specs[0] = .{
        .kind = .default,
        .local = local,
        .imported = null,
        .is_type_only = false,
        .span = arena.get(local).span(),
    };
    return arena.push(.{ .import_decl = .{
        .specifiers = specs,
        .source = source,
        .is_type_only = false,
        .attributes = &.{},
        .span = span,
    } });
}

fn isBarePackageSpecifier(specifier: []const u8) bool {
    if (specifier.len == 0) return false;
    if (std.mem.startsWith(u8, specifier, "./") or std.mem.startsWith(u8, specifier, "../")) return false;
    if (std.mem.startsWith(u8, specifier, "/")) return false;
    if (std.mem.indexOf(u8, specifier, "://") != null) return false;
    if (std.mem.startsWith(u8, specifier, "node:")) return false;
    return true;
}

fn resolveImportInterop(specifier: []const u8, src_file: []const u8, configured: ImportInterop, alloc: std.mem.Allocator) !ImportInterop {
    if (!isBarePackageSpecifier(specifier)) return configured;
    const module_path = try resolvePackageEntryPath(specifier, src_file, alloc) orelse return .none;
    defer alloc.free(module_path);
    const code = (try readTextFile(module_path, alloc)) orelse return .none;
    defer alloc.free(code);
    if (hasEsModuleFlag(code) or hasNamedExports(code)) return .none;
    return configured;
}

fn importUsesNodeInterop(
    arena: *ast.Arena,
    src_file: []const u8,
    imp: ast.ImportDecl,
    configured: ImportInterop,
    alloc: std.mem.Allocator,
) !bool {
    if (imp.is_type_only or imp.specifiers.len == 0) return false;

    var has_named = false;
    var has_namespace = false;
    for (imp.specifiers) |spec| {
        switch (spec.kind) {
            .namespace => has_namespace = true,
            .named => has_named = true,
            else => {},
        }
    }

    if (!has_named or has_namespace) return false;
    return try resolveImportInterop(arena.get(imp.source).str_lit.value, src_file, configured, alloc) == .node;
}

fn exportUsesNodeInterop(
    arena: *ast.Arena,
    src_file: []const u8,
    exp: ast.ExportDecl,
    configured: ImportInterop,
    alloc: std.mem.Allocator,
) !bool {
    const source = switch (exp.kind) {
        .named => |named| named.source orelse return false,
        .all => |all| all.source,
        else => return false,
    };

    return try resolveImportInterop(arena.get(source).str_lit.value, src_file, configured, alloc) == .node;
}

fn packageName(specifier: []const u8) []const u8 {
    if (specifier[0] == '@') {
        var slash_count: usize = 0;
        for (specifier, 0..) |c, i| {
            if (c != '/') continue;
            slash_count += 1;
            if (slash_count == 2) return specifier[0..i];
        }
        return specifier;
    }

    const slash = std.mem.indexOfScalar(u8, specifier, '/') orelse return specifier;
    return specifier[0..slash];
}

fn packageSubpath(specifier: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    const pkg = packageName(specifier);
    if (specifier.len == pkg.len) return alloc.dupe(u8, ".");
    return std.fmt.allocPrint(alloc, ".{s}", .{specifier[pkg.len..]});
}

fn resolvePackageEntryPath(specifier: []const u8, src_file: []const u8, alloc: std.mem.Allocator) !?[]const u8 {
    const package_name = packageName(specifier);
    const subpath = try packageSubpath(specifier, alloc);
    defer alloc.free(subpath);
    const package_dir = try findPackageDir(src_file, package_name, alloc) orelse return null;
    defer alloc.free(package_dir);

    if (!std.mem.eql(u8, subpath, ".")) {
        const subpath_fs = subpath[2..];
        const exact_path = try std.fs.path.join(alloc, &.{ package_dir, subpath_fs });
        switch (try pathKind(exact_path)) {
            .file => return exact_path,
            .directory => {
                if (try resolveDirectoryEntryPath(exact_path, alloc)) |entry| {
                    alloc.free(exact_path);
                    return entry;
                }
            },
            .missing => {},
        }
        alloc.free(exact_path);

        if (std.fs.path.extension(subpath_fs).len == 0) {
            const js_path = try std.fmt.allocPrint(alloc, "{s}/{s}.js", .{ package_dir, subpath_fs });
            if (try pathKind(js_path) == .file) return js_path;
            alloc.free(js_path);
        }

        return null;
    }

    const package_json_path = try std.fs.path.join(alloc, &.{ package_dir, "package.json" });
    defer alloc.free(package_json_path);
    if (try readJsonFile(package_json_path, alloc)) |parsed| {
        defer parsed.deinit();
        if (parsed.value == .object) {
            if (parsed.value.object.get("main")) |main_value| {
                if (main_value == .string) {
                    const main_path = try std.fs.path.join(alloc, &.{ package_dir, main_value.string });
                    if (try pathExists(main_path)) return main_path;
                    alloc.free(main_path);
                }
            }
        }
    }

    const index_js_path = try std.fs.path.join(alloc, &.{ package_dir, "index.js" });
    if (try pathExists(index_js_path)) return index_js_path;
    alloc.free(index_js_path);
    return null;
}

fn findPackageDir(src_file: []const u8, package_name: []const u8, alloc: std.mem.Allocator) !?[]const u8 {
    var current_dir = try alloc.dupe(u8, std.fs.path.dirname(src_file) orelse ".");
    defer alloc.free(current_dir);
    while (true) {
        const candidate = try std.fs.path.join(alloc, &.{ current_dir, "node_modules", package_name });
        if (try pathExists(candidate)) return candidate;
        alloc.free(candidate);

        const parent = std.fs.path.dirname(current_dir) orelse {
            // dirname("src") = null — still need to try CWD "."
            if (std.mem.eql(u8, current_dir, ".")) return null;
            const next_dir = try alloc.dupe(u8, ".");
            alloc.free(current_dir);
            current_dir = next_dir;
            continue;
        };
        if (std.mem.eql(u8, parent, current_dir)) return null;
        const next_dir = try alloc.dupe(u8, parent);
        alloc.free(current_dir);
        current_dir = next_dir;
    }
}

fn pathExists(path: []const u8) !bool {
    return try pathKind(path) != .missing;
}

const PathKind = enum { missing, file, directory };

fn pathKind(path: []const u8) !PathKind {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return .missing,
        else => return err,
    };
    defer _ = std.os.linux.close(fd);
    var probe: [1]u8 = undefined;
    _ = std.posix.read(fd, probe[0..]) catch |err| switch (err) {
        error.IsDir => return .directory,
        else => return err,
    };
    return .file;
}

fn readTextFile(path: []const u8, alloc: std.mem.Allocator) !?[]u8 {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer _ = std.os.linux.close(fd);

    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(alloc);
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &tmp) catch |err| switch (err) {
            error.IsDir => return null,
            else => return err,
        };
        if (n == 0) break;
        try buf.appendSlice(alloc, tmp[0..n]);
    }

    return try buf.toOwnedSlice(alloc);
}

fn readJsonFile(path: []const u8, alloc: std.mem.Allocator) !?std.json.Parsed(std.json.Value) {
    const content = (try readTextFile(path, alloc)) orelse return null;
    defer alloc.free(content);
    return try json5.parse(content, alloc);
}

fn resolveDirectoryEntryPath(dir_path: []const u8, alloc: std.mem.Allocator) !?[]u8 {
    const package_json_path = try std.fs.path.join(alloc, &.{ dir_path, "package.json" });
    defer alloc.free(package_json_path);
    if (try readJsonFile(package_json_path, alloc)) |parsed| {
        defer parsed.deinit();
        if (parsed.value == .object) {
            if (parsed.value.object.get("main")) |main_value| {
                if (main_value == .string) {
                    const main_path = try std.fs.path.join(alloc, &.{ dir_path, main_value.string });
                    if (try pathKind(main_path) == .file) return main_path;
                    alloc.free(main_path);
                }
            }
        }
    }

    const index_js_path = try std.fs.path.join(alloc, &.{ dir_path, "index.js" });
    if (try pathKind(index_js_path) == .file) return index_js_path;
    alloc.free(index_js_path);
    return null;
}

fn buildConst(arena: *ast.Arena, alloc: std.mem.Allocator, id: NodeId, init: NodeId, span: Span) !NodeId {
    return arena.push(.{ .var_decl = .{
        .kind = .@"const",
        .declarators = try alloc.dupe(ast.VarDeclarator, &.{.{ .id = id, .init = init, .span = span }}),
        .span = span,
    } });
}

fn makeGeneratedModuleName(source_val: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(alloc);

    for (source_val, 0..) |c, i| {
        const is_valid = std.ascii.isAlphanumeric(c) or c == '_' or c == '$';
        if (is_valid) {
            if (out.items.len == 0 and std.ascii.isDigit(c)) try out.append(alloc, '_');
            try out.append(alloc, c);
            continue;
        }

        if (i == 0 and c == '@') continue;
        if (out.items.len == 0 or out.items[out.items.len - 1] == '_') continue;
        try out.append(alloc, '_');
    }

    if (out.items.len == 0) try out.append(alloc, '_');
    if (out.items[out.items.len - 1] == '_' and out.items.len > 1) _ = out.pop();

    return out.toOwnedSlice(alloc);
}
