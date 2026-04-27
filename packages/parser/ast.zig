const std = @import("std");
const lexer = @import("lexer");

pub const Span = lexer.token.Span;

pub const NodeId = u32;
pub const NULL_NODE: NodeId = std.math.maxInt(u32);

pub const SourceType = enum { script, module };

pub const Program = struct {
    body: []NodeId,
    source_type: SourceType,
    span: Span,
};

pub const Block = struct {
    body: []NodeId,
    span: Span,
};

pub const VarKind = enum { @"var", let, @"const", using };

pub const VarDeclarator = struct {
    id: NodeId,
    init: ?NodeId,
    span: Span,
};

pub const VarDecl = struct {
    kind: VarKind,
    declarators: []VarDeclarator,
    is_await: bool = false,
    span: Span,
};

pub const FnDecl = struct {
    id: ?NodeId,
    type_params: []TsTypeParam,
    params: []NodeId,
    param_decorators: []const []const NodeId,
    param_types: []const ?NodeId,
    param_access: []const ?Accessibility,
    param_readonly: []const bool,
    body: NodeId,
    return_type: ?NodeId,
    is_async: bool,
    is_generator: bool,
    span: Span,
};

pub const ClassMemberKind = enum { method, getter, setter, field, constructor, static_block, auto_accessor };
pub const Accessibility = enum { public, private, protected };

pub const ClassMember = struct {
    kind: ClassMemberKind,
    key: NodeId,
    value: ?NodeId,
    is_declare: bool,
    is_static: bool,
    is_computed: bool,
    accessibility: ?Accessibility,
    is_abstract: bool,
    is_readonly: bool,
    decorators: []NodeId,
    span: Span,
};

pub const ClassDecl = struct {
    id: ?NodeId,
    type_params: []TsTypeParam,
    super_class: ?NodeId,
    body: []ClassMember,
    decorators: []NodeId,
    span: Span,
};

pub const ReturnStmt = struct {
    argument: ?NodeId,
    span: Span,
};

pub const IfStmt = struct {
    cond: NodeId,
    consequent: NodeId,
    alternate: ?NodeId,
    span: Span,
};

pub const ForKind = enum { plain, in, of };

pub const ForStmt = struct {
    kind: ForKind,
    is_await: bool = false,
    init: ?NodeId,
    cond: ?NodeId,
    update: ?NodeId,
    body: NodeId,
    span: Span,
};

pub const WhileStmt = struct {
    cond: NodeId,
    body: NodeId,
    is_do: bool,
    span: Span,
};

pub const SwitchCase = struct {
    cond: ?NodeId,
    body: []NodeId,
    span: Span,
};

pub const SwitchStmt = struct {
    disc: NodeId,
    cases: []SwitchCase,
    span: Span,
};

pub const CatchClause = struct {
    param: ?NodeId,
    body: NodeId,
    span: Span,
};

pub const TryStmt = struct {
    block: NodeId,
    handler: ?CatchClause,
    finalizer: ?NodeId,
    span: Span,
};

pub const ThrowStmt = struct {
    argument: NodeId,
    span: Span,
};

pub const LabeledStmt = struct {
    label: NodeId,
    body: NodeId,
    span: Span,
};

pub const BreakContinue = struct {
    is_break: bool,
    label: ?NodeId,
    span: Span,
};

pub const ImportSpecKind = enum { named, default, namespace };

pub const ImportSpecifier = struct {
    kind: ImportSpecKind,
    local: NodeId,
    imported: ?NodeId,
    is_type_only: bool,
    is_deferred: bool = false,
    span: Span,
};

pub const ImportAttribute = struct {
    key: []const u8,
    value: []const u8,
};

pub const ImportAttributeSyntax = enum {
    none,
    with,
    assert,
};

pub const ImportDecl = struct {
    specifiers: []ImportSpecifier,
    source: NodeId,
    is_type_only: bool,
    is_deferred: bool = false,
    attributes: []ImportAttribute,
    attribute_syntax: ImportAttributeSyntax = .none,
    span: Span,
};

pub const ExportSpecifier = struct {
    local: NodeId,
    exported: NodeId,
    is_type_only: bool,
    span: Span,
};

pub const ExportNamed = struct {
    specifiers: []ExportSpecifier,
    source: ?NodeId,
    is_type_only: bool,
    attributes: []ImportAttribute = &.{},
    attribute_syntax: ImportAttributeSyntax = .none,
};

pub const ExportAll = struct {
    exported: ?NodeId,
    source: NodeId,
    is_type_only: bool = false,
    attributes: []ImportAttribute = &.{},
    attribute_syntax: ImportAttributeSyntax = .none,
};

pub const ExportDeclKind = union(enum) {
    named: ExportNamed,
    default_expr: NodeId,
    default_decl: NodeId,
    all: ExportAll,
    decl: NodeId,
};

pub const ExportDecl = struct {
    kind: ExportDeclKind,
    span: Span,
};

pub const Ident = struct {
    name: []const u8,
    span: Span,
};

pub const NumLit = struct {
    raw: []const u8,
    span: Span,
};

pub const StrLit = struct {
    raw: []const u8,
    value: []const u8,
    span: Span,
};

pub const BoolLit = struct {
    value: bool,
    span: Span,
};

pub const NullLit = struct { span: Span };
pub const UndefinedRef = struct { span: Span };

pub const BinOp = enum {
    eq2,
    eq3,
    neq,
    neq2,
    lt,
    lte,
    gt,
    gte,
    plus,
    minus,
    star,
    slash,
    percent,
    star2,
    amp,
    pipe,
    caret,
    amp2,
    pipe2,
    question2,
    lt2,
    gt2,
    gt3,
    in,
    instanceof,
    comma,
};

pub const BinaryExpr = struct {
    op: BinOp,
    left: NodeId,
    right: NodeId,
    span: Span,
};

pub const UnaryOp = enum { plus, minus, bang, tilde, typeof, void, delete };

pub const UnaryExpr = struct {
    op: UnaryOp,
    prefix: bool,
    argument: NodeId,
    span: Span,
};

pub const UpdateOp = enum { plus2, minus2 };

pub const UpdateExpr = struct {
    op: UpdateOp,
    prefix: bool,
    argument: NodeId,
    span: Span,
};

pub const AssignOp = enum {
    eq,
    plus_eq,
    minus_eq,
    star_eq,
    slash_eq,
    percent_eq,
    star2_eq,
    lt2_eq,
    gt2_eq,
    gt3_eq,
    amp_eq,
    pipe_eq,
    caret_eq,
    amp2_eq,
    pipe2_eq,
    question2_eq,
};

pub const AssignExpr = struct {
    op: AssignOp,
    left: NodeId,
    right: NodeId,
    span: Span,
};

pub const Argument = struct {
    expr: NodeId,
    spread: bool,
};

pub const CallExpr = struct {
    callee: NodeId,
    type_args: []NodeId,
    args: []Argument,
    optional: bool,
    span: Span,
};

pub const MemberExpr = struct {
    object: NodeId,
    prop: NodeId,
    computed: bool,
    optional: bool,
    span: Span,
};

pub const NewExpr = struct {
    callee: NodeId,
    type_args: []NodeId,
    args: []Argument,
    span: Span,
};

pub const SeqExpr = struct {
    exprs: []NodeId,
    span: Span,
};

pub const CondExpr = struct {
    cond: NodeId,
    consequent: NodeId,
    alternate: NodeId,
    span: Span,
};

pub const ArrowFn = struct {
    type_params: []TsTypeParam,
    params: []NodeId,
    body: NodeId,
    is_async: bool,
    is_expr_body: bool,
    span: Span,
};

pub const FnExpr = struct {
    id: ?NodeId,
    type_params: []TsTypeParam,
    params: []NodeId,
    param_decorators: []const []const NodeId,
    param_types: []const ?NodeId,
    param_access: []const ?Accessibility,
    param_readonly: []const bool,
    body: NodeId,
    return_type: ?NodeId,
    is_async: bool,
    is_generator: bool,
    span: Span,
};

pub const ClassExpr = struct {
    id: ?NodeId,
    type_params: []TsTypeParam,
    super_class: ?NodeId,
    body: []ClassMember,
    span: Span,
};

pub const KvProp = struct {
    key: NodeId,
    value: NodeId,
    computed: bool,
    span: Span,
};

pub const MethodProp = struct {
    key: NodeId,
    value: NodeId,
    kind: ClassMemberKind,
    computed: bool,
    span: Span,
};

pub const ObjectProp = union(enum) {
    kv: KvProp,
    shorthand: NodeId,
    spread: NodeId,
    method: MethodProp,
};

pub const ObjectExpr = struct {
    props: []ObjectProp,
    span: Span,
};

pub const ArrayExpr = struct {
    elements: []?NodeId,
    span: Span,
};

pub const TemplateElem = struct {
    raw: []const u8,
    span: Span,
};

pub const TemplateLit = struct {
    quasis: []TemplateElem,
    exprs: []NodeId,
    span: Span,
};

pub const TaggedTemplate = struct {
    tag: NodeId,
    quasi: NodeId,
    span: Span,
};

pub const SpreadElement = struct {
    argument: NodeId,
    span: Span,
};

pub const YieldExpr = struct {
    argument: ?NodeId,
    delegate: bool,
    span: Span,
};

pub const AwaitExpr = struct {
    argument: NodeId,
    span: Span,
};

pub const RestElement = struct {
    argument: NodeId,
    span: Span,
};

pub const AssignPat = struct {
    left: NodeId,
    right: NodeId,
    span: Span,
};

pub const ObjectPatProp = union(enum) {
    assign: struct { key: NodeId, value: ?NodeId, computed: bool, span: Span },
    rest: NodeId,
};

pub const ObjectPat = struct {
    props: []ObjectPatProp,
    rest: ?NodeId,
    span: Span,
};

pub const ArrayPat = struct {
    elements: []?NodeId,
    rest: ?NodeId,
    span: Span,
};

pub const TsTypeAnnotation = struct {
    type_node: NodeId,
    span: Span,
};

pub const TsTypeRef = struct {
    name: NodeId,
    type_args: []NodeId,
    span: Span,
};

pub const TsQualifiedName = struct {
    left: NodeId,
    right: NodeId,
    span: Span,
};

pub const TsUnionType = struct {
    types: []NodeId,
    span: Span,
};

pub const TsIntersectionType = struct {
    types: []NodeId,
    span: Span,
};

pub const TsArrayType = struct {
    elem: NodeId,
    span: Span,
};

pub const TsTupleType = struct {
    types: []NodeId,
    span: Span,
};

pub const TsKeyword = enum {
    any,
    unknown,
    never,
    void_kw,
    undefined_kw,
    null_kw,
    boolean,
    number,
    string,
    bigint,
    symbol,
    object,
};

pub const TsKeywordType = struct {
    keyword: TsKeyword,
    span: Span,
};

pub const TsTypeMemberKind = union(enum) {
    prop: struct { key: NodeId, type_ann: ?NodeId, optional: bool, readonly: bool },
    method: struct { key: NodeId, params: []NodeId, ret: ?NodeId },
    index: struct { param: NodeId, type_ann: NodeId },
};

pub const TsTypeMember = struct {
    kind: TsTypeMemberKind,
    span: Span,
};

pub const TsTypeParam = struct {
    name: NodeId,
    constraint: ?NodeId,
    default_type: ?NodeId,
    span: Span,
};

pub const TsInterfaceDecl = struct {
    id: NodeId,
    extends: []NodeId,
    body: []TsTypeMember,
    type_params: []TsTypeParam,
    span: Span,
};

pub const TsTypeAliasDecl = struct {
    id: NodeId,
    type_params: []TsTypeParam,
    type_ann: NodeId,
    span: Span,
};

pub const TsEnumMember = struct {
    id: NodeId,
    init: ?NodeId,
    span: Span,
};

pub const TsEnumDecl = struct {
    id: NodeId,
    members: []TsEnumMember,
    is_const: bool,
    span: Span,
};

pub const TsNamespaceDecl = struct {
    id: NodeId,
    body: []NodeId,
    span: Span,
};

pub const TsNonNullExpr = struct {
    expr: NodeId,
    span: Span,
};

pub const TsAsExpr = struct {
    expr: NodeId,
    type_ann: NodeId,
    span: Span,
};

pub const TsSatisfiesExpr = struct {
    expr: NodeId,
    type_ann: NodeId,
    span: Span,
};

pub const TsInstantiationExpr = struct {
    expr: NodeId,
    type_args: []NodeId,
    span: Span,
};

pub const TsTypeAssert = struct {
    expr: NodeId,
    type_ann: NodeId,
    span: Span,
};

pub const JsxOpening = struct {
    name: NodeId,
    attrs: []JsxAttr,
    self_closing: bool,
    span: Span,
};

pub const JsxClosing = struct {
    name: NodeId,
    span: Span,
};

pub const JsxAttr = union(enum) {
    named: struct { name: NodeId, value: ?NodeId, span: Span },
    spread: NodeId,
};

pub const JsxElement = struct {
    opening: JsxOpening,
    children: []NodeId,
    closing: ?JsxClosing,
    span: Span,
};

pub const JsxFragment = struct {
    children: []NodeId,
    span: Span,
};

pub const JsxExprContainer = struct {
    expr: ?NodeId,
    span: Span,
};

pub const JsxText = struct {
    raw: []const u8,
    span: Span,
};

pub const JsxName = struct {
    name: []const u8,
    span: Span,
};

pub const JsxMemberExpr = struct {
    object: NodeId,
    prop: NodeId,
    span: Span,
};

pub const Node = union(enum) {
    program: Program,
    block: Block,
    expr_stmt: struct { expr: NodeId, span: Span },
    empty_stmt: struct { span: Span },
    raw_js: struct { code: []const u8, span: Span },
    var_decl: VarDecl,
    fn_decl: FnDecl,
    class_decl: ClassDecl,
    return_stmt: ReturnStmt,
    if_stmt: IfStmt,
    for_stmt: ForStmt,
    while_stmt: WhileStmt,
    switch_stmt: SwitchStmt,
    try_stmt: TryStmt,
    throw_stmt: ThrowStmt,
    labeled_stmt: LabeledStmt,
    break_continue: BreakContinue,
    debugger_stmt: struct { span: Span },
    import_decl: ImportDecl,
    export_decl: ExportDecl,
    ident: Ident,
    num_lit: NumLit,
    str_lit: StrLit,
    bool_lit: BoolLit,
    null_lit: NullLit,
    undefined_ref: UndefinedRef,
    regex_lit: struct { raw: []const u8, span: Span },
    binary_expr: BinaryExpr,
    unary_expr: UnaryExpr,
    update_expr: UpdateExpr,
    assign_expr: AssignExpr,
    call_expr: CallExpr,
    member_expr: MemberExpr,
    new_expr: NewExpr,
    new_target: struct { span: Span },
    seq_expr: SeqExpr,
    cond_expr: CondExpr,
    arrow_fn: ArrowFn,
    fn_expr: FnExpr,
    class_expr: ClassExpr,
    object_expr: ObjectExpr,
    array_expr: ArrayExpr,
    template_lit: TemplateLit,
    tagged_template: TaggedTemplate,
    spread_elem: SpreadElement,
    yield_expr: YieldExpr,
    await_expr: AwaitExpr,
    rest_elem: RestElement,
    assign_pat: AssignPat,
    object_pat: ObjectPat,
    array_pat: ArrayPat,
    ts_type_annotation: TsTypeAnnotation,
    ts_type_ref: TsTypeRef,
    ts_qualified_name: TsQualifiedName,
    ts_union: TsUnionType,
    ts_intersection: TsIntersectionType,
    ts_array_type: TsArrayType,
    ts_tuple: TsTupleType,
    ts_keyword: TsKeywordType,
    ts_interface: TsInterfaceDecl,
    ts_type_alias: TsTypeAliasDecl,
    ts_enum: TsEnumDecl,
    ts_namespace: TsNamespaceDecl,
    ts_non_null: TsNonNullExpr,
    ts_as_expr: TsAsExpr,
    ts_satisfies: TsSatisfiesExpr,
    ts_instantiation: TsInstantiationExpr,
    ts_type_assert: TsTypeAssert,
    jsx_element: JsxElement,
    jsx_fragment: JsxFragment,
    jsx_expr_container: JsxExprContainer,
    jsx_text: JsxText,
    jsx_name: JsxName,
    jsx_member_expr: JsxMemberExpr,
    import_meta: struct { span: Span },
    import_call: struct { source: NodeId, attributes: []ImportAttribute, span: Span },

    pub fn span(self: *const Node) Span {
        return switch (self.*) {
            .program => |n| n.span,
            .block => |n| n.span,
            .expr_stmt => |n| n.span,
            .empty_stmt => |n| n.span,
            .raw_js => |n| n.span,
            .var_decl => |n| n.span,
            .fn_decl => |n| n.span,
            .class_decl => |n| n.span,
            .return_stmt => |n| n.span,
            .if_stmt => |n| n.span,
            .for_stmt => |n| n.span,
            .while_stmt => |n| n.span,
            .switch_stmt => |n| n.span,
            .try_stmt => |n| n.span,
            .throw_stmt => |n| n.span,
            .labeled_stmt => |n| n.span,
            .break_continue => |n| n.span,
            .debugger_stmt => |n| n.span,
            .import_decl => |n| n.span,
            .export_decl => |n| n.span,
            .ident => |n| n.span,
            .num_lit => |n| n.span,
            .str_lit => |n| n.span,
            .bool_lit => |n| n.span,
            .null_lit => |n| n.span,
            .undefined_ref => |n| n.span,
            .regex_lit => |n| n.span,
            .binary_expr => |n| n.span,
            .unary_expr => |n| n.span,
            .update_expr => |n| n.span,
            .assign_expr => |n| n.span,
            .call_expr => |n| n.span,
            .member_expr => |n| n.span,
            .new_expr => |n| n.span,
            .new_target => |n| n.span,
            .seq_expr => |n| n.span,
            .cond_expr => |n| n.span,
            .arrow_fn => |n| n.span,
            .fn_expr => |n| n.span,
            .class_expr => |n| n.span,
            .object_expr => |n| n.span,
            .array_expr => |n| n.span,
            .template_lit => |n| n.span,
            .tagged_template => |n| n.span,
            .spread_elem => |n| n.span,
            .yield_expr => |n| n.span,
            .await_expr => |n| n.span,
            .rest_elem => |n| n.span,
            .assign_pat => |n| n.span,
            .object_pat => |n| n.span,
            .array_pat => |n| n.span,
            .ts_type_annotation => |n| n.span,
            .ts_type_ref => |n| n.span,
            .ts_qualified_name => |n| n.span,
            .ts_union => |n| n.span,
            .ts_intersection => |n| n.span,
            .ts_array_type => |n| n.span,
            .ts_tuple => |n| n.span,
            .ts_keyword => |n| n.span,
            .ts_interface => |n| n.span,
            .ts_type_alias => |n| n.span,
            .ts_enum => |n| n.span,
            .ts_namespace => |n| n.span,
            .ts_non_null => |n| n.span,
            .ts_as_expr => |n| n.span,
            .ts_satisfies => |n| n.span,
            .ts_instantiation => |n| n.span,
            .ts_type_assert => |n| n.span,
            .jsx_element => |n| n.span,
            .jsx_fragment => |n| n.span,
            .jsx_expr_container => |n| n.span,
            .jsx_text => |n| n.span,
            .jsx_name => |n| n.span,
            .jsx_member_expr => |n| n.span,
            .import_meta => |n| n.span,
            .import_call => |n| n.span,
        };
    }
};

pub const Arena = struct {
    nodes: std.ArrayListUnmanaged(Node),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) Arena {
        return .{ .nodes = .empty, .alloc = alloc };
    }

    pub fn deinit(self: *Arena) void {
        self.nodes.deinit(self.alloc);
    }

    pub fn push(self: *Arena, node: Node) !NodeId {
        const id: NodeId = @intCast(self.nodes.items.len);
        try self.nodes.append(self.alloc, node);
        return id;
    }

    pub fn get(self: *const Arena, id: NodeId) *const Node {
        return &self.nodes.items[id];
    }

    pub fn getMut(self: *Arena, id: NodeId) *Node {
        return &self.nodes.items[id];
    }
};
