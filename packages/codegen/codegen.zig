const std = @import("std");

const ast = @import("ast");
const lexer = @import("lexer");
const sourcemap = @import("sourcemap");

const Comment = lexer.Lexer.Comment;
const NodeId = ast.NodeId;
const NULL_NODE = ast.NULL_NODE;

pub const CodegenOptions = struct {
    pretty: bool = true,
    indent_size: u8 = 2,
    source_map: bool = false,
    source_name: []const u8 = "",
    source_root: ?[]const u8 = null,
    keep_import_attributes: bool = false,
    import_attribute_syntax: ast.ImportAttributeSyntax = .with,
    remove_comments: bool = true,
    comments: []const Comment = &.{},
};

pub const Codegen = struct {
    arena: *const ast.Arena,
    buf: std.ArrayListUnmanaged(u8),
    alloc: std.mem.Allocator,
    merge_scopes: std.ArrayListUnmanaged(std.StringHashMapUnmanaged(void)),
    merge_decl_counts: std.ArrayListUnmanaged(std.StringHashMapUnmanaged(usize)),
    indent_level: u32,
    gen_line: u32,
    gen_col: u32,
    source_map: ?sourcemap.SourceMap,
    source_idx: u32,
    last_mapping_line: ?u32,
    last_mapping_col: ?u32,
    comment_index: usize,
    opts: CodegenOptions,

    pub fn init(arena: *const ast.Arena, alloc: std.mem.Allocator, opts: CodegenOptions) !Codegen {
        var cg = Codegen{
            .arena = arena,
            .buf = .empty,
            .alloc = alloc,
            .merge_scopes = .empty,
            .merge_decl_counts = .empty,
            .indent_level = 0,
            .gen_line = 0,
            .gen_col = 0,
            .source_map = null,
            .source_idx = 0,
            .last_mapping_line = null,
            .last_mapping_col = null,
            .comment_index = 0,
            .opts = opts,
        };

        if (opts.source_map) {
            var sm = sourcemap.SourceMap.init(alloc);
            sm.source_root = opts.source_root;
            cg.source_idx = try sm.addSource(opts.source_name);
            cg.source_map = sm;
        }

        return cg;
    }

    pub fn deinit(self: *Codegen) void {
        for (self.merge_scopes.items) |*scope| {
            scope.deinit(self.alloc);
        }
        self.merge_scopes.deinit(self.alloc);

        for (self.merge_decl_counts.items) |*counts| {
            counts.deinit(self.alloc);
        }
        self.merge_decl_counts.deinit(self.alloc);

        if (self.source_map) |*sm| {
            sm.deinit();
        }
    }

    pub fn finish(self: *Codegen) ![]const u8 {
        return self.buf.toOwnedSlice(self.alloc);
    }

    pub fn finishSourceMap(self: *Codegen) !?[]const u8 {
        if (self.source_map) |*sm| {
            return try sm.toJsonAlloc();
        }
        return null;
    }

    fn w(self: *Codegen, s: []const u8) !void {
        try self.buf.appendSlice(self.alloc, s);
        self.advanceGenerated(s);
    }

    fn wb(self: *Codegen, b: u8) !void {
        try self.buf.append(self.alloc, b);
        const single = [1]u8{b};
        self.advanceGenerated(&single);
    }

    fn wf(self: *Codegen, comptime fmt: []const u8, args: anytype) !void {
        const rendered = try std.fmt.allocPrint(self.alloc, fmt, args);
        try self.w(rendered);
    }

    fn nl(self: *Codegen) !void {
        if (!self.opts.pretty) return;
        try self.wb('\n');
        var j: u32 = 0;
        while (j < self.indent_level * self.opts.indent_size) : (j += 1) try self.wb(' ');
    }

    fn indent(self: *Codegen) void {
        self.indent_level += 1;
    }
    fn dedent(self: *Codegen) void {
        if (self.indent_level > 0) self.indent_level -= 1;
    }

    fn isCommentRaw(code: []const u8) bool {
        return std.mem.startsWith(u8, code, "//") or std.mem.startsWith(u8, code, "/*");
    }

    fn emitCommentsBefore(self: *Codegen, pos: u32) !void {
        if (self.opts.remove_comments) return;
        while (self.comment_index < self.opts.comments.len and self.opts.comments[self.comment_index].span.start <= pos) {
            try self.w(self.opts.comments[self.comment_index].raw);
            if (self.opts.pretty and !std.mem.endsWith(u8, self.opts.comments[self.comment_index].raw, "\n")) {
                try self.wb('\n');
            }
            self.comment_index += 1;
        }
    }

    fn emitRemainingComments(self: *Codegen) !void {
        if (self.opts.remove_comments) return;
        while (self.comment_index < self.opts.comments.len) {
            try self.w(self.opts.comments[self.comment_index].raw);
            if (self.opts.pretty and !std.mem.endsWith(u8, self.opts.comments[self.comment_index].raw, "\n")) {
                try self.wb('\n');
            }
            self.comment_index += 1;
        }
    }

    pub fn gen(self: *Codegen, id: NodeId) anyerror!void {
        const node = self.arena.get(id);
        try self.emitCommentsBefore(node.span().start);
        try self.recordNodeMapping(node);
        switch (node.*) {
            .program => |p| try self.genProgram(p),
            .block => |b| try self.genBlock(b),
            .expr_stmt => |s| {
                try self.gen(s.expr);
                try self.w(";");
            },
            .empty_stmt => {},
            .raw_js => |r| {
                if (!isCommentRaw(r.code)) try self.w(r.code);
            },
            .var_decl => |v| try self.genVarDecl(v),
            .fn_decl => |f| try self.genFnDecl(f),
            .class_decl => |c| try self.genClassDecl(c),
            .return_stmt => |r| try self.genReturn(r),
            .if_stmt => |s| try self.genIf(s),
            .for_stmt => |s| try self.genFor(s),
            .while_stmt => |s| try self.genWhile(s),
            .switch_stmt => |s| try self.genSwitch(s),
            .try_stmt => |s| try self.genTry(s),
            .throw_stmt => |s| {
                try self.w("throw ");
                try self.gen(s.argument);
                try self.w(";");
            },
            .break_continue => |s| try self.genBreakContinue(s),
            .debugger_stmt => try self.w("debugger;"),
            .labeled_stmt => |s| {
                try self.gen(s.label);
                try self.w(": ");
                try self.gen(s.body);
            },
            .import_decl => |imp| try self.genImport(imp),
            .export_decl => |exp| try self.genExport(exp),
            .ident => |i| try self.w(i.name),
            .num_lit => |n| try self.w(n.raw),
            .str_lit => |s| try self.w(s.raw),
            .bool_lit => |b| try self.w(if (b.value) "true" else "false"),
            .null_lit => try self.w("null"),
            .undefined_ref => try self.w("undefined"),
            .regex_lit => |r| try self.w(r.raw),
            .binary_expr => |b| try self.genBinary(b),
            .unary_expr => |u| try self.genUnary(u),
            .update_expr => |u| try self.genUpdate(u),
            .assign_expr => |a| try self.genAssign(a),
            .call_expr => |c| try self.genCall(c),
            .member_expr => |m| try self.genMember(m),
            .new_expr => |n| try self.genNew(n),
            .new_target => try self.w("new.target"),
            .seq_expr => |s| try self.genSeq(s),
            .cond_expr => |c| try self.genCond(c),
            .arrow_fn => |f| try self.genArrow(f),
            .fn_expr => |f| try self.genFnExpr(f),
            .class_expr => |c| try self.genClassExpr(c),
            .object_expr => |o| try self.genObject(o),
            .array_expr => |a| try self.genArray(a),
            .template_lit => |t| try self.genTemplate(t),
            .tagged_template => |t| {
                try self.gen(t.tag);
                try self.genTemplate(self.arena.get(t.quasi).template_lit);
            },
            .spread_elem => |s| {
                try self.w("...");
                if (self.arena.get(s.argument).* == .cond_expr) {
                    try self.w("(");
                    try self.gen(s.argument);
                    try self.w(")");
                } else try self.gen(s.argument);
            },
            .yield_expr => |y| try self.genYield(y),
            .await_expr => |a| {
                try self.w("await ");
                try self.gen(a.argument);
            },
            .rest_elem => |r| {
                try self.w("...");
                try self.gen(r.argument);
            },
            .assign_pat => |p| {
                try self.gen(p.left);
                try self.w(" = ");
                try self.gen(p.right);
            },
            .object_pat => |p| try self.genObjectPat(p),
            .array_pat => |p| try self.genArrayPat(p),
            .ts_enum => |e| try self.genEnum(e),
            // TS type nodes: already stripped or skipped
            .ts_interface, .ts_type_alias, .ts_type_ref, .ts_qualified_name, .ts_union, .ts_intersection, .ts_array_type, .ts_tuple, .ts_keyword, .ts_type_annotation => {},
            .ts_non_null => |e| try self.gen(e.expr),
            .ts_as_expr => |e| try self.gen(e.expr),
            .ts_satisfies => |e| try self.gen(e.expr),
            .ts_instantiation => |e| try self.gen(e.expr),
            .ts_type_assert => |e| try self.gen(e.expr),
            .ts_namespace => |n| try self.genNamespaceDecl(n),
            // JSX: should be transformed before codegen
            .jsx_element, .jsx_fragment, .jsx_text, .jsx_expr_container, .jsx_name, .jsx_member_expr => {},
            .import_meta => try self.w("import.meta"),
            .import_call => |c| {
                try self.w("import(");
                try self.gen(c.source);
                if (self.opts.keep_import_attributes and c.attributes.len > 0) {
                    try self.w(", { with: { ");
                    for (c.attributes, 0..) |a, i| {
                        if (i > 0) try self.w(", ");
                        try self.wf("{s}: \"{s}\"", .{ a.key, a.value });
                    }
                    try self.w(" } }");
                }
                try self.w(")");
            },
        }
    }

    fn advanceGenerated(self: *Codegen, text: []const u8) void {
        for (text) |c| {
            if (c == '\n') {
                self.gen_line += 1;
                self.gen_col = 0;
            } else {
                self.gen_col += 1;
            }
        }
    }

    fn recordNodeMapping(self: *Codegen, node: *const ast.Node) !void {
        if (self.source_map == null) return;
        if (node.* == .program) return;

        const sp = node.span();
        if (sp.start == sp.end) return;
        if (sp.line == 0 or sp.col == 0) return;

        if (self.last_mapping_line != null and self.last_mapping_col != null and
            self.last_mapping_line.? == self.gen_line and self.last_mapping_col.? == self.gen_col)
        {
            return;
        }

        try self.source_map.?.addMapping(.{
            .gen_line = self.gen_line,
            .gen_col = self.gen_col,
            .src_line = sp.line - 1,
            .src_col = sp.col - 1,
            .source_idx = self.source_idx,
        });
        self.last_mapping_line = self.gen_line;
        self.last_mapping_col = self.gen_col;
    }

    fn genProgram(self: *Codegen, p: ast.Program) !void {
        try self.genScopedStatements(p.body);
        try self.emitRemainingComments();
    }

    fn genScopedStatements(self: *Codegen, body: []const NodeId) !void {
        try self.pushMergeScope(body);
        defer self.popMergeScope();

        for (body, 0..) |stmt, i| {
            if (i > 0) try self.nl();
            try self.gen(stmt);
            try self.recordScopeBindingsForStmt(stmt);
            self.consumeMergeDeclForStmt(stmt);
        }
    }

    fn pushMergeScope(self: *Codegen, body: []const NodeId) !void {
        try self.merge_scopes.append(self.alloc, .empty);
        try self.merge_decl_counts.append(self.alloc, .empty);
        var i: usize = 0;
        while (i < body.len) : (i += 1) {
            if (self.mergeDeclNameOfStmt(body[i])) |name| {
                const counts = &self.merge_decl_counts.items[self.merge_decl_counts.items.len - 1];
                const cur = counts.get(name) orelse 0;
                counts.put(self.alloc, name, cur + 1) catch {};
            }
        }
    }

    fn popMergeScope(self: *Codegen) void {
        if (self.merge_scopes.items.len == 0) return;

        self.merge_scopes.items[self.merge_scopes.items.len - 1].deinit(self.alloc);
        self.merge_decl_counts.items[self.merge_decl_counts.items.len - 1].deinit(self.alloc);

        self.merge_scopes.items.len -= 1;
        self.merge_decl_counts.items.len -= 1;
    }

    fn currentMergeScope(self: *Codegen) ?*std.StringHashMapUnmanaged(void) {
        if (self.merge_scopes.items.len == 0) return null;
        return &self.merge_scopes.items[self.merge_scopes.items.len - 1];
    }

    fn scopeContainsName(self: *Codegen, name: []const u8) bool {
        const scope = self.currentMergeScope() orelse return false;
        return scope.contains(name);
    }

    fn currentMergeDeclCounts(self: *Codegen) ?*std.StringHashMapUnmanaged(usize) {
        if (self.merge_decl_counts.items.len == 0) return null;
        return &self.merge_decl_counts.items[self.merge_decl_counts.items.len - 1];
    }

    fn pendingMergeDeclCount(self: *Codegen, name: []const u8) usize {
        const counts = self.currentMergeDeclCounts() orelse return 0;
        return counts.get(name) orelse 0;
    }

    fn shouldUseVarForMergeDecl(self: *Codegen, name: []const u8) bool {
        return self.pendingMergeDeclCount(name) > 1;
    }

    fn recordNameInScope(self: *Codegen, name: []const u8) !void {
        const scope = self.currentMergeScope() orelse return;
        try scope.put(self.alloc, name, {});
    }

    fn recordScopeBindingsForStmt(self: *Codegen, stmt_id: NodeId) !void {
        switch (self.arena.get(stmt_id).*) {
            .var_decl => |v| {
                for (v.declarators) |d| switch (self.arena.get(d.id).*) {
                    .ident => |id| try self.recordNameInScope(id.name),
                    else => {},
                };
            },
            .fn_decl => |f| if (f.id) |id| try self.recordNameInScope(self.arena.get(id).ident.name),
            .class_decl => |c| if (c.id) |id| try self.recordNameInScope(self.arena.get(id).ident.name),
            .ts_enum => |e| try self.recordNameInScope(self.arena.get(e.id).ident.name),
            .ts_namespace => |n| try self.recordNameInScope(self.arena.get(n.id).ident.name),
            .export_decl => |e| switch (e.kind) {
                .decl => |id| try self.recordScopeBindingsForStmt(id),
                .default_decl => |id| try self.recordScopeBindingsForStmt(id),
                else => {},
            },
            else => {},
        }
    }

    fn mergeDeclNameOfStmt(self: *Codegen, stmt_id: NodeId) ?[]const u8 {
        return switch (self.arena.get(stmt_id).*) {
            .ts_enum => |e| self.arena.get(e.id).ident.name,
            .ts_namespace => |n| self.arena.get(n.id).ident.name,
            .export_decl => |e| switch (e.kind) {
                .decl => |id| self.mergeDeclNameOfStmt(id),
                .default_decl => |id| self.mergeDeclNameOfStmt(id),
                else => null,
            },
            else => null,
        };
    }

    fn consumeMergeDeclForStmt(self: *Codegen, stmt_id: NodeId) void {
        const name = self.mergeDeclNameOfStmt(stmt_id) orelse return;
        const counts = self.currentMergeDeclCounts() orelse return;
        const cur = counts.get(name) orelse return;
        if (cur <= 1) {
            _ = counts.remove(name);
        } else {
            counts.put(self.alloc, name, cur - 1) catch {};
        }
    }

    fn genBlock(self: *Codegen, b: ast.Block) !void {
        try self.w("{");
        self.indent();
        for (b.body) |stmt| {
            try self.nl();
            try self.gen(stmt);
        }
        self.dedent();
        if (b.body.len > 0) try self.nl();
        try self.w("}");
    }

    fn genVarDeclNoSemi(self: *Codegen, v: ast.VarDecl) !void {
        if (v.is_await) try self.w("await ");
        try self.w(switch (v.kind) {
            .@"var" => "var",
            .let => "let",
            .@"const" => "const",
            .using => "using",
        });
        try self.wb(' ');
        for (v.declarators, 0..) |d, i| {
            if (i > 0) try self.w(", ");
            try self.gen(d.id);
            if (d.init) |init_val| {
                try self.w(" = ");
                try self.gen(init_val);
            }
        }
    }

    fn genVarDecl(self: *Codegen, v: ast.VarDecl) !void {
        try self.genVarDeclNoSemi(v);
        try self.w(";");
    }

    fn genFnDecl(self: *Codegen, f: ast.FnDecl) !void {
        if (f.is_async) try self.w("async ");
        try self.w("function");
        if (f.is_generator) try self.wb('*');
        if (f.id) |id| {
            try self.wb(' ');
            try self.gen(id);
        }
        try self.w("(");
        for (f.params, 0..) |p, i| {
            if (i > 0) try self.w(", ");
            try self.gen(p);
        }
        try self.w(") ");
        try self.gen(f.body);
    }

    fn genClassDecl(self: *Codegen, c: ast.ClassDecl) !void {
        try self.w("class");
        if (c.id) |id| {
            try self.wb(' ');
            try self.gen(id);
        }
        if (c.super_class) |sc| {
            try self.w(" extends ");
            const wrap_super = self.classHeritageNeedsParens(sc);
            if (wrap_super) try self.w("(");
            try self.gen(sc);
            if (wrap_super) try self.w(")");
        }
        try self.w(" {");
        self.indent();
        for (c.body) |m| {
            try self.nl();
            try self.genClassMember(m);
        }
        self.dedent();
        if (c.body.len > 0) try self.nl();
        try self.w("}");
    }

    fn genClassExpr(self: *Codegen, c: ast.ClassExpr) !void {
        try self.w("class");
        if (c.id) |id| {
            try self.wb(' ');
            try self.gen(id);
        }
        if (c.super_class) |sc| {
            try self.w(" extends ");
            const wrap_super = self.classHeritageNeedsParens(sc);
            if (wrap_super) try self.w("(");
            try self.gen(sc);
            if (wrap_super) try self.w(")");
        }
        try self.w(" {");
        self.indent();
        for (c.body) |m| {
            try self.nl();
            try self.genClassMember(m);
        }
        self.dedent();
        if (c.body.len > 0) try self.nl();
        try self.w("}");
    }

    fn classHeritageNeedsParens(self: *Codegen, node: ast.NodeId) bool {
        return switch (self.arena.get(node).*) {
            .cond_expr,
            .seq_expr,
            .assign_expr,
            .arrow_fn,
            => true,
            else => false,
        };
    }

    fn genClassMember(self: *Codegen, m: ast.ClassMember) !void {
        if (m.is_static) try self.w("static ");
        switch (m.kind) {
            .constructor => {
                try self.w("constructor(");
                if (m.value) |v| {
                    const f = self.arena.get(v).fn_expr;
                    for (f.params, 0..) |p, i| {
                        if (i > 0) try self.w(", ");
                        try self.gen(p);
                    }
                    try self.w(") {");
                    self.indent();
                    for (f.params, 0..) |p, i| {
                        const access = if (i < f.param_access.len) f.param_access[i] else null;
                        const is_property = access != null or (i < f.param_readonly.len and f.param_readonly[i]);
                        if (!is_property) continue;
                        const name = switch (self.arena.get(p).*) {
                            .ident => |id| id.name,
                            else => continue,
                        };
                        try self.nl();
                        try self.wf("this.{s} = {s};", .{ name, name });
                    }
                    const body = self.arena.get(f.body).block;
                    for (body.body) |stmt| {
                        try self.nl();
                        try self.gen(stmt);
                    }
                    self.dedent();
                    if (body.body.len > 0 or hasConstructorPropertyAssignments(f)) try self.nl();
                    try self.w("}");
                } else try self.w(") {}");
            },
            .method, .getter, .setter => {
                if (m.value) |v| {
                    const f = self.arena.get(v).fn_expr;
                    if (f.is_async) try self.w("async ");
                }
                if (m.value) |v| {
                    const f = self.arena.get(v).fn_expr;
                    if (f.is_generator) try self.wb('*');
                }
                if (m.kind == .getter) try self.w("get ");
                if (m.kind == .setter) try self.w("set ");
                if (m.is_computed) try self.w("[");
                try self.gen(m.key);
                if (m.is_computed) try self.w("]");
                if (m.value) |v| {
                    const f = self.arena.get(v).fn_expr;
                    try self.w("(");
                    for (f.params, 0..) |p, i| {
                        if (i > 0) try self.w(", ");
                        try self.gen(p);
                    }
                    try self.w(") ");
                    try self.gen(f.body);
                }
            },
            .field => {
                if (m.is_computed) try self.w("[");
                try self.gen(m.key);
                if (m.is_computed) try self.w("]");
                if (m.value) |v| {
                    try self.w(" = ");
                    try self.gen(v);
                }
                try self.w(";");
            },
            .auto_accessor => {
                try self.w("accessor ");
                if (m.is_computed) try self.w("[");
                try self.gen(m.key);
                if (m.is_computed) try self.w("]");
                if (m.value) |v| {
                    try self.w(" = ");
                    try self.gen(v);
                }
                try self.w(";");
            },
            .static_block => {
                if (m.value) |v| try self.gen(v);
            },
        }
    }

    fn genReturn(self: *Codegen, r: ast.ReturnStmt) !void {
        try self.w("return");
        if (r.argument) |a| {
            try self.wb(' ');
            try self.gen(a);
        }
        try self.w(";");
    }

    fn genIf(self: *Codegen, s: ast.IfStmt) !void {
        try self.w("if (");
        try self.gen(s.cond);
        try self.w(") ");
        try self.gen(s.consequent);
        if (s.alternate) |alt| {
            try self.w(" else ");
            try self.gen(alt);
        }
    }

    fn genForInit(self: *Codegen, id: NodeId) !void {
        const node = self.arena.get(id);
        if (node.* == .var_decl) try self.genVarDeclNoSemi(node.var_decl) else try self.gen(id);
    }

    fn genFor(self: *Codegen, s: ast.ForStmt) !void {
        switch (s.kind) {
            .plain => {
                try self.w("for (");
                if (s.init) |i| {
                    try self.genForInit(i);
                    try self.w(";");
                } else try self.w(";");
                if (s.cond) |t| {
                    try self.wb(' ');
                    try self.gen(t);
                }
                try self.w(";");
                if (s.update) |u| {
                    try self.wb(' ');
                    try self.gen(u);
                }
                try self.w(") ");
            },
            .in => {
                try self.w("for (");
                if (s.init) |i| try self.genForInit(i);
                try self.w(" in ");
                if (s.update) |r| try self.gen(r);
                try self.w(") ");
            },
            .of => {
                if (s.is_await) try self.w("for await (") else try self.w("for (");
                if (s.init) |i| try self.genForInit(i);
                try self.w(" of ");
                if (s.update) |r| try self.gen(r);
                try self.w(") ");
            },
        }
        try self.gen(s.body);
    }

    fn genWhile(self: *Codegen, s: ast.WhileStmt) !void {
        if (s.is_do) {
            try self.w("do ");
            try self.gen(s.body);
            try self.w(" while (");
            try self.gen(s.cond);
            try self.w(");");
        } else {
            try self.w("while (");
            try self.gen(s.cond);
            try self.w(") ");
            try self.gen(s.body);
        }
    }

    fn genSwitch(self: *Codegen, s: ast.SwitchStmt) !void {
        try self.w("switch (");
        try self.gen(s.disc);
        try self.w(") {");
        self.indent();
        for (s.cases) |c| {
            try self.nl();
            if (c.cond) |t| {
                try self.w("case ");
                try self.gen(t);
                try self.w(":");
            } else try self.w("default:");
            self.indent();
            for (c.body) |stmt| {
                try self.nl();
                try self.gen(stmt);
            }
            self.dedent();
        }
        self.dedent();
        try self.nl();
        try self.w("}");
    }

    fn genTry(self: *Codegen, s: ast.TryStmt) !void {
        try self.w("try ");
        try self.gen(s.block);
        if (s.handler) |h| {
            try self.w(" catch");
            if (h.param) |p| {
                try self.w(" (");
                try self.gen(p);
                try self.w(")");
            }
            try self.wb(' ');
            try self.gen(h.body);
        }
        if (s.finalizer) |f| {
            try self.w(" finally ");
            try self.gen(f);
        }
    }

    fn genBreakContinue(self: *Codegen, s: ast.BreakContinue) !void {
        try self.w(if (s.is_break) "break" else "continue");
        if (s.label) |l| {
            try self.wb(' ');
            try self.gen(l);
        }
        try self.w(";");
    }

    fn genImportAttributes(self: *Codegen, attrs: []const ast.ImportAttribute) !void {
        switch (self.opts.import_attribute_syntax) {
            .assert => try self.w(" assert { "),
            else => try self.w(" with { "),
        }
        for (attrs, 0..) |a, i| {
            if (i > 0) try self.w(", ");
            try self.wf("{s}: \"{s}\"", .{ a.key, a.value });
        }
        try self.w(" }");
    }

    fn genImport(self: *Codegen, imp: ast.ImportDecl) !void {
        if (imp.specifiers.len == 0) {
            try self.w("import ");
            if (imp.is_deferred) try self.w("defer ");
            try self.gen(imp.source);
            if (self.opts.keep_import_attributes and imp.attributes.len > 0)
                try self.genImportAttributes(imp.attributes);
            try self.w(";");
            return;
        }

        try self.w("import ");
        if (imp.is_deferred) {
            try self.w("defer ");
        }

        var named_start: usize = 0;
        for (imp.specifiers, 0..) |s, i| {
            switch (s.kind) {
                .default => {
                    try self.gen(s.local);
                    named_start = i + 1;
                },
                .namespace => {
                    if (i > 0) try self.w(", ");
                    try self.w("* as ");
                    try self.gen(s.local);
                    named_start = i + 1;
                },
                .named => {},
            }
        }
        const named = imp.specifiers[named_start..];
        if (named.len > 0) {
            if (named_start > 0) try self.w(", ");
            try self.w("{ ");
            for (named, 0..) |s, i| {
                if (i > 0) try self.w(", ");
                if (s.imported) |im| {
                    const im_name = self.arena.get(im).ident.name;
                    const local_name = self.arena.get(s.local).ident.name;
                    if (!std.mem.eql(u8, im_name, local_name)) {
                        try self.gen(im);
                        try self.w(" as ");
                    }
                }
                try self.gen(s.local);
            }
            try self.w(" }");
        }
        try self.w(" from ");
        try self.gen(imp.source);
        if (self.opts.keep_import_attributes and imp.attributes.len > 0)
            try self.genImportAttributes(imp.attributes);
        try self.w(";");
    }

    fn genExport(self: *Codegen, exp: ast.ExportDecl) !void {
        switch (exp.kind) {
            .decl => |d| {
                if (self.arena.get(d).* == .ts_namespace) {
                    const ns = self.arena.get(d).ts_namespace;
                    const name = self.arena.get(ns.id).ident.name;
                    try self.genNamespaceDecl(ns);
                    try self.nl();
                    try self.wf("export {{ {s} }};", .{name});
                } else {
                    try self.w("export ");
                    try self.gen(d);
                }
            },
            .default_expr => |e| {
                try self.w("export default ");
                try self.gen(e);
                try self.w(";");
            },
            .default_decl => |d| {
                try self.w("export default ");
                try self.gen(d);
            },
            .named => |n| {
                try self.w("export { ");
                for (n.specifiers, 0..) |s, i| {
                    if (i > 0) try self.w(", ");
                    try self.gen(s.local);
                    const local_name = self.arena.get(s.local).ident.name;
                    const exported_name = self.arena.get(s.exported).ident.name;
                    if (!std.mem.eql(u8, local_name, exported_name)) {
                        try self.w(" as ");
                        try self.gen(s.exported);
                    }
                }
                try self.w(" }");
                if (n.source) |src| {
                    try self.w(" from ");
                    try self.gen(src);
                    if (self.opts.keep_import_attributes and n.attributes.len > 0)
                        try self.genImportAttributes(n.attributes);
                }
                try self.w(";");
            },
            .all => |a| {
                try self.w("export *");
                if (a.exported) |e| {
                    try self.w(" as ");
                    try self.gen(e);
                }
                try self.w(" from ");
                try self.gen(a.source);
                if (self.opts.keep_import_attributes and a.attributes.len > 0)
                    try self.genImportAttributes(a.attributes);
                try self.w(";");
            },
        }
    }

    fn binPrecedence(op: ast.BinOp) u8 {
        return switch (op) {
            .comma => 1,
            .pipe2, .question2 => 3,
            .amp2 => 4,
            .pipe => 5,
            .caret => 6,
            .amp => 7,
            .eq2, .eq3, .neq, .neq2 => 8,
            .lt, .lte, .gt, .gte, .in, .instanceof => 9,
            .lt2, .gt2, .gt3 => 10,
            .plus, .minus => 11,
            .star, .slash, .percent => 12,
            .star2 => 13,
        };
    }

    fn binaryChildNeedsParens(self: *Codegen, child_id: NodeId, parent_op: ast.BinOp, is_right: bool) bool {
        const child = self.arena.get(child_id);
        return switch (child.*) {
            .assign_expr, .seq_expr, .cond_expr, .arrow_fn, .yield_expr => true,
            .binary_expr => |b| {
                const child_prec = binPrecedence(b.op);
                const parent_prec = binPrecedence(parent_op);
                if (child_prec < parent_prec) return true;
                if (child_prec > parent_prec) return false;

                if (parent_op == .star2) {
                    return !is_right;
                }

                if (!is_right) return false;

                return switch (parent_op) {
                    .minus, .slash, .percent, .lt2, .gt2, .gt3, .lt, .lte, .gt, .gte, .in, .instanceof, .eq2, .eq3, .neq, .neq2 => true,
                    else => false,
                };
            },
            else => false,
        };
    }

    fn genBinaryChild(self: *Codegen, child_id: NodeId, parent_op: ast.BinOp, is_right: bool) !void {
        const wrap = self.binaryChildNeedsParens(child_id, parent_op, is_right);
        if (wrap) try self.w("(");
        try self.gen(child_id);
        if (wrap) try self.w(")");
    }

    fn genBinary(self: *Codegen, b: ast.BinaryExpr) !void {
        try self.genBinaryChild(b.left, b.op, false);
        try self.w(switch (b.op) {
            .eq2 => " == ",
            .eq3 => " === ",
            .neq => " != ",
            .neq2 => " !== ",
            .lt => " < ",
            .lte => " <= ",
            .gt => " > ",
            .gte => " >= ",
            .plus => " + ",
            .minus => " - ",
            .star => " * ",
            .slash => " / ",
            .percent => " % ",
            .star2 => " ** ",
            .amp => " & ",
            .pipe => " | ",
            .caret => " ^ ",
            .amp2 => " && ",
            .pipe2 => " || ",
            .question2 => " ?? ",
            .lt2 => " << ",
            .gt2 => " >> ",
            .gt3 => " >>> ",
            .in => " in ",
            .instanceof => " instanceof ",
            .comma => ", ",
        });
        try self.genBinaryChild(b.right, b.op, true);
    }

    fn unaryArgNeedsParens(self: *Codegen, node_id: NodeId) bool {
        return switch (self.arena.get(node_id).*) {
            .binary_expr, .assign_expr, .seq_expr, .cond_expr, .arrow_fn, .yield_expr => true,
            else => false,
        };
    }

    fn genUnary(self: *Codegen, u: ast.UnaryExpr) !void {
        const op = switch (u.op) {
            .plus => "+",
            .minus => "-",
            .bang => "!",
            .tilde => "~",
            .typeof => "typeof ",
            .void => "void ",
            .delete => "delete ",
        };
        const wrap_arg = self.unaryArgNeedsParens(u.argument);
        if (u.prefix) {
            try self.w(op);
            if (wrap_arg) try self.w("(");
            try self.gen(u.argument);
            if (wrap_arg) try self.w(")");
        } else {
            if (wrap_arg) try self.w("(");
            try self.gen(u.argument);
            if (wrap_arg) try self.w(")");
            try self.w(op);
        }
    }

    fn genUpdate(self: *Codegen, u: ast.UpdateExpr) !void {
        const op = if (u.op == .plus2) "++" else "--";
        if (u.prefix) {
            try self.w(op);
            try self.gen(u.argument);
        } else {
            try self.gen(u.argument);
            try self.w(op);
        }
    }

    fn genAssign(self: *Codegen, a: ast.AssignExpr) !void {
        try self.gen(a.left);
        try self.w(switch (a.op) {
            .eq => " = ",
            .plus_eq => " += ",
            .minus_eq => " -= ",
            .star_eq => " *= ",
            .slash_eq => " /= ",
            .percent_eq => " %= ",
            .star2_eq => " **= ",
            .amp_eq => " &= ",
            .pipe_eq => " |= ",
            .caret_eq => " ^= ",
            .lt2_eq => " <<= ",
            .gt2_eq => " >>= ",
            .gt3_eq => " >>>= ",
            .amp2_eq => " &&= ",
            .pipe2_eq => " ||= ",
            .question2_eq => " ??= ",
        });
        try self.gen(a.right);
    }

    fn calleeNeedsParens(self: *Codegen, node_id: NodeId) bool {
        return switch (self.arena.get(node_id).*) {
            .object_expr,
            .fn_expr,
            .class_expr,
            .arrow_fn,
            .binary_expr,
            .unary_expr,
            .update_expr,
            .assign_expr,
            .seq_expr,
            .cond_expr,
            .yield_expr,
            .await_expr,
            => true,
            else => false,
        };
    }

    fn memberObjectNeedsParens(self: *Codegen, node_id: NodeId) bool {
        return switch (self.arena.get(node_id).*) {
            .object_expr,
            .fn_expr,
            .class_expr,
            .binary_expr,
            .unary_expr,
            .update_expr,
            .assign_expr,
            .seq_expr,
            .cond_expr,
            .arrow_fn,
            .yield_expr,
            .await_expr,
            => true,
            else => false,
        };
    }

    fn genCall(self: *Codegen, c: ast.CallExpr) !void {
        const wrap = self.calleeNeedsParens(c.callee);
        if (wrap) try self.w("(");
        try self.gen(c.callee);
        if (wrap) try self.w(")");
        if (c.optional) try self.w("?.");
        try self.w("(");
        for (c.args, 0..) |a, i| {
            if (i > 0) try self.w(", ");
            if (a.spread) try self.w("...");
            try self.gen(a.expr);
        }
        try self.w(")");
    }

    fn genMember(self: *Codegen, m: ast.MemberExpr) !void {
        const wrap_object = self.memberObjectNeedsParens(m.object);
        if (wrap_object) try self.w("(");
        try self.gen(m.object);
        if (wrap_object) try self.w(")");
        if (m.computed) {
            if (m.optional) try self.w("?.");
            try self.w("[");
            try self.gen(m.prop);
            try self.w("]");
        } else {
            if (m.optional) try self.w("?.") else try self.wb('.');
            try self.gen(m.prop);
        }
    }

    fn genNew(self: *Codegen, n: ast.NewExpr) !void {
        const wrap = self.calleeNeedsParens(n.callee);
        try self.w("new ");
        if (wrap) try self.w("(");
        try self.gen(n.callee);
        if (wrap) try self.w(")");
        try self.w("(");
        for (n.args, 0..) |a, i| {
            if (i > 0) try self.w(", ");
            if (a.spread) try self.w("...");
            try self.gen(a.expr);
        }
        try self.w(")");
    }

    fn genSeq(self: *Codegen, s: ast.SeqExpr) !void {
        for (s.exprs, 0..) |e, i| {
            if (i > 0) try self.w(", ");
            try self.gen(e);
        }
    }

    fn genCond(self: *Codegen, c: ast.CondExpr) !void {
        try self.gen(c.cond);
        try self.w(" ? ");
        try self.gen(c.consequent);
        try self.w(" : ");
        try self.gen(c.alternate);
    }

    fn genArrow(self: *Codegen, f: ast.ArrowFn) !void {
        if (f.is_async) try self.w("async ");
        const single_needs_parens = f.params.len == 1 and switch (self.arena.get(f.params[0]).*) {
            .object_pat, .array_pat, .assign_pat, .rest_elem, .object_expr, .array_expr => true,
            else => false,
        };
        if (f.params.len == 1 and !f.is_async and !single_needs_parens) {
            try self.gen(f.params[0]);
        } else {
            try self.w("(");
            for (f.params, 0..) |p, i| {
                if (i > 0) try self.w(", ");
                try self.gen(p);
            }
            try self.w(")");
        }
        try self.w(" => ");
        if (!f.is_expr_body) {
            try self.gen(f.body);
        } else {
            // wrap object literals in parens to avoid ambiguity
            const is_obj = switch (self.arena.get(f.body).*) {
                .object_expr => true,
                else => false,
            };
            if (is_obj) try self.wb('(');
            try self.gen(f.body);
            if (is_obj) try self.wb(')');
        }
    }

    fn genFnExpr(self: *Codegen, f: ast.FnExpr) !void {
        if (f.is_async) try self.w("async ");
        try self.w("function");
        if (f.is_generator) try self.wb('*');
        if (f.id) |id| {
            try self.wb(' ');
            try self.gen(id);
        }
        try self.w("(");
        for (f.params, 0..) |p, i| {
            if (i > 0) try self.w(", ");
            try self.gen(p);
        }
        try self.w(") ");
        try self.gen(f.body);
    }

    fn hasConstructorPropertyAssignments(f: ast.FnExpr) bool {
        for (f.param_access, 0..) |access, i| {
            if (access != null) return true;
            if (i < f.param_readonly.len and f.param_readonly[i]) return true;
        }
        return false;
    }

    fn genObject(self: *Codegen, o: ast.ObjectExpr) !void {
        try self.w("{");
        self.indent();
        for (o.props, 0..) |prop, i| {
            if (i > 0) try self.w(",");
            try self.nl();
            switch (prop) {
                .kv => |kv| {
                    if (kv.computed) try self.w("[");
                    try self.gen(kv.key);
                    if (kv.computed) try self.w("]");
                    try self.w(": ");
                    try self.gen(kv.value);
                },
                .shorthand => |s| try self.gen(s),
                .spread => |s| {
                    try self.w("...");
                    if (self.arena.get(s).* == .cond_expr) {
                        try self.w("(");
                        try self.gen(s);
                        try self.w(")");
                    } else try self.gen(s);
                },
                .method => |m| {
                    const f = self.arena.get(m.value).fn_expr;
                    if (m.kind == .getter) try self.w("get ");
                    if (m.kind == .setter) try self.w("set ");
                    if (f.is_async) try self.w("async ");
                    if (f.is_generator) try self.wb('*');
                    if (m.computed) try self.w("[");
                    try self.gen(m.key);
                    if (m.computed) try self.w("]");
                    try self.w("(");
                    for (f.params, 0..) |p, j| {
                        if (j > 0) try self.w(", ");
                        try self.gen(p);
                    }
                    try self.w(") ");
                    try self.gen(f.body);
                },
            }
        }
        self.dedent();
        if (o.props.len > 0) try self.nl();
        try self.w("}");
    }

    fn genArray(self: *Codegen, a: ast.ArrayExpr) !void {
        try self.w("[");
        for (a.elements, 0..) |elem, i| {
            if (i > 0) try self.w(", ");
            if (elem) |e| try self.gen(e);
        }
        try self.w("]");
    }

    fn genTemplate(self: *Codegen, t: ast.TemplateLit) !void {
        try self.wb('`');
        for (t.quasis, 0..) |q, i| {
            const raw = q.raw;
            // strip surrounding delimiters:
            //   head: `...${  → strip leading ` and trailing ${
            //   middle: }...${  → strip leading } and trailing ${
            //   tail: }...`  → strip leading } and trailing `
            //   no_sub: `...`  → strip both `
            const inner = if (i == 0 and i == t.quasis.len - 1)
                // no_sub: `...`
                if (raw.len >= 2) raw[1 .. raw.len - 1] else ""
            else if (i == 0)
                // head: `...${ — strip ` and ${
                if (raw.len >= 3) raw[1 .. raw.len - 2] else ""
            else if (i == t.quasis.len - 1)
                // tail: }...` — strip } and `
                if (raw.len >= 2) raw[1 .. raw.len - 1] else ""
            else
                // middle: }...${ — strip } and ${
                if (raw.len >= 3) raw[1 .. raw.len - 2] else "";
            try self.w(inner);
            if (i < t.exprs.len) {
                try self.w("${");
                try self.gen(t.exprs[i]);
                try self.wb('}');
            }
        }
        try self.wb('`');
    }

    fn genYield(self: *Codegen, y: ast.YieldExpr) !void {
        try self.w("yield");
        if (y.delegate) try self.wb('*');
        if (y.argument) |a| {
            try self.wb(' ');
            try self.gen(a);
        }
    }

    fn genObjectPat(self: *Codegen, p: ast.ObjectPat) !void {
        try self.w("{ ");
        for (p.props, 0..) |prop, i| {
            if (i > 0) try self.w(", ");
            switch (prop) {
                .assign => |a| {
                    try self.gen(a.key);
                    if (a.value) |v| {
                        const node = self.arena.get(v);
                        if (node.* == .assign_pat and node.assign_pat.left == a.key) {
                            try self.w(" = ");
                            try self.gen(node.assign_pat.right);
                        } else {
                            try self.w(": ");
                            try self.gen(v);
                        }
                    }
                },
                .rest => |r| {
                    try self.w("...");
                    try self.gen(r);
                },
            }
        }
        if (p.rest) |r| {
            if (p.props.len > 0) try self.w(", ");
            try self.w("...");
            try self.gen(r);
        }
        try self.w(" }");
    }

    fn genArrayPat(self: *Codegen, p: ast.ArrayPat) !void {
        try self.w("[");
        for (p.elements, 0..) |elem, i| {
            if (i > 0) try self.w(", ");
            if (elem) |e| try self.gen(e);
        }
        if (p.rest) |r| {
            if (p.elements.len > 0) try self.w(", ");
            try self.w("...");
            try self.gen(r);
        }
        try self.w("]");
    }

    fn genEnum(self: *Codegen, e: ast.TsEnumDecl) !void {
        const name = self.arena.get(e.id).ident.name;
        if (self.scopeContainsName(name))
            try self.wf("{s} = (function(_E) {{", .{name})
        else if (self.shouldUseVarForMergeDecl(name))
            try self.wf("var {s} = (function(_E) {{", .{name})
        else
            try self.wf("var {s} = (function(_E) {{", .{name});
        self.indent();
        try self.nl();
        for (e.members, 0..) |m, i| {
            try self.nl();
            const key = self.arena.get(m.id).ident.name;
            if (m.init) |init_id| {
                try self.wf("_E[_E[\"{s}\"] = ", .{key});
                try self.gen(init_id);
                try self.wf("] = \"{s}\";", .{key});
            } else {
                try self.wf("_E[_E[\"{s}\"] = {d}] = \"{s}\";", .{ key, i, key });
            }
        }
        try self.nl();
        try self.w("return _E;");
        self.dedent();
        try self.nl();
        try self.wf("}})({s} || {{}});", .{name});
    }

    fn genNamespaceDecl(self: *Codegen, ns: ast.TsNamespaceDecl) !void {
        const name = self.arena.get(ns.id).ident.name;
        if (self.scopeContainsName(name))
            try self.wf("{s} = (function(_N) {{", .{name})
        else if (self.shouldUseVarForMergeDecl(name))
            try self.wf("var {s} = (function(_N) {{", .{name})
        else
            try self.wf("const {s} = (function(_N) {{", .{name});
        self.indent();
        try self.nl();
        try self.pushMergeScope(ns.body);
        defer self.popMergeScope();
        for (ns.body, 0..) |stmt, i| {
            if (i > 0) try self.nl();
            try self.nl();
            try self.genNamespaceBodyStmt(stmt, "_N");
            try self.recordScopeBindingsForStmt(stmt);
            self.consumeMergeDeclForStmt(stmt);
        }
        try self.nl();
        try self.w("return _N;");
        self.dedent();
        try self.nl();
        try self.wf("}})({s} || {{}});", .{name});
    }

    fn genNamespaceBodyStmt(self: *Codegen, stmt_id: NodeId, ns_name: []const u8) !void {
        switch (self.arena.get(stmt_id).*) {
            .export_decl => |exp| switch (exp.kind) {
                .decl => |decl_id| {
                    try self.gen(decl_id);
                    try self.genNamespaceDeclAssignments(decl_id, ns_name);
                },
                .named => |n| if (n.source == null) {
                    for (n.specifiers) |s| {
                        try self.nl();
                        try self.wf("{s}.", .{ns_name});
                        try self.gen(s.exported);
                        try self.w(" = ");
                        try self.gen(s.local);
                        try self.w(";");
                    }
                },
                .default_expr => |expr_id| {
                    try self.wf("{s}.default = ", .{ns_name});
                    try self.gen(expr_id);
                    try self.w(";");
                },
                .default_decl => |decl_id| {
                    try self.gen(decl_id);
                    try self.nl();
                    try self.wf("{s}.default = ", .{ns_name});
                    try self.genNamespaceDeclName(decl_id);
                    try self.w(";");
                },
                .all => {},
            },
            else => try self.gen(stmt_id),
        }
    }

    fn genNamespaceDeclAssignments(self: *Codegen, decl_id: NodeId, ns_name: []const u8) !void {
        switch (self.arena.get(decl_id).*) {
            .var_decl => |v| {
                for (v.declarators) |d| {
                    switch (self.arena.get(d.id).*) {
                        .ident => |id| {
                            try self.nl();
                            try self.wf("{s}.{s} = {s};", .{ ns_name, id.name, id.name });
                        },
                        else => {},
                    }
                }
            },
            .fn_decl => |f| if (f.id) |id| {
                const name = self.arena.get(id).ident.name;
                try self.nl();
                try self.wf("{s}.{s} = {s};", .{ ns_name, name, name });
            },
            .class_decl => |c| if (c.id) |id| {
                const name = self.arena.get(id).ident.name;
                try self.nl();
                try self.wf("{s}.{s} = {s};", .{ ns_name, name, name });
            },
            .ts_enum => |e| {
                const name = self.arena.get(e.id).ident.name;
                try self.nl();
                try self.wf("{s}.{s} = {s};", .{ ns_name, name, name });
            },
            .ts_namespace => |n| {
                const name = self.arena.get(n.id).ident.name;
                try self.nl();
                try self.wf("{s}.{s} = {s};", .{ ns_name, name, name });
            },
            else => {},
        }
    }

    fn genNamespaceDeclName(self: *Codegen, decl_id: NodeId) !void {
        switch (self.arena.get(decl_id).*) {
            .fn_decl => |f| if (f.id) |id| return self.gen(id),
            .class_decl => |c| if (c.id) |id| return self.gen(id),
            .ts_namespace => |n| return self.gen(n.id),
            .ts_enum => |e| return self.gen(e.id),
            else => {},
        }
        try self.w("undefined");
    }
};
