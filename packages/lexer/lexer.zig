const std = @import("std");
const tok = @import("token.zig");
pub const Token = tok.Token;
pub const TokenKind = tok.TokenKind;
pub const Span = tok.Span;
pub const token = tok;

pub const LexerMode = enum {
    normal,
    jsx,
    jsx_attr,
    type_pos,
};

pub const Lexer = struct {
    pub const Comment = struct {
        raw: []const u8,
        span: Span,
    };

    src: []const u8,
    pos: u32,
    line: u32,
    line_start: u32,
    mode: LexerMode,
    peeked: ?Token,
    last_kind: ?TokenKind,
    // template literal depth tracking: each entry is the brace depth when we entered the ${
    template_stack: [16]u8 = [_]u8{0} ** 16,
    template_depth: u8 = 0,
    brace_depth: u8 = 0,
    pending_comments: [32]Comment = undefined,
    pending_comments_len: u8 = 0,

    pub fn init(src: []const u8) Lexer {
        return .{
            .src = src,
            .pos = 0,
            .line = 1,
            .line_start = 0,
            .mode = .normal,
            .peeked = null,
            .last_kind = null,
        };
    }

    pub fn peek(self: *Lexer) Token {
        if (self.peeked == null) {
            self.peeked = self.nextInner();
        }
        return self.peeked.?;
    }

    pub fn next(self: *Lexer) Token {
        if (self.peeked) |t| {
            self.peeked = null;
            self.last_kind = t.kind;
            return t;
        }
        const t = self.nextInner();
        self.last_kind = t.kind;
        return t;
    }

    pub fn expect(self: *Lexer, kind: TokenKind) !Token {
        const t = self.next();
        if (t.kind != kind) return error.UnexpectedToken;
        return t;
    }

    pub fn takePendingComments(self: *Lexer) []const Comment {
        const comments = self.pending_comments[0..self.pending_comments_len];
        self.pending_comments_len = 0;
        return comments;
    }

    fn col(self: *const Lexer) u32 {
        return self.pos - self.line_start + 1;
    }

    fn spanFrom(self: *const Lexer, start: u32, start_line: u32, start_col: u32) Span {
        return .{
            .start = start,
            .end = self.pos,
            .line = start_line,
            .col = start_col,
        };
    }

    fn cur(self: *const Lexer) u8 {
        if (self.pos >= self.src.len) return 0;
        return self.src[self.pos];
    }

    fn peek1(self: *const Lexer) u8 {
        if (self.pos + 1 >= self.src.len) return 0;
        return self.src[self.pos + 1];
    }

    fn advance(self: *Lexer) void {
        if (self.pos < self.src.len) self.pos += 1;
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.src.len) {
            if (self.matchInvisibleWhitespace()) continue;
            switch (self.src[self.pos]) {
                ' ', '\t', '\r' => self.pos += 1,
                '\n' => {
                    self.pos += 1;
                    self.line += 1;
                    self.line_start = self.pos;
                },
                else => break,
            }
        }
    }

    fn matchInvisibleWhitespace(self: *Lexer) bool {
        if (self.pos + 2 < self.src.len) {
            const b0 = self.src[self.pos];
            const b1 = self.src[self.pos + 1];
            const b2 = self.src[self.pos + 2];

            // UTF-8 BOM / zero-width no-break space (U+FEFF).
            if (b0 == 0xEF and b1 == 0xBB and b2 == 0xBF) {
                self.pos += 3;
                return true;
            }

            // Zero-width space (U+200B).
            if (b0 == 0xE2 and b1 == 0x80 and b2 == 0x8B) {
                self.pos += 3;
                return true;
            }
        }
        return false;
    }

    fn skipLineComment(self: *Lexer) void {
        while (self.pos < self.src.len and self.src[self.pos] != '\n') {
            self.pos += 1;
        }
    }

    fn skipBlockComment(self: *Lexer) bool {
        self.pos += 2;
        while (self.pos + 1 < self.src.len) {
            if (self.src[self.pos] == '\n') {
                self.line += 1;
                self.line_start = self.pos + 1;
            }
            if (self.src[self.pos] == '*' and self.src[self.pos + 1] == '/') {
                self.pos += 2;
                return true;
            }
            self.pos += 1;
        }
        return false;
    }

    fn pushPendingComment(self: *Lexer, start: u32, start_line: u32, start_col: u32) void {
        if (self.pending_comments_len >= self.pending_comments.len) return;
        self.pending_comments[self.pending_comments_len] = .{
            .raw = self.src[start..self.pos],
            .span = self.spanFrom(start, start_line, start_col),
        };
        self.pending_comments_len += 1;
    }

    fn readString(self: *Lexer, quote: u8) Token {
        const start = self.pos;
        const sl = self.line;
        const sc = self.col();
        self.advance();
        var closed = false;
        while (self.pos < self.src.len) {
            const c = self.src[self.pos];
            if (c == '\\') {
                self.pos += 2;
                continue;
            }
            if (c == '\n' or c == '\r') break;
            self.advance();
            if (c == quote) {
                closed = true;
                break;
            }
        }
        if (!closed) {
            self.pos = start + 1;
            return .{
                .kind = .invalid,
                .span = self.spanFrom(start, sl, sc),
                .raw = self.src[start..self.pos],
            };
        }
        return .{
            .kind = .string,
            .span = self.spanFrom(start, sl, sc),
            .raw = self.src[start..self.pos],
        };
    }

    fn readTemplate(self: *Lexer) Token {
        const start = self.pos;
        const sl = self.line;
        const sc = self.col();
        self.advance();
        var has_expr = false;
        var closed = false;
        while (self.pos < self.src.len) {
            const c = self.src[self.pos];
            if (c == '\\') {
                self.pos += 2;
                continue;
            }
            if (c == '\n') {
                self.line += 1;
                self.line_start = self.pos + 1;
            }
            if (c == '$' and self.peek1() == '{') {
                self.pos += 2;
                has_expr = true;
                break;
            }
            self.advance();
            if (c == '`') {
                closed = true;
                break;
            }
        }
        if (!has_expr and !closed) {
            self.pos = start + 1;
            return .{
                .kind = .invalid,
                .span = self.spanFrom(start, sl, sc),
                .raw = self.src[start..self.pos],
            };
        }
        const kind: TokenKind = if (has_expr) .template_head else .template_no_sub;
        if (kind == .template_head) {
            // push current brace depth so we know when ${...} closes
            if (self.template_depth < 16) {
                self.template_stack[self.template_depth] = self.brace_depth;
                self.template_depth += 1;
            }
        }
        return .{
            .kind = kind,
            .span = self.spanFrom(start, sl, sc),
            .raw = self.src[start..self.pos],
        };
    }

    fn readTemplateMiddleOrTail(self: *Lexer) Token {
        const start = self.pos;
        const sl = self.line;
        const sc = self.col();
        // starts after }
        var has_expr = false;
        while (self.pos < self.src.len) {
            const c = self.src[self.pos];
            if (c == '\\') {
                self.pos += 2;
                continue;
            }
            if (c == '\n') {
                self.line += 1;
                self.line_start = self.pos + 1;
            }
            if (c == '$' and self.peek1() == '{') {
                self.pos += 2;
                has_expr = true;
                break;
            }
            self.advance();
            if (c == '`') break;
        }
        const kind: TokenKind = if (has_expr) .template_middle else .template_tail;
        if (kind == .template_middle) {
            if (self.template_depth < 16) {
                self.template_stack[self.template_depth] = self.brace_depth;
                self.template_depth += 1;
            }
        }
        return .{
            .kind = kind,
            .span = self.spanFrom(start, sl, sc),
            .raw = self.src[start..self.pos],
        };
    }

    fn readNumber(self: *Lexer) Token {
        const start = self.pos;
        const sl = self.line;
        const sc = self.col();
        if (self.cur() == '0' and (self.peek1() == 'x' or self.peek1() == 'X')) {
            self.pos += 2;
            while (self.pos < self.src.len and std.ascii.isHex(self.src[self.pos])) self.pos += 1;
        } else if (self.cur() == '0' and (self.peek1() == 'b' or self.peek1() == 'B')) {
            self.pos += 2;
            while (self.pos < self.src.len and (self.src[self.pos] == '0' or self.src[self.pos] == '1')) self.pos += 1;
        } else if (self.cur() == '0' and (self.peek1() == 'o' or self.peek1() == 'O')) {
            self.pos += 2;
            while (self.pos < self.src.len and self.src[self.pos] >= '0' and self.src[self.pos] <= '7') self.pos += 1;
        } else {
            while (self.pos < self.src.len and (std.ascii.isDigit(self.src[self.pos]) or self.src[self.pos] == '_')) self.pos += 1;
            if (self.pos < self.src.len and self.src[self.pos] == '.') {
                self.pos += 1;
                while (self.pos < self.src.len and std.ascii.isDigit(self.src[self.pos])) self.pos += 1;
            }
            if (self.pos < self.src.len and (self.src[self.pos] == 'e' or self.src[self.pos] == 'E')) {
                self.pos += 1;
                if (self.pos < self.src.len and (self.src[self.pos] == '+' or self.src[self.pos] == '-')) self.pos += 1;
                while (self.pos < self.src.len and std.ascii.isDigit(self.src[self.pos])) self.pos += 1;
            }
        }
        if (self.pos < self.src.len and self.src[self.pos] == 'n') self.pos += 1;
        return .{
            .kind = .number,
            .span = self.spanFrom(start, sl, sc),
            .raw = self.src[start..self.pos],
        };
    }

    fn readPrivateName(self: *Lexer) Token {
        const start = self.pos;
        const sl = self.line;
        const sc = self.col();
        self.advance(); // eat '#'
        while (self.pos < self.src.len) {
            const ch = self.src[self.pos];
            if (std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '$') {
                self.pos += 1;
            } else break;
        }
        return .{ .kind = .private_name, .span = self.spanFrom(start, sl, sc), .raw = self.src[start..self.pos] };
    }

    fn readIdent(self: *Lexer) Token {
        const start = self.pos;
        const sl = self.line;
        const sc = self.col();
        while (self.pos < self.src.len) {
            const c = self.src[self.pos];
            if (std.ascii.isAlphanumeric(c) or c == '_' or c == '$' or c > 127) {
                self.pos += 1;
            } else break;
        }
        const raw = self.src[start..self.pos];
        const kind = tok.lookupKeyword(raw) orelse .ident;
        return .{
            .kind = kind,
            .span = self.spanFrom(start, sl, sc),
            .raw = raw,
        };
    }

    fn canStartRegex(self: *const Lexer) bool {
        const kind = self.last_kind orelse return true;
        return switch (kind) {
            .ident,
            .private_name,
            .number,
            .string,
            .regex,
            .kw_true,
            .kw_false,
            .kw_null,
            .kw_this,
            .kw_super,
            .kw_import,
            .template_tail,
            .template_no_sub,
            .rparen,
            .rbracket,
            .rbrace,
            .plus2,
            .minus2,
            => false,
            else => true,
        };
    }

    fn readRegex(self: *Lexer) Token {
        const start = self.pos;
        const sl = self.line;
        const sc = self.col();
        self.advance();

        var in_class = false;
        var closed = false;
        while (self.pos < self.src.len) {
            const c = self.src[self.pos];
            if (c == '\\') {
                if (self.pos + 1 < self.src.len) {
                    self.pos += 2;
                } else {
                    self.pos += 1;
                }
                continue;
            }
            if (c == '\n' or c == '\r') break;
            if (c == '[') {
                in_class = true;
                self.pos += 1;
                continue;
            }
            if (c == ']' and in_class) {
                in_class = false;
                self.pos += 1;
                continue;
            }
            if (c == '/' and !in_class) {
                self.pos += 1;
                closed = true;
                while (self.pos < self.src.len and std.ascii.isAlphabetic(self.src[self.pos])) {
                    self.pos += 1;
                }
                break;
            }
            self.pos += 1;
        }

        if (!closed) {
            self.pos = start + 1;
            return .{
                .kind = .invalid,
                .span = self.spanFrom(start, sl, sc),
                .raw = self.src[start..self.pos],
            };
        }

        return .{
            .kind = .regex,
            .span = self.spanFrom(start, sl, sc),
            .raw = self.src[start..self.pos],
        };
    }

    fn nextInner(self: *Lexer) Token {
        self.skipWhitespace();

        if (self.pos >= self.src.len) {
            return .{
                .kind = .eof,
                .span = .{ .start = self.pos, .end = self.pos, .line = self.line, .col = self.col() },
                .raw = "",
            };
        }

        if (self.cur() == '/' and self.peek1() == '/') {
            const start = self.pos;
            const sl = self.line;
            const sc = self.col();
            self.skipLineComment();
            self.pushPendingComment(start, sl, sc);
            return self.nextInner();
        }
        if (self.cur() == '/' and self.peek1() == '*') {
            const start = self.pos;
            const sl = self.line;
            const sc = self.col();
            const closed = self.skipBlockComment();
            if (!closed) {
                self.pos = start + 2;
                return .{ .kind = .invalid, .span = self.spanFrom(start, sl, sc), .raw = self.src[start..self.pos] };
            }
            self.pushPendingComment(start, sl, sc);
            return self.nextInner();
        }

        const start = self.pos;
        const sl = self.line;
        const sc = self.col();
        const c = self.src[self.pos];

        if (self.mode == .jsx and c == '/') {
            self.advance();
            return .{ .kind = .slash, .span = self.spanFrom(start, sl, sc), .raw = self.src[start..self.pos] };
        }

        if (c == '"' or c == '\'') return self.readString(c);
        if (c == '`') return self.readTemplate();
        if (c == '/' and self.canStartRegex()) return self.readRegex();

        if (std.ascii.isDigit(c) or (c == '.' and self.pos + 1 < self.src.len and std.ascii.isDigit(self.src[self.pos + 1]))) {
            return self.readNumber();
        }

        if (std.ascii.isAlphabetic(c) or c == '_' or c == '$' or c > 127) {
            return self.readIdent();
        }

        if (c == '#' and self.pos + 1 < self.src.len and (std.ascii.isAlphabetic(self.src[self.pos + 1]) or self.src[self.pos + 1] == '_')) {
            return self.readPrivateName();
        }

        // Handle } before generic advance: may need to continue a template literal
        if (c == '}' and self.template_depth > 0 and self.brace_depth == self.template_stack[self.template_depth - 1]) {
            self.template_depth -= 1;
            // do NOT advance; readTemplateMiddleOrTail starts from } and includes it in raw
            return self.readTemplateMiddleOrTail();
        }

        self.advance();
        const sp = self.spanFrom(start, sl, sc);

        const kind: TokenKind = switch (c) {
            '(' => .lparen,
            ')' => .rparen,
            '{' => blk: {
                self.brace_depth +|= 1;
                break :blk .lbrace;
            },
            '}' => blk: {
                if (self.brace_depth > 0) self.brace_depth -= 1;
                break :blk .rbrace;
            },
            '[' => .lbracket,
            ']' => .rbracket,
            ';' => .semicolon,
            ':' => .colon,
            ',' => .comma,
            '~' => .tilde,
            '@' => .at,
            '.' => blk: {
                if (self.cur() == '.' and self.peek1() == '.') {
                    self.pos += 2;
                    break :blk .dotdotdot;
                }
                break :blk .dot;
            },
            '?' => blk: {
                if (self.cur() == '.') {
                    self.advance();
                    break :blk .question_dot;
                }
                if (self.cur() == '?') {
                    self.advance();
                    if (self.cur() == '=') {
                        self.advance();
                        break :blk .question2_eq;
                    }
                    break :blk .question2;
                }
                break :blk .question;
            },
            '=' => blk: {
                if (self.cur() == '>') {
                    self.advance();
                    break :blk .arrow;
                }
                if (self.cur() == '=') {
                    self.advance();
                    if (self.cur() == '=') {
                        self.advance();
                        break :blk .eq3;
                    }
                    break :blk .eq2;
                }
                break :blk .eq;
            },
            '!' => blk: {
                if (self.cur() == '=') {
                    self.advance();
                    if (self.cur() == '=') {
                        self.advance();
                        break :blk .bang_eq2;
                    }
                    break :blk .bang_eq;
                }
                break :blk .bang;
            },
            '+' => blk: {
                if (self.cur() == '+') {
                    self.advance();
                    break :blk .plus2;
                }
                if (self.cur() == '=') {
                    self.advance();
                    break :blk .plus_eq;
                }
                break :blk .plus;
            },
            '-' => blk: {
                if (self.cur() == '-') {
                    self.advance();
                    break :blk .minus2;
                }
                if (self.cur() == '=') {
                    self.advance();
                    break :blk .minus_eq;
                }
                break :blk .minus;
            },
            '*' => blk: {
                if (self.cur() == '*') {
                    self.advance();
                    if (self.cur() == '=') {
                        self.advance();
                        break :blk .star2_eq;
                    }
                    break :blk .star2;
                }
                if (self.cur() == '=') {
                    self.advance();
                    break :blk .star_eq;
                }
                break :blk .star;
            },
            '/' => blk: {
                if (self.cur() == '=') {
                    self.advance();
                    break :blk .slash_eq;
                }
                break :blk .slash;
            },
            '%' => blk: {
                if (self.cur() == '=') {
                    self.advance();
                    break :blk .percent_eq;
                }
                break :blk .percent;
            },
            '<' => blk: {
                if (self.cur() == '<') {
                    self.advance();
                    if (self.cur() == '=') {
                        self.advance();
                        break :blk .lt2_eq;
                    }
                    break :blk .lt2;
                }
                if (self.cur() == '=') {
                    self.advance();
                    break :blk .lt_eq;
                }
                break :blk .lt;
            },
            '>' => blk: {
                if (self.cur() == '>') {
                    self.advance();
                    if (self.cur() == '>') {
                        self.advance();
                        if (self.cur() == '=') {
                            self.advance();
                            break :blk .gt3_eq;
                        }
                        break :blk .gt3;
                    }
                    if (self.cur() == '=') {
                        self.advance();
                        break :blk .gt2_eq;
                    }
                    break :blk .gt2;
                }
                if (self.cur() == '=') {
                    self.advance();
                    break :blk .gt_eq;
                }
                break :blk .gt;
            },
            '&' => blk: {
                if (self.cur() == '&') {
                    self.advance();
                    if (self.cur() == '=') {
                        self.advance();
                        break :blk .amp2_eq;
                    }
                    break :blk .amp2;
                }
                if (self.cur() == '=') {
                    self.advance();
                    break :blk .amp_eq;
                }
                break :blk .amp;
            },
            '|' => blk: {
                if (self.cur() == '|') {
                    self.advance();
                    if (self.cur() == '=') {
                        self.advance();
                        break :blk .pipe2_eq;
                    }
                    break :blk .pipe2;
                }
                if (self.cur() == '=') {
                    self.advance();
                    break :blk .pipe_eq;
                }
                break :blk .pipe;
            },
            '^' => blk: {
                if (self.cur() == '=') {
                    self.advance();
                    break :blk .caret_eq;
                }
                break :blk .caret;
            },
            else => .invalid,
        };

        return .{ .kind = kind, .span = sp, .raw = self.src[start..self.pos] };
    }
};
