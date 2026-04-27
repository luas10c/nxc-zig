const std = @import("std");

pub const Span = struct {
    start: u32,
    end: u32,
    line: u32,
    col: u32,

    pub fn len(self: Span) u32 {
        return self.end - self.start;
    }
};

pub const TokenKind = enum {
    // Literals
    number,
    string,
    template_head,
    template_middle,
    template_tail,
    template_no_sub,
    regex,

    // Identifier
    ident,
    private_name, // #field

    // JS keywords
    kw_var, kw_let, kw_const,
    kw_function, kw_return,
    kw_if, kw_else,
    kw_for, kw_while, kw_do,
    kw_break, kw_continue,
    kw_switch, kw_case, kw_default,
    kw_throw, kw_try, kw_catch, kw_finally,
    kw_new, kw_delete, kw_typeof, kw_instanceof, kw_void,
    kw_in, kw_of,
    kw_class, kw_extends, kw_super, kw_this,
    kw_import, kw_export, kw_from, kw_as,
    kw_async, kw_await, kw_yield,
    kw_static, kw_get, kw_set,
    kw_true, kw_false, kw_null,
    kw_with, kw_debugger,

	// TS keywords (contextual)
	kw_type, kw_interface, kw_namespace, kw_declare,
	kw_abstract, kw_override, kw_implements, kw_readonly,
	kw_satisfies, kw_keyof, kw_infer, kw_never, kw_unknown,
	kw_is, kw_enum, kw_module, kw_using, kw_accessor,

    // Punctuators
    lparen, rparen,
    lbrace, rbrace,
    lbracket, rbracket,
    semicolon, colon, comma,
    dot, dotdotdot,
    question,
    at,

    // Operators
    eq, eq2, eq3,
    bang, bang_eq, bang_eq2,
    plus, plus_eq, plus2,
    minus, minus_eq, minus2,
    star, star_eq, star2, star2_eq,
    slash, slash_eq,
    percent, percent_eq,
    lt, lt_eq, lt2, lt2_eq,
    gt, gt_eq, gt2, gt2_eq, gt3, gt3_eq,
    amp, amp_eq, amp2, amp2_eq,
    pipe, pipe_eq, pipe2, pipe2_eq,
    caret, caret_eq,
    tilde,
    arrow,
    question2,
    question2_eq,
    question_dot,

    // JSX
    jsx_text,

    // Special
    eof,
    invalid,
};

pub const Token = struct {
    kind: TokenKind,
    span: Span,
    raw: []const u8,
};

const kw_map = std.StaticStringMap(TokenKind).initComptime(.{
    .{ "var", .kw_var },         .{ "let", .kw_let },
    .{ "const", .kw_const },     .{ "function", .kw_function },
    .{ "return", .kw_return },   .{ "if", .kw_if },
    .{ "else", .kw_else },       .{ "for", .kw_for },
    .{ "while", .kw_while },     .{ "do", .kw_do },
    .{ "break", .kw_break },     .{ "continue", .kw_continue },
    .{ "switch", .kw_switch },   .{ "case", .kw_case },
    .{ "default", .kw_default }, .{ "throw", .kw_throw },
    .{ "try", .kw_try },         .{ "catch", .kw_catch },
    .{ "finally", .kw_finally }, .{ "new", .kw_new },
    .{ "delete", .kw_delete },   .{ "typeof", .kw_typeof },
    .{ "instanceof", .kw_instanceof }, .{ "void", .kw_void },
    .{ "in", .kw_in },           .{ "of", .kw_of },
    .{ "class", .kw_class },     .{ "extends", .kw_extends },
    .{ "super", .kw_super },     .{ "this", .kw_this },
    .{ "import", .kw_import },   .{ "export", .kw_export },
    .{ "from", .kw_from },       .{ "as", .kw_as },
    .{ "async", .kw_async },     .{ "await", .kw_await },
    .{ "yield", .kw_yield },     .{ "static", .kw_static },
    .{ "get", .kw_get },         .{ "set", .kw_set },
    .{ "true", .kw_true },       .{ "false", .kw_false },
    .{ "null", .kw_null },       .{ "with", .kw_with },
    .{ "debugger", .kw_debugger },
    .{ "type", .kw_type },       .{ "interface", .kw_interface },
    .{ "namespace", .kw_namespace }, .{ "declare", .kw_declare },
    .{ "abstract", .kw_abstract }, .{ "override", .kw_override },
    .{ "implements", .kw_implements }, .{ "readonly", .kw_readonly },
    .{ "satisfies", .kw_satisfies }, .{ "keyof", .kw_keyof },
    .{ "infer", .kw_infer },     .{ "never", .kw_never },
    .{ "unknown", .kw_unknown }, .{ "is", .kw_is },
	.{ "enum", .kw_enum }, .{ "module", .kw_module },
	.{ "using", .kw_using }, .{ "accessor", .kw_accessor },
});

pub fn lookupKeyword(s: []const u8) ?TokenKind {
    return kw_map.get(s);
}
