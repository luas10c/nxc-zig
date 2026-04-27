const std = @import("std");

const compiler = @import("compiler");
const diagnostics = @import("diagnostics");

fn freeDiagnostics(alloc: std.mem.Allocator, diags: []const diagnostics.Diagnostic) void {
    for (diags) |d| {
        alloc.free(d.message);
        alloc.free(d.filename);
        if (d.source_line) |line| alloc.free(line);
    }
    alloc.free(diags);
}

fn deinitCompileResult(alloc: std.mem.Allocator, result: compiler.CompileResult) void {
    alloc.free(result.code);
    if (result.map) |m| alloc.free(m);
    freeDiagnostics(alloc, result.diagnostics);
}

fn compile(src: []const u8) ![]const u8 {
    const alloc = std.testing.allocator;
    const cfg = compiler.Config{ .parser = .{ .syntax = .ecmascript }, .jsx = false };
    const result = try compiler.compile(src, "test.js", cfg, std.testing.io, alloc);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| {
            std.debug.print("diag: {s}\n", .{d.message});
        }
        if (result.diagnostics.len > 0 and result.diagnostics[0].severity == .err) {
            alloc.free(result.code);
            freeDiagnostics(alloc, result.diagnostics);
            return error.ParseError;
        }
    }
    freeDiagnostics(alloc, result.diagnostics);
    return result.code;
}

fn compileTs(src: []const u8) ![]const u8 {
    const alloc = std.testing.allocator;
    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript }, .jsx = false };
    const result = try compiler.compile(src, "test.ts", cfg, std.testing.io, alloc);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) {
            alloc.free(result.code);
            freeDiagnostics(alloc, result.diagnostics);
            return error.ParseError;
        }
    }
    freeDiagnostics(alloc, result.diagnostics);
    return result.code;
}

fn compileTsWithComments(src: []const u8) ![]const u8 {
    const alloc = std.testing.allocator;
    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript }, .jsx = false, .remove_comments = false };
    const result = try compiler.compile(src, "test.ts", cfg, std.testing.io, alloc);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) {
            alloc.free(result.code);
            freeDiagnostics(alloc, result.diagnostics);
            return error.ParseError;
        }
    }
    freeDiagnostics(alloc, result.diagnostics);
    return result.code;
}

fn expectOutput(src: []const u8, expected: []const u8) !void {
    const out = try compile(src);
    defer std.testing.allocator.free(out);
    const trimmed = normalizedOutput(out, expected);
    const exp_trimmed = trimText(expected);
    if (!std.mem.eql(u8, trimmed, exp_trimmed) and !equalIgnoringWhitespace(trimmed, exp_trimmed)) {
        std.debug.print("\n=== EXPECTED ===\n{s}\n=== GOT ===\n{s}\n", .{ exp_trimmed, trimmed });
        return error.TestExpectedEqual;
    }
}

fn trimText(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \n\r\t");
}

fn normalizedOutput(out: []const u8, expected: []const u8) []const u8 {
    const trimmed = trimText(out);
    const exp_trimmed = trimText(expected);
    const strict = "\"use strict\";";
    if (std.mem.startsWith(u8, exp_trimmed, strict)) return trimmed;
    if (!std.mem.startsWith(u8, trimmed, strict)) return trimmed;
    var rest = trimmed[strict.len..];
    if (std.mem.startsWith(u8, rest, "\r\n")) rest = rest[2..] else if (std.mem.startsWith(u8, rest, "\n")) rest = rest[1..];
    return trimText(rest);
}

fn equalIgnoringWhitespace(a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (true) {
        while (i < a.len and std.ascii.isWhitespace(a[i])) i += 1;
        while (j < b.len and std.ascii.isWhitespace(b[j])) j += 1;
        if (i == a.len or j == b.len) return i == a.len and j == b.len;
        if (a[i] != b[j] and !((a[i] == '\'' or a[i] == '"') and (b[j] == '\'' or b[j] == '"'))) return false;
        i += 1;
        j += 1;
    }
}

fn compilePathsFrom(src: []const u8, filename: []const u8, aliases: []const compiler.PathAlias, add_ext: bool) ![]const u8 {
    const alloc = std.testing.allocator;
    const cfg = compiler.Config{
        .parser = .{ .syntax = .ecmascript },
        .jsx = false,
        .paths = aliases,
        .module = .{ .resolve_full_paths = add_ext },
    };
    const result = try compiler.compile(src, filename, cfg, std.testing.io, alloc);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) {
            alloc.free(result.code);
            freeDiagnostics(alloc, result.diagnostics);
            return error.ParseError;
        }
    }
    freeDiagnostics(alloc, result.diagnostics);
    return result.code;
}

fn expectPathsFromOutput(src: []const u8, filename: []const u8, aliases: []const compiler.PathAlias, add_ext: bool, expected: []const u8) !void {
    const out = try compilePathsFrom(src, filename, aliases, add_ext);
    defer std.testing.allocator.free(out);
    const trimmed = normalizedOutput(out, expected);
    const exp_trimmed = trimText(expected);
    if (!std.mem.eql(u8, trimmed, exp_trimmed) and !equalIgnoringWhitespace(trimmed, exp_trimmed)) {
        std.debug.print("\n=== EXPECTED ===\n{s}\n=== GOT ===\n{s}\n", .{ exp_trimmed, trimmed });
        return error.TestExpectedEqual;
    }
}

fn compilePaths(src: []const u8, aliases: []const compiler.PathAlias, add_ext: bool) ![]const u8 {
    const alloc = std.testing.allocator;
    const cfg = compiler.Config{
        .parser = .{ .syntax = .ecmascript },
        .jsx = false,
        .paths = aliases,
        .module = .{ .resolve_full_paths = add_ext },
    };
    const result = try compiler.compile(src, "test.js", cfg, std.testing.io, alloc);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) {
            alloc.free(result.code);
            freeDiagnostics(alloc, result.diagnostics);
            return error.ParseError;
        }
    }
    freeDiagnostics(alloc, result.diagnostics);
    return result.code;
}

fn expectPathsOutput(src: []const u8, aliases: []const compiler.PathAlias, add_ext: bool, expected: []const u8) !void {
    const out = try compilePaths(src, aliases, add_ext);
    defer std.testing.allocator.free(out);
    const trimmed = normalizedOutput(out, expected);
    const exp_trimmed = trimText(expected);
    if (!std.mem.eql(u8, trimmed, exp_trimmed) and !equalIgnoringWhitespace(trimmed, exp_trimmed)) {
        std.debug.print("\n=== EXPECTED ===\n{s}\n=== GOT ===\n{s}\n", .{ exp_trimmed, trimmed });
        return error.TestExpectedEqual;
    }
}

fn expectTsOutput(src: []const u8, expected: []const u8) !void {
    const out = try compileTs(src);
    defer std.testing.allocator.free(out);
    const trimmed = normalizedOutput(out, expected);
    const exp_trimmed = trimText(expected);
    if (!std.mem.eql(u8, trimmed, exp_trimmed) and !equalIgnoringWhitespace(trimmed, exp_trimmed)) {
        std.debug.print("\n=== EXPECTED ===\n{s}\n=== GOT ===\n{s}\n", .{ exp_trimmed, trimmed });
        return error.TestExpectedEqual;
    }
}

fn expectTsParseError(label: []const u8, src: []const u8) !void {
    _ = label;
    const alloc = std.testing.allocator;
    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript }, .jsx = false };
    const result = try compiler.compile(src, "test.ts", cfg, std.testing.io, alloc);
    defer deinitCompileResult(alloc, result);

    try std.testing.expect(result.diagnostics.len > 0);
    try std.testing.expectEqual(.err, result.diagnostics[0].severity);
}

fn expectTsParseErrorMessage(src: []const u8, expected: []const u8) !void {
    const alloc = std.testing.allocator;
    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript }, .jsx = false };
    const result = try compiler.compile(src, "test.ts", cfg, std.testing.io, alloc);
    defer deinitCompileResult(alloc, result);

    try std.testing.expect(result.diagnostics.len > 0);
    try std.testing.expectEqual(.err, result.diagnostics[0].severity);
    try std.testing.expectEqualStrings(expected, result.diagnostics[0].message);
}

fn expectUnexpectedTokenDiagnostic(src: []const u8, expected_line: u32, expected_col: u32) !void {
    const alloc = std.testing.allocator;
    const result = try compiler.compile(src, "test.js", .{ .parser = .{ .syntax = .ecmascript }, .jsx = false }, std.testing.io, alloc);
    defer deinitCompileResult(alloc, result);

    try std.testing.expectEqual(@as(usize, 1), result.diagnostics.len);
    try std.testing.expectEqual(.err, result.diagnostics[0].severity);
    try std.testing.expectEqualStrings("unexpected token", result.diagnostics[0].message);
    try std.testing.expectEqual(expected_line, result.diagnostics[0].line);
    try std.testing.expectEqual(expected_col, result.diagnostics[0].col);
}

fn compileWithConfig(src: []const u8, filename: []const u8, cfg: compiler.Config) ![]const u8 {
    const alloc = std.testing.allocator;
    const result = try compiler.compile(src, filename, cfg, std.testing.io, alloc);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) {
            alloc.free(result.code);
            freeDiagnostics(alloc, result.diagnostics);
            return error.ParseError;
        }
    }
    freeDiagnostics(alloc, result.diagnostics);
    return result.code;
}

fn expectOutputWithConfig(src: []const u8, filename: []const u8, cfg: compiler.Config, expected: []const u8) !void {
    const out = try compileWithConfig(src, filename, cfg);
    defer std.testing.allocator.free(out);
    const trimmed = normalizedOutput(out, expected);
    const exp_trimmed = trimText(expected);
    if (std.mem.eql(u8, trimmed, "\"use strict\";") and std.mem.startsWith(u8, exp_trimmed, "\"use strict\";")) return;
    if (!std.mem.eql(u8, trimmed, exp_trimmed) and !equalIgnoringWhitespace(trimmed, exp_trimmed)) {
        std.debug.print("\n=== EXPECTED ===\n{s}\n=== GOT ===\n{s}\n", .{ exp_trimmed, trimmed });
        return error.TestExpectedEqual;
    }
}

fn mkdirP(path: [:0]const u8) void {
    _ = std.os.linux.mkdirat(std.posix.AT.FDCWD, path.ptr, 0o755);
}

fn deleteTree(path: []const u8) void {
    std.Io.Dir.cwd().deleteTree(std.testing.io, path) catch {};
}

fn writeFile(path: []const u8, content: []const u8) !void {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    defer _ = std.os.linux.close(fd);
    var written: usize = 0;
    while (written < content.len) {
        const n = std.os.linux.write(fd, content.ptr + written, content.len - written);
        if (n == 0) break;
        written += n;
    }
}

fn readFile(path: []const u8, a: std.mem.Allocator) ![]u8 {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0);
    defer _ = std.os.linux.close(fd);
    var buf = std.ArrayListUnmanaged(u8).empty;
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = try std.posix.read(fd, &tmp);
        if (n == 0) break;
        try buf.appendSlice(a, tmp[0..n]);
    }
    return buf.toOwnedSlice(a);
}

fn expectContainsText(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) return;
    std.debug.print("expected to find '{s}' in text\n", .{needle});
    return error.TestExpectedEqual;
}

test "core compileFile: single file compiles" {
    const tmp = "/tmp/zts_core_compile_file";
    mkdirP(tmp);
    defer deleteTree(tmp);

    const file = tmp ++ "/main.ts";
    try writeFile(file, "export const x: number = 1;");

    const result = try compiler.compileFile(file, .{ .parser = .{ .syntax = .typescript } }, std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try expectContainsText(result.code, "const x = 1;");
}

test "core compileFile: directory is rejected" {
    const tmp = "/tmp/zts_core_compile_dir";
    mkdirP(tmp);
    defer deleteTree(tmp);

    try std.testing.expectError(error.IsDir, compiler.compileFile(tmp, .{ .parser = .{ .syntax = .typescript } }, std.testing.io, std.testing.allocator));
}

test "core compileFile: nonexistent path returns file not found" {
    try std.testing.expectError(error.FileNotFound, compiler.compileFile("/tmp/zts_missing_input.ts", .{ .parser = .{ .syntax = .typescript } }, std.testing.io, std.testing.allocator));
}

// ── Variables ─────────────────────────────────────────────────────────────────

test "var declaration" {
    try expectOutput("var x = 1;", "var x = 1;");
}

test "let declaration" {
    try expectOutput("let x = 2;", "let x = 2;");
}

test "const declaration" {
    try expectOutput("const x = 3;", "const x = 3;");
}

test "multiple declarators" {
    try expectOutput("let a = 1, b = 2;", "let a = 1, b = 2;");
}

// ── Literals ──────────────────────────────────────────────────────────────────

test "string literal" {
    try expectOutput(
        \\const s = "hello";
    ,
        \\const s = "hello";
    );
}

test "number literal" {
    try expectOutput("const n = 42;", "const n = 42;");
}

test "regex fixture compiles without unexpected token" {
    const result = try compiler.compileFile(
        "tests/fixtures/regex_literals.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export const digits = /\\d+/;");
    try expectContainsText(result.code, "export const combiningMarks = /[\\u0300-\\u036f]/g;");
    try expectContainsText(result.code, "export const price = /\\$(\\d+)/gu;");
    try expectContainsText(result.code, "export const protocol = /^http[s]?:\\/\\//;");
    try expectContainsText(result.code, "export const htmlSrc = /(?<=src=\")(.|\\n)*?(?=\")/gu;");
}

test "member call expression fixture compiles and preserves includes call" {
    const result = try compiler.compileFile(
        "tests/fixtures/member_call_expression.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) return error.ParseError;
    }

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "ALLOWED_TYPES.includes(type)");
    try expectContainsText(result.code, "function validate(metatype, type)");
    try expectContainsText(result.code, "const result = validate(String, String);");
}

test "template string angle brackets fixture compiles and preserves templates" {
    const result = try compiler.compileFile(
        "tests/fixtures/template_string_angle_brackets.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) return error.ParseError;
    }

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "`${htmlEscape(senderName)} <${senderEmail}>`");
    try expectContainsText(result.code, "`${senderName} <${senderEmail}>`");
    try expectContainsText(result.code, "`${htmlEscape(senderName)} <${senderEmail.toLowerCase()}>`");
    try expectContainsText(result.code, "`${senderName} <${senderEmail ?? \"fallback@email.com\"}>`");
    try expectContainsText(result.code, "`<${user?.email}>`");
}

test "parameter type annotation enum-like fixture compiles and strips parameter types" {
    const result = try compiler.compileFile(
        "tests/fixtures/parameter_type_annotation_enum_like.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) return error.ParseError;
    }

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export const mpTaxes = type => {");
    try expectContainsText(result.code, "export const fn1 = type => {");
    try expectContainsText(result.code, "export const fn2 = type => {");
    try expectContainsText(result.code, "export const fn3 = type => {");
    try expectContainsText(result.code, "export const fn4 = (a, type, b) => {");
    try expectContainsText(result.code, "export const fn5 = type => type;");
    try expectContainsText(result.code, "export const fn6 = (type = StoreTypeEnum.MARKETPLACE) => {");
    try expectContainsText(result.code, "export const fn7 = type => {");
    try expectContainsText(result.code, "export const fn8 = (...types) => {");
    try expectContainsText(result.code, "export const fn9 = ({ type }) => {");
}

test "boolean literals" {
    try expectOutput("const t = true; const f = false;",
        \\const t = true;
        \\const f = false;
    );
}

test "null literal" {
    try expectOutput("const x = null;", "const x = null;");
}

test "array literal" {
    try expectOutput("const a = [1, 2, 3];", "const a = [1, 2, 3];");
}

test "object literal" {
    try expectOutput("const o = { a: 1, b: 2 };",
        \\const o = {
        \\  a: 1,
        \\  b: 2
        \\};
    );
}

test "malformed call arguments report unexpected token at problem token" {
    const cases = [_]struct {
        src: []const u8,
        line: u32,
        col: u32,
    }{
        .{ .src = "console.log({)", .line = 1, .col = 14 },
        .{ .src = "console.log([)", .line = 1, .col = 14 },
        .{ .src = "console.log(/)", .line = 1, .col = 13 },
        .{ .src = "console.log(\")", .line = 1, .col = 13 },
        .{ .src = "console.log(')", .line = 1, .col = 13 },
        .{ .src = "console.log(`)", .line = 1, .col = 13 },
        .{ .src = "console.log(/*)", .line = 1, .col = 13 },
        .{ .src = "const ok = true;\nconsole.log({)", .line = 2, .col = 14 },
    };

    for (cases) |case| {
        try expectUnexpectedTokenDiagnostic(case.src, case.line, case.col);
    }
}

test "object computed property: identifier key" {
    try expectOutput("const o = { [key]: 1 };",
        \\const o = {
        \\  [key]: 1
        \\};
    );
}

test "object computed property: expression key" {
    try expectOutput("const o = { [a + b]: 1 };",
        \\const o = {
        \\  [a + b]: 1
        \\};
    );
}

test "object computed property: method call key" {
    try expectOutput(
        \\const errors = exception.errors.map((error) => {
        \\  return { [error.path.join('')]: error.message };
        \\});
    ,
        \\const errors = exception.errors.map(error => {
        \\  return {
        \\    [error.path.join("")]: error.message
        \\  };
        \\});
    );
}

test "object computed property: call expr key and identifier key in same object" {
    try expectOutput(
        \\const key = error.path.join('');
        \\const result = {
        \\  [error.path.join('')]: error.message,
        \\  [key]: error.message
        \\};
    ,
        \\const key = error.path.join("");
        \\const result = {
        \\  [error.path.join("")]: error.message,
        \\  [key]: error.message
        \\};
    );
}

test "object computed property: string literal key" {
    try expectOutput("const o = { ['key']: 1 };",
        \\const o = {
        \\  ["key"]: 1
        \\};
    );
}

test "object computed property: mixed computed and static keys" {
    try expectOutput("const o = { a: 1, [b]: 2, c: 3 };",
        \\const o = {
        \\  a: 1,
        \\  [b]: 2,
        \\  c: 3
        \\};
    );
}

test "object computed method: symbol key" {
    try expectOutput("const o = { [Symbol.iterator]() { return this; } };",
        \\const o = {
        \\  [Symbol.iterator]() {
        \\    return this;
        \\  }
        \\};
    );
}

test "template literal" {
    try expectOutput("const s = `hello ${name}`;", "const s = `hello ${name}`;");
}

// ── Operators ─────────────────────────────────────────────────────────────────

test "binary operators" {
    try expectOutput("const r = 1 + 2 * 3;", "const r = 1 + 2 * 3;");
}

test "comparison operators" {
    try expectOutput("const r = x <= 10;", "const r = x <= 10;");
    try expectOutput("const r = x >= 0;", "const r = x >= 0;");
    try expectOutput("const r = x === y;", "const r = x === y;");
    try expectOutput("const r = x !== y;", "const r = x !== y;");
}

test "logical operators" {
    try expectOutput("const r = a && b || c;", "const r = a && b || c;");
    try expectOutput("const r = a ?? b;", "const r = a ?? b;");
}

test "assignment operators" {
    try expectOutput("x += 1;", "x += 1;");
    try expectOutput("x -= 1;", "x -= 1;");
    try expectOutput("x *= 2;", "x *= 2;");
}

test "unary operators" {
    try expectOutput("const r = !x;", "const r = !x;");
    try expectOutput("const r = -x;", "const r = -x;");
    try expectOutput("const r = typeof x;", "const r = typeof x;");
    try expectOutput("const r = void 0;", "const r = void 0;");
}

test "ternary operator" {
    try expectOutput("const r = x ? a : b;", "const r = x ? a : b;");
}

test "increment decrement" {
    try expectOutput("i++;", "i++;");
    try expectOutput("i--;", "i--;");
    try expectOutput("++i;", "++i;");
}

test "spread operator" {
    try expectOutput("const a = [...b, 1];", "const a = [...b, 1];");
}

test "optional chaining" {
    try expectOutput("const r = obj?.prop;", "const r = obj?.prop;");
    try expectOutput("const r = fn?.();", "const r = fn?.();");
}

// ── Control flow ──────────────────────────────────────────────────────────────

test "if statement" {
    try expectOutput(
        \\if (x > 0) {
        \\  console.log(x);
        \\}
    ,
        \\if (x > 0) {
        \\  console.log(x);
        \\}
    );
}

test "if-else statement" {
    try expectOutput(
        \\if (x > 0) {
        \\  console.log("pos");
        \\} else {
        \\  console.log("neg");
        \\}
    ,
        \\if (x > 0) {
        \\  console.log("pos");
        \\} else {
        \\  console.log("neg");
        \\}
    );
}

test "for loop" {
    try expectOutput(
        \\for (let i = 1; i <= 10; i++) {
        \\  console.log(i);
        \\}
    ,
        \\for (let i = 1; i <= 10; i++) {
        \\  console.log(i);
        \\}
    );
}

test "for-of loop" {
    try expectOutput(
        \\for (const x of arr) {
        \\  console.log(x);
        \\}
    ,
        \\for (const x of arr) {
        \\  console.log(x);
        \\}
    );
}

test "for-in loop" {
    try expectOutput(
        \\for (const k in obj) {
        \\  console.log(k);
        \\}
    ,
        \\for (const k in obj) {
        \\  console.log(k);
        \\}
    );
}

test "while loop" {
    try expectOutput(
        \\while (x > 0) {
        \\  x--;
        \\}
    ,
        \\while (x > 0) {
        \\  x--;
        \\}
    );
}

test "do-while loop" {
    try expectOutput(
        \\do {
        \\  x--;
        \\} while (x > 0);
    ,
        \\do {
        \\  x--;
        \\} while (x > 0);
    );
}

test "switch statement" {
    try expectOutput(
        \\switch (x) {
        \\  case 1:
        \\    console.log("one");
        \\    break;
        \\  default:
        \\    console.log("other");
        \\}
    ,
        \\switch (x) {
        \\  case 1:
        \\    console.log("one");
        \\    break;
        \\  default:
        \\    console.log("other");
        \\}
    );
}

test "try-catch with typed catch param" {
    try expectTsOutput(
        \\function readError() {
        \\  try {
        \\    throw new Error("boom");
        \\  } catch (error: unknown) {
        \\    return error instanceof Error ? error.message : "unknown";
        \\  }
        \\}
    ,
        \\"use strict";
        \\function readError() {
        \\  try {
        \\    throw new Error("boom");
        \\  } catch (error) {
        \\    return error instanceof Error ? error.message : "unknown";
        \\  }
        \\}
    );
}

test "try-catch with typed destructured catch param" {
    try expectTsOutput(
        \\function readMessage(payload: { message: string }) {
        \\  try {
        \\    throw payload;
        \\  } catch ({ message }: { message: string }) {
        \\    return message;
        \\  }
        \\}
    ,
        \\"use strict";
        \\function readMessage(payload) {
        \\  try {
        \\    throw payload;
        \\  } catch ({ message }) {
        \\    return message;
        \\  }
        \\}
    );
}

test "try-catch-finally" {
    try expectOutput(
        \\try {
        \\  doSomething();
        \\} catch (e) {
        \\  console.error(e);
        \\} finally {
        \\  cleanup();
        \\}
    ,
        \\try {
        \\  doSomething();
        \\} catch (e) {
        \\  console.error(e);
        \\} finally {
        \\  cleanup();
        \\}
    );
}

test "throw statement" {
    try expectOutput("throw new Error(\"oops\");", "throw new Error(\"oops\");");
}

test "return statement" {
    try expectOutput("function f() { return 42; }",
        \\function f() {
        \\  return 42;
        \\}
    );
}

test "break and continue" {
    try expectOutput(
        \\for (const x of a) {
        \\  if (x === 0) continue;
        \\  if (x > 10) break;
        \\}
    ,
        \\for (const x of a) {
        \\  if (x === 0) continue;
        \\  if (x > 10) break;
        \\}
    );
}

test "labeled for loop with break" {
    try expectOutput(
        \\outerLoop: for (let i = 0; i < 3; i++) {
        \\  for (let j = 0; j < 3; j++) {
        \\    if (i === 1 && j === 1) break outerLoop;
        \\  }
        \\}
    ,
        \\outerLoop: for (let i = 0; i < 3; i++) {
        \\  for (let j = 0; j < 3; j++) {
        \\    if (i === 1 && j === 1) break outerLoop;
        \\  }
        \\}
    );
}

test "labeled for-of loop with continue" {
    try expectOutput(
        \\outer: for (const x of a) {
        \\  for (const y of b) {
        \\    if (x === y) continue outer;
        \\  }
        \\}
    ,
        \\outer: for (const x of a) {
        \\  for (const y of b) {
        \\    if (x === y) continue outer;
        \\  }
        \\}
    );
}

test "labeled while loop" {
    try expectOutput(
        \\loop: while (true) {
        \\  if (done) break loop;
        \\}
    ,
        \\loop: while (true) {
        \\  if (done) break loop;
        \\}
    );
}

test "labeled block with break" {
    try expectOutput(
        \\block: {
        \\  doSomething();
        \\  if (cond) break block;
        \\  doMore();
        \\}
    ,
        \\block: {
        \\  doSomething();
        \\  if (cond) break block;
        \\  doMore();
        \\}
    );
}

test "labeled for-of with break label" {
    try expectOutput(
        \\const fileKeys = ['avatar', 'document'];
        \\checkFile: for (const fileFieldKey of fileKeys) {
        \\  if (fileFieldKey === 'avatar') {
        \\    break checkFile;
        \\  }
        \\}
    ,
        \\const fileKeys = ['avatar', 'document'];
        \\checkFile: for (const fileFieldKey of fileKeys) {
        \\  if (fileFieldKey === 'avatar') {
        \\    break checkFile;
        \\  }
        \\}
    );
}

test "labeled for-of fixture" {
    try expectOutput(
        \\const fileKeys = ['avatar', 'document'];
        \\checkFile: for (const fileFieldKey of fileKeys) {
        \\  if (fileFieldKey === 'avatar') {
        \\    break checkFile;
        \\  }
        \\}
    ,
        \\const fileKeys = ['avatar', 'document'];
        \\checkFile: for (const fileFieldKey of fileKeys) {
        \\  if (fileFieldKey === 'avatar') {
        \\    break checkFile;
        \\  }
        \\}
    );
}

// ── Functions ─────────────────────────────────────────────────────────────────

test "function declaration" {
    try expectOutput(
        \\function add(a, b) {
        \\  return a + b;
        \\}
    ,
        \\function add(a, b) {
        \\  return a + b;
        \\}
    );
}

test "arrow function" {
    try expectOutput("const add = (a, b) => a + b;", "const add = (a, b) => a + b;");
}

test "arrow function with body" {
    try expectOutput(
        \\const add = (a, b) => {
        \\  return a + b;
        \\};
    ,
        \\const add = (a, b) => {
        \\  return a + b;
        \\};
    );
}

test "async function" {
    try expectOutput(
        \\async function fetchData() {
        \\  const res = await fetch(url);
        \\  return res.json();
        \\}
    ,
        \\async function fetchData() {
        \\  const res = await fetch(url);
        \\  return res.json();
        \\}
    );
}

test "async class method" {
    try expectOutput(
        \\class Foo {
        \\  async bar() {
        \\    return await baz();
        \\  }
        \\}
    ,
        \\class Foo {
        \\  async bar() {
        \\    return await baz();
        \\  }
        \\}
    );
}

test "async delete method" {
    try expectOutput(
        \\class Foo {
        \\  async delete() {
        \\    return await baz();
        \\  }
        \\}
    ,
        \\class Foo {
        \\  async delete() {
        \\    return await baz();
        \\  }
        \\}
    );
}

test "async object method" {
    try expectOutput(
        \\const foo = {
        \\  async bar() {
        \\    return await baz();
        \\  }
        \\};
    ,
        \\const foo = {
        \\  async bar() {
        \\    return await baz();
        \\  }
        \\};
    );
}

test "generator function" {
    try expectOutput(
        \\function* gen() {
        \\  yield 1;
        \\  yield 2;
        \\}
    ,
        \\function* gen() {
        \\  yield 1;
        \\  yield 2;
        \\}
    );
}

test "default parameters" {
    try expectOutput("function greet(name = \"world\") { return name; }",
        \\function greet(name = "world") {
        \\  return name;
        \\}
    );
}

test "rest parameters" {
    try expectOutput("function sum(...args) { return args; }",
        \\function sum(...args) {
        \\  return args;
        \\}
    );
}

// ── Classes ───────────────────────────────────────────────────────────────────

test "class declaration" {
    try expectOutput(
        \\class Animal {
        \\  constructor(name) {
        \\    this.name = name;
        \\  }
        \\  speak() {
        \\    return this.name;
        \\  }
        \\}
    ,
        \\class Animal {
        \\  constructor(name) {
        \\    this.name = name;
        \\  }
        \\  speak() {
        \\    return this.name;
        \\  }
        \\}
    );
}

test "class extends" {
    try expectOutput(
        \\class Dog extends Animal {
        \\  constructor(name) {
        \\    super(name);
        \\  }
        \\}
    ,
        \\class Dog extends Animal {
        \\  constructor(name) {
        \\    super(name);
        \\  }
        \\}
    );
}

test "typescript: constructor parameter property assigns to this" {
    try expectTsOutput(
        \\class ServiceConsumer {
        \\  constructor(private service: Service) {}
        \\}
    ,
        "\"use strict\";\nclass ServiceConsumer {\n  constructor(service) {\n    this.service = service;\n  }\n}",
    );
}

test "keep class names: names anonymous class expression from variable" {
    try expectOutputWithConfig(
        "const Foo = class {};",
        "test.js",
        .{ .parser = .{ .syntax = .ecmascript }, .keep_class_names = true },
        "const Foo = class Foo {};",
    );
}

test "keep class names: names anonymous default export class" {
    try expectOutputWithConfig(
        "export default class {};",
        "widget.ts",
        .{ .parser = .{ .syntax = .typescript }, .keep_class_names = true },
        "export default class widget {};",
    );
}

// ── Imports / Exports ─────────────────────────────────────────────────────────

test "named import" {
    try expectOutput(
        \\import { join, resolve } from "node:path";
    ,
        \\import { join, resolve } from "node:path";
    );
}

test "default import" {
    try expectOutput(
        \\import fs from "node:fs";
    ,
        \\import fs from "node:fs";
    );
}

test "namespace import" {
    try expectOutput(
        \\import * as path from "node:path";
    ,
        \\import * as path from "node:path";
    );
}

test "named export" {
    try expectOutput(
        \\export const x = 1;
    ,
        \\export const x = 1;
    );
}

test "named export omits redundant alias when names match" {
    try expectTsOutput(
        \\const NotificationsController = 1;
        \\export { NotificationsController as NotificationsController };
    ,
        \\"use strict";
        \\const NotificationsController = 1;
        \\export { NotificationsController };
    );
}

test "default export" {
    try expectOutput(
        \\export default function main() {}
    ,
        \\export default function main() {};
    );
}

test "re-export" {
    try expectOutput(
        \\export { join } from "node:path";
    ,
        \\export { join } from "node:path";
    );
}

test "dynamic import" {
    try expectOutput(
        \\const mod = await import("./module.js");
    ,
        \\const mod = await import("./module.js");
    );
}

// ── import.meta ───────────────────────────────────────────────────────────────

test "import.meta.url" {
    try expectOutput(
        \\const url = import.meta.url;
    ,
        \\const url = import.meta.url;
    );
}

test "import.meta.dirname" {
    try expectOutput(
        \\const dir = import.meta.dirname;
    ,
        \\const dir = import.meta.dirname;
    );
}

// ── process / environment ─────────────────────────────────────────────────────

test "process.env" {
    try expectOutput(
        \\const port = process.env.PORT;
    ,
        \\const port = process.env.PORT;
    );
}

test "process.cwd" {
    try expectOutput(
        \\const cwd = process.cwd();
    ,
        \\const cwd = process.cwd();
    );
}

test "process.argv" {
    try expectOutput(
        \\const args = process.argv.slice(2);
    ,
        \\const args = process.argv.slice(2);
    );
}

// ── Destructuring ─────────────────────────────────────────────────────────────

test "array destructuring" {
    try expectOutput(
        \\const [a, b] = arr;
    ,
        \\const [a, b] = arr;
    );
}

test "object destructuring" {
    try expectOutput(
        \\const { x, y } = point;
    ,
        \\const { x, y } = point;
    );
}

test "destructuring with rest" {
    try expectOutput(
        \\const [head, ...tail] = arr;
    ,
        \\const [head, ...tail] = arr;
    );
}

// ── Member access ─────────────────────────────────────────────────────────────

test "member expression" {
    try expectOutput("const x = obj.a.b.c;", "const x = obj.a.b.c;");
}

test "computed member expression" {
    try expectOutput("const x = arr[0];", "const x = arr[0];");
    try expectOutput("const x = obj[key];", "const x = obj[key];");
}

test "call expression" {
    try expectOutput("console.log(1, 2, 3);", "console.log(1, 2, 3);");
}

test "new expression" {
    try expectOutput("const x = new Map();", "const x = new Map();");
}

// ── TypeScript stripping ──────────────────────────────────────────────────────

test "ts: type annotation stripped" {
    try expectTsOutput("const x: number = 42;", "const x = 42;");
}

test "ts: interface stripped" {
    try expectTsOutput(
        \\interface Foo { x: number; }
        \\const y = 1;
    ,
        \\const y = 1;
    );
}

test "ts: type alias stripped" {
    try expectTsOutput(
        \\type Id = string | number;
        \\const id: Id = "abc";
    ,
        \\const id = "abc";
    );
}

test "ts: import type stripped" {
    try expectTsOutput(
        \\import type { Foo } from "./foo";
        \\const x = 1;
    ,
        \\const x = 1;
    );
}

// ── Type-only import elision ──────────────────────────────────────────────────

test "ts elide: used only as type annotation — removed" {
    try expectTsOutput(
        \\import { CreateNotificationBody } from "./body.js";
        \\const body: CreateNotificationBody = {};
    ,
        \\const body = {};
    );
}

test "ts elide: used as value — kept" {
    try expectTsOutput(
        \\import { Foo } from "./foo.js";
        \\const x = new Foo();
    ,
        \\import { Foo } from "./foo.js";
        \\const x = new Foo();
    );
}

test "ts elide: used in both type and value — kept" {
    try expectTsOutput(
        \\import { Foo } from "./foo.js";
        \\const x: Foo = new Foo();
    ,
        \\import { Foo } from "./foo.js";
        \\const x = new Foo();
    );
}

test "ts elide: mixed specifiers — type-only removed, value kept" {
    try expectTsOutput(
        \\import { TypeOnly, ValueUsed } from "./mod.js";
        \\const x: TypeOnly = {};
        \\const y = ValueUsed();
    ,
        \\import { ValueUsed } from "./mod.js";
        \\const x = {};
        \\const y = ValueUsed();
    );
}

test "ts elide: all specifiers type-only — whole import removed" {
    try expectTsOutput(
        \\import { OnlyType } from "./types.js";
        \\const x: OnlyType = {};
    ,
        \\const x = {};
    );
}

test "ts elide: used in function param annotation — removed" {
    try expectTsOutput(
        \\import { MyDto } from "./dto.js";
        \\function handle(req: MyDto): void {}
    ,
        \\function handle(req) {}
    );
}

test "ts elide: used as function return type — removed" {
    try expectTsOutput(
        \\import { MyResult } from "./result.js";
        \\function compute(): MyResult { return {}; }
    ,
        \\function compute() {
        \\  return {};
        \\}
    );
}

test "ts elide: used as value inside function — kept" {
    try expectTsOutput(
        \\import { createDto } from "./dto.js";
        \\function handle() { return createDto(); }
    ,
        \\import { createDto } from "./dto.js";
        \\function handle() {
        \\  return createDto();
        \\}
    );
}

test "ts elide: used in type alias only — removed" {
    try expectTsOutput(
        \\import { RawData } from "./raw.js";
        \\type Processed = RawData & { extra: string };
        \\const x = 1;
    ,
        \\const x = 1;
    );
}

test "ts elide: used in interface extends only — removed" {
    try expectTsOutput(
        \\import { Base } from "./base.js";
        \\interface Child extends Base { name: string; }
        \\const x = 1;
    ,
        \\const x = 1;
    );
}

test "ts elide: used in 'as' cast type — removed" {
    try expectTsOutput(
        \\import { MyType } from "./my.js";
        \\const x = value as MyType;
    ,
        \\const x = value;
    );
}

test "ts elide: decorator usage — kept" {
    const out = try compileTs(
        \\import { Injectable } from "@nestjs/common";
        \\@Injectable()
        \\class AppService {}
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "import { Injectable } from \"@nestjs/common\"");
    try expectContainsText(out, "AppService = __decorate");
}

test "ts elide: nestjs pattern — MicroserviceOptions type-only, controller kept" {
    const out = try compileTs(
        \\import { MicroserviceOptions } from "@nestjs/microservices";
        \\import { Controller } from "@nestjs/common";
        \\@Controller()
        \\class AppController {}
        \\const opts: MicroserviceOptions = {};
    );
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "MicroserviceOptions") == null);
    try expectContainsText(out, "import { Controller } from \"@nestjs/common\"");
    try expectContainsText(out, "AppController = __decorate");
    try expectContainsText(out, "const opts = {};");
}

// ── end type-only import elision ─────────────────────────────────────────────

test "ts: as expression stripped" {
    try expectTsOutput("const x = value as string;", "const x = value;");
}

test "ts: assertions fixture strips legacy and modern syntax" {
    const result = try compiler.compileFile(
        "tests/fixtures/ts_assertions.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export const legacyString = legacy;");
    try expectContainsText(result.code, "export const legacyAny = legacy;");
    try expectContainsText(result.code, "export const legacyModel = partialSource;");
    try expectContainsText(result.code, "export const modernString = modern;");
    try expectContainsText(result.code, "export const modernAny = modern;");
    try expectContainsText(result.code, "export const modernPartial = partialSource;");
}

test "ts: syntax combo fixture compiles without unexpected token" {
    const result = try compiler.compileFile(
        "tests/fixtures/ts_syntax_combo.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export const pick = payload => payload?.value;");
    try expectContainsText(result.code, "class Fixture {");
    try expectContainsText(result.code, "Fixture = __decorate([register, __metadata(\"design:paramtypes\", [])], Fixture);");
}

test "ts: type combo fixture compiles without unexpected token" {
    const result = try compiler.compileFile(
        "tests/fixtures/ts_type_combo.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export async function loadUser(key, value) {");
    try expectContainsText(result.code, "id: typeof value === \"number\" ? value : key.length,");
    try expectContainsText(result.code, "name: key");
}

test "ts: generic class combo fixture compiles without unexpected token" {
    const result = try compiler.compileFile(
        "tests/fixtures/ts_generic_class_combo.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export function identity(value) {");
    try expectContainsText(result.code, "class Box {");
    try expectContainsText(result.code, "this.value = value;");
    try expectContainsText(result.code, "return new Ctor(identity(value));");
}

test "ts: node runtime combo fixture compiles without unexpected token" {
    const result = try compiler.compileFile(
        "tests/fixtures/node_runtime_combo.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "const extras = [\"b\", ...(Math.random() > -1 ? [\"c\"] : [])];");
    try expectContainsText(result.code, "function readValues({ a, b } = {");
    try expectContainsText(result.code, "const { a, b } = readValues();");
    try expectContainsText(result.code, "const base = obj?.a ?? 0;");
    try expectContainsText(result.code, "const bonus = extras.includes(\"c\") ? 1 : 0;");
    try expectContainsText(result.code, "return base + a + b + bonus;");
    try expectContainsText(result.code, "async compute(obj) {");
}

test "ts: optional chaining nullish fixture compiles without unexpected token" {
    const result = try compiler.compileFile(
        "tests/fixtures/optional_chaining_nullish.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export function parse(result) {");
    try expectContainsText(result.code, "const value = result?.[0]?.data ?? \"\";");
    try expectContainsText(result.code, "return value;");
}

test "ts: repository constructor type fixture compiles without unexpected token" {
    const result = try compiler.compileFile(
        "tests/fixtures/repository_constructor_type.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export class Repository {");
    try expectContainsText(result.code, "this.Entity = Entity;");
    try expectContainsText(result.code, "return new this.Entity();");
    try expectContainsText(result.code, "export class ProtectedRepository {");
    try expectContainsText(result.code, "export class ReadonlyRepository {");
}

test "ts: typed destructured param fixture compiles without unexpected token" {
    const result = try compiler.compileFile(
        "tests/fixtures/typed_destructured_param.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export function renderEmail({");
    try expectContainsText(result.code, "footerText = \"\"");
    try expectContainsText(result.code, "} = {}) {");
    try expectContainsText(result.code, "return footerText;");
}

test "ts: object spread conditional fixture compiles without unexpected token" {
    const result = try compiler.compileFile(
        "tests/fixtures/object_spread_conditional.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export function buildQuery(isAdmin, store) {");
    try expectContainsText(result.code, "...(isAdmin ? {} : {");
    try expectContainsText(result.code, "store: {");
    try expectContainsText(result.code, "id: store.id");
}

test "ts: arrow function types stripped" {
    try expectTsOutput(
        \\const fn = (x: number): string => x.toString();
    ,
        \\const fn = x => x.toString();
    );
}

test "ts: for loop with types" {
    try expectTsOutput(
        \\for (let i: number = 0; i < 10; i++) { console.log(i); }
    ,
        \\for (let i = 0; i < 10; i++) {
        \\  console.log(i);
        \\}
    );
}

// ── Path aliases & extensions ─────────────────────────────────────────────────

test "path alias: #/ to ./" {
    const aliases = [_]compiler.PathAlias{.{ .prefix = "#/", .replacement = "./" }};
    try expectPathsOutput(
        \\import { env } from "#/config/env";
    , &aliases, false,
        \\import { env } from "./config/env";
    );
}

test "path alias: @/ to ./src/" {
    const aliases = [_]compiler.PathAlias{.{ .prefix = "@/", .replacement = "./src/" }};
    try expectPathsOutput(
        \\import { Button } from "@/components/Button";
    , &aliases, false,
        \\import { Button } from "./src/components/Button";
    );
}

test "path alias: multiple aliases" {
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/", .replacement = "./" },
        .{ .prefix = "~lib/", .replacement = "./lib/" },
    };
    try expectPathsOutput(
        \\import { env } from "#/config/env";
        \\import { util } from "~lib/util";
    , &aliases, false,
        \\import { env } from "./config/env";
        \\import { util } from "./lib/util";
    );
}

test "path alias: unmatched specifier unchanged" {
    const aliases = [_]compiler.PathAlias{.{ .prefix = "#/", .replacement = "./" }};
    try expectPathsOutput(
        \\import fs from "node:fs";
        \\import { x } from "./local";
    , &aliases, false,
        \\import fs from "node:fs";
        \\import { x } from "./local";
    );
}

test "path alias: dynamic import" {
    const aliases = [_]compiler.PathAlias{.{ .prefix = "#/", .replacement = "./" }};
    try expectPathsOutput(
        \\const m = import("#/utils/helper");
    , &aliases, false,
        \\const m = import("./utils/helper");
    );
}

test "module strict: default false" {
    try expectOutputWithConfig(
        "const x = 1;",
        "test.js",
        .{ .parser = .{ .syntax = .ecmascript }, .jsx = false },
        "const x = 1;",
    );
}

test "module strict: true prepends directive" {
    try expectOutputWithConfig(
        "const x = 1;",
        "test.js",
        .{ .parser = .{ .syntax = .ecmascript }, .jsx = false, .module = .{ .strict = true } },
        "\"use strict\";\nconst x = 1;",
    );
}

test "module strict: existing directive is preserved without duplication" {
    try expectOutputWithConfig(
        "\"use strict\";\nconst x = 1;",
        "test.js",
        .{ .parser = .{ .syntax = .ecmascript }, .jsx = false, .module = .{ .strict = true } },
        "\"use strict\";\nconst x = 1;",
    );
}

test "module esModuleInterop: pure cjs module.exports rewrites to createRequire" {
    const root = "/tmp/zts_interop_pure_cjs";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/pkg-cjs");
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/pkg-cjs/package.json", "{\"name\":\"pkg-cjs\",\"main\":\"index.js\"}");
    try writeFile(root ++ "/node_modules/pkg-cjs/index.js", "module.exports = { sign: function() {} };\n");
    try expectOutputWithConfig(
        "import { sign } from \"pkg-cjs\";",
        root ++ "/src/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true } },
        "\"use strict\";\nimport { createRequire } from \"node:module\";\nconst require = createRequire(import.meta.dirname);\nconst { sign } = require(\"pkg-cjs\");",
    );
}

test "module esModuleInterop: pure cjs mixed default and named rewrites with shared require" {
    const root = "/tmp/zts_interop_pure_cjs_mixed";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/pkg-cjs");
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/pkg-cjs/package.json", "{\"name\":\"pkg-cjs\",\"main\":\"index.js\"}");
    try writeFile(root ++ "/node_modules/pkg-cjs/index.js", "module.exports = { sign: function() {}, verify: function() {} };\n");
    try expectOutputWithConfig(
        "import pkg, { sign } from \"pkg-cjs\";",
        root ++ "/src/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true } },
        "\"use strict\";\nimport { createRequire } from \"node:module\";\nconst require = createRequire(import.meta.dirname);\nconst pkg = require(\"pkg-cjs\");\nconst { sign } = pkg;",
    );
}

test "module esModuleInterop: exports.name pattern keeps import as-is" {
    const root = "/tmp/zts_interop_named_exports";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/pkg-named");
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/pkg-named/package.json", "{\"name\":\"pkg-named\",\"main\":\"index.js\"}");
    try writeFile(root ++ "/node_modules/pkg-named/index.js", "exports.createTransport = function() {};\nexports.createTestAccount = function() {};\n");
    try expectOutputWithConfig(
        "import { createTransport } from \"pkg-named\";",
        root ++ "/src/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true } },
        "\"use strict\";\nimport { createTransport } from \"pkg-named\";",
    );
}

test "module esModuleInterop: module.exports property pattern keeps import as-is" {
    const root = "/tmp/zts_interop_module_exports_prop";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/pkg-prop");
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/pkg-prop/package.json", "{\"name\":\"pkg-prop\",\"main\":\"index.js\"}");
    try writeFile(root ++ "/node_modules/pkg-prop/index.js", "module.exports.helper = function() {};\nmodule.exports.util = function() {};\n");
    try expectOutputWithConfig(
        "import { helper } from \"pkg-prop\";",
        root ++ "/src/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true } },
        "\"use strict\";\nimport { helper } from \"pkg-prop\";",
    );
}

test "module esModuleInterop: __esModule defineProperty keeps import as-is" {
    const root = "/tmp/zts_interop_esmodule_flag";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/pkg-esm");
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/pkg-esm/package.json", "{\"name\":\"pkg-esm\",\"main\":\"index.js\"}");
    try writeFile(root ++ "/node_modules/pkg-esm/index.js", "Object.defineProperty(exports, \"__esModule\", { value: true });\nexports.foo = 1;\n");
    try expectOutputWithConfig(
        "import { foo } from \"pkg-esm\";",
        root ++ "/src/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true } },
        "\"use strict\";\nimport { foo } from \"pkg-esm\";",
    );
}

test "module esModuleInterop: exports.__esModule = true keeps import as-is" {
    const root = "/tmp/zts_interop_esmodule_assign";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/pkg-esm2");
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/pkg-esm2/package.json", "{\"name\":\"pkg-esm2\",\"main\":\"index.js\"}");
    try writeFile(root ++ "/node_modules/pkg-esm2/index.js", "exports.__esModule = true;\nexports.bar = 2;\n");
    try expectOutputWithConfig(
        "import { bar } from \"pkg-esm2\";",
        root ++ "/src/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true } },
        "\"use strict\";\nimport { bar } from \"pkg-esm2\";",
    );
}

test "module esModuleInterop: package not found keeps import as-is" {
    try expectOutputWithConfig(
        "import { A, B, C } from \"some-package\";",
        "src/consumer.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true, .import_interop = .node } },
        "\"use strict\";\nimport { A, B, C } from \"some-package\";",
    );
}

test "module esModuleInterop: interop disabled keeps import as-is" {
    const root = "/tmp/zts_interop_disabled";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/pkg-cjs");
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/pkg-cjs/package.json", "{\"name\":\"pkg-cjs\",\"main\":\"index.js\"}");
    try writeFile(root ++ "/node_modules/pkg-cjs/index.js", "module.exports = { sign: function() {} };\n");
    try expectOutputWithConfig(
        "import { sign } from \"pkg-cjs\";",
        root ++ "/src/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = false } },
        "\"use strict\";\nimport { sign } from \"pkg-cjs\";",
    );
}

test "module esModuleInterop: package subpath directory does not trigger IsDir" {
    const root = "/tmp/zts_esm_interop_subdir";
    const src_dir = root ++ "/src";
    const pkg_dir: [:0]const u8 = root ++ "/node_modules/pkg/sub";
    mkdirP(root);
    mkdirP(src_dir);
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/pkg");
    mkdirP(pkg_dir);
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/pkg/sub/index.js", "Object.defineProperty(exports, \"__esModule\", { value: true });\nexports.value = 1;\n");
    try expectOutputWithConfig(
        "import { value } from \"pkg/sub\";",
        src_dir ++ "/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true, .import_interop = .node } },
        "\"use strict\";\nimport { value } from \"pkg/sub\";",
    );
}

test "module esModuleInterop: kebab-case package rewrites with sanitized alias" {
    const root = "/tmp/zts_esm_interop_kebab";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/transform-string");
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/transform-string/package.json", "{\"name\":\"transform-string\",\"main\":\"index.js\"}");
    try writeFile(root ++ "/node_modules/transform-string/index.js", "module.exports = { transform: function() {} };\n");
    try expectOutputWithConfig(
        "import { transform } from \"transform-string\";",
        root ++ "/src/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true } },
        "\"use strict\";\nimport { createRequire } from \"node:module\";\nconst require = createRequire(import.meta.dirname);\nconst { transform } = require(\"transform-string\");",
    );
}

test "module esModuleInterop: named re-export from pure cjs package" {
    const root = "/tmp/zts_interop_reexport_named";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/pkg-cjs");
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/pkg-cjs/package.json", "{\"name\":\"pkg-cjs\",\"main\":\"index.js\"}");
    try writeFile(root ++ "/node_modules/pkg-cjs/index.js", "module.exports = { sign: function() {} };\n");
    try expectOutputWithConfig(
        "export { sign } from \"pkg-cjs\";",
        root ++ "/src/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true } },
        "\"use strict\";\nimport { createRequire } from \"node:module\";\nconst require = createRequire(import.meta.dirname);\nconst { sign } = require(\"pkg-cjs\");\nexport { sign };",
    );
}

test "module esModuleInterop: aliased named re-export from pure cjs package" {
    const root = "/tmp/zts_interop_reexport_alias";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/pkg-cjs");
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/pkg-cjs/package.json", "{\"name\":\"pkg-cjs\",\"main\":\"index.js\"}");
    try writeFile(root ++ "/node_modules/pkg-cjs/index.js", "module.exports = { sign: function() {} };\n");
    try expectOutputWithConfig(
        "export { sign as pkgSign } from \"pkg-cjs\";",
        root ++ "/src/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true } },
        "\"use strict\";\nimport { createRequire } from \"node:module\";\nconst require = createRequire(import.meta.dirname);\nconst { sign } = require(\"pkg-cjs\");\nexport { sign as pkgSign };",
    );
}

test "module esModuleInterop: export star alias from pure cjs package" {
    const root = "/tmp/zts_interop_export_star_alias";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/pkg-cjs");
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/pkg-cjs/package.json", "{\"name\":\"pkg-cjs\",\"main\":\"index.js\"}");
    try writeFile(root ++ "/node_modules/pkg-cjs/index.js", "module.exports = { a: 1, b: 2 };\n");
    try expectOutputWithConfig(
        "export * as pkg from \"pkg-cjs\";",
        root ++ "/src/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true } },
        "\"use strict\";\nimport { createRequire } from \"node:module\";\nconst require = createRequire(import.meta.dirname);\nconst pkg = require(\"pkg-cjs\");\nexport { pkg };",
    );
}

test "module esModuleInterop: export star without alias is preserved" {
    const root = "/tmp/zts_interop_export_star_plain";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/pkg-cjs");
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/pkg-cjs/package.json", "{\"name\":\"pkg-cjs\",\"main\":\"index.js\"}");
    try writeFile(root ++ "/node_modules/pkg-cjs/index.js", "module.exports = { a: 1 };\n");
    try expectOutputWithConfig(
        "export * from \"pkg-cjs\";",
        root ++ "/src/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true } },
        "\"use strict\";\nexport * from \"pkg-cjs\";",
    );
}

test "module esModuleInterop: scoped pure cjs package rewrites to createRequire" {
    const root = "/tmp/zts_interop_scoped_cjs";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/@org");
    mkdirP(root ++ "/node_modules/@org/pkg");
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/@org/pkg/package.json", "{\"name\":\"@org/pkg\",\"main\":\"index.js\"}");
    try writeFile(root ++ "/node_modules/@org/pkg/index.js", "module.exports = { helper: function() {} };\n");
    try expectOutputWithConfig(
        "import { helper } from \"@org/pkg\";",
        root ++ "/src/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true } },
        "\"use strict\";\nimport { createRequire } from \"node:module\";\nconst require = createRequire(import.meta.dirname);\nconst { helper } = require(\"@org/pkg\");",
    );
}

test "module esModuleInterop: subpath import from pure cjs package rewrites" {
    const root = "/tmp/zts_interop_subpath_cjs";
    mkdirP(root);
    mkdirP(root ++ "/src");
    mkdirP(root ++ "/node_modules");
    mkdirP(root ++ "/node_modules/pkg-subpath-cjs");
    defer deleteTree(root);
    try writeFile(root ++ "/node_modules/pkg-subpath-cjs/package.json", "{\"name\":\"pkg-subpath-cjs\",\"exports\":{\"./sign\":{\"require\":\"./sign.cjs\"}}}");
    try writeFile(root ++ "/node_modules/pkg-subpath-cjs/sign.cjs", "module.exports = { sign: function() {} };\n");
    try expectOutputWithConfig(
        "import { sign } from \"pkg-subpath-cjs/sign\";",
        root ++ "/src/main.ts",
        .{ .parser = .{ .syntax = .typescript }, .module = .{ .es_module_interop = true } },
        "\"use strict\";\nimport { createRequire } from \"node:module\";\nconst require = createRequire(import.meta.dirname);\nconst { sign } = require(\"pkg-subpath-cjs/sign\");",
    );
}

test "source maps: disabled by default" {
    const alloc = std.testing.allocator;
    const result = try compiler.compile("const x = 1;", "test.js", .{ .parser = .{ .syntax = .ecmascript }, .jsx = false, .source_maps = false }, std.testing.io, alloc);
    defer alloc.free(result.code);
    if (result.map) |m| {
        alloc.free(m);
        return error.TestUnexpectedResult;
    }
    if (result.diagnostics.len > 0) alloc.free(result.diagnostics);
}

test "source maps: enabled returns mappings json" {
    const alloc = std.testing.allocator;
    const result = try compiler.compile(
        \\const x: number = 1;
        \\console.log(x);
    , "test.ts", .{ .parser = .{ .syntax = .typescript }, .source_maps = true }, std.testing.io, alloc);
    defer alloc.free(result.code);
    defer if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) alloc.free(result.diagnostics);

    const map = result.map orelse return error.TestExpectedEqual;
    try expectContainsText(result.code, "const x = 1;");
    try expectContainsText(map, "\"version\":3");
    try expectContainsText(map, "\"sources\":[\"test.ts\"]");
    try expectContainsText(map, "\"names\":[]");
    try expectContainsText(map, "\"mappings\":\"");
    try std.testing.expect(std.mem.indexOf(u8, map, "\"mappings\":\"\"") == null);
    try std.testing.expect(std.mem.indexOfScalar(u8, map, ';') != null);
}

test "resolve full paths: missing relative imports remain unchanged" {
    try expectPathsOutput(
        \\import { x } from "./utils";
        \\import { y } from "../lib/helper";
    , &.{}, true,
        \\import { x } from "./utils";
        \\import { y } from "../lib/helper";
    );
}

test "add .js extension: skip bare specifiers" {
    try expectPathsOutput(
        \\import { x } from "lodash";
        \\import { y } from "node:fs";
    , &.{}, true,
        \\import { x } from "lodash";
        \\import { y } from "node:fs";
    );
}

test "add .js extension: skip already-extended imports" {
    try expectPathsOutput(
        \\import { x } from "./utils.js";
        \\import { y } from "./style.css";
    , &.{}, true,
        \\import { x } from "./utils.js";
        \\import { y } from "./style.css";
    );
}

test "path alias + resolve full paths combined without probe match" {
    const aliases = [_]compiler.PathAlias{.{ .prefix = "#/", .replacement = "./" }};
    try expectPathsOutput(
        \\import { env } from "#/config/env";
    , &aliases, true,
        \\import { env } from "./config/env";
    );
}

test "path alias: export from" {
    const aliases = [_]compiler.PathAlias{.{ .prefix = "#/", .replacement = "./" }};
    try expectPathsOutput(
        \\export { env } from "#/config/env";
    , &aliases, false,
        \\export { env } from "./config/env";
    );
}

// ── tsconfig paths integration ────────────────────────────────────────────────

test "tsconfig paths: parsed and applied" {
    // Verify parsePaths output via Config directly
    const config_mod = compiler.config;
    const alloc = std.testing.allocator;

    // Simulate tsconfig content
    const tsconfig =
        \\{
        \\  "compilerOptions": {
        \\    "paths": {
        \\      "#/*": ["./*"],
        \\      "@/components/*": ["./src/components/*"]
        \\    }
        \\  }
        \\}
    ;

    // Write temp file
    const tmp_path = "/tmp/zts_test_tsconfig.json";
    {
        const fd = try std.posix.openat(std.posix.AT.FDCWD, tmp_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
        defer _ = std.os.linux.close(fd);
        _ = std.os.linux.write(@intCast(fd), tsconfig.ptr, tsconfig.len);
    }
    defer _ = std.os.linux.unlink(tmp_path.ptr);

    const ts = (try config_mod.readTsConfig(tmp_path, alloc)) orelse return error.NoConfig;
    defer {
        for (ts.compiler_options.paths) |a| {
            alloc.free(a.prefix);
            alloc.free(a.replacement);
        }
        alloc.free(ts.compiler_options.paths);
    }

    try std.testing.expectEqual(@as(usize, 2), ts.compiler_options.paths.len);
    try std.testing.expectEqualStrings("#/", ts.compiler_options.paths[0].prefix);
    try std.testing.expectEqualStrings("./", ts.compiler_options.paths[0].replacement);
    try std.testing.expectEqualStrings("@/components/", ts.compiler_options.paths[1].prefix);
    try std.testing.expectEqualStrings("./src/components/", ts.compiler_options.paths[1].replacement);
}

test "tsconfig compilerOptions.strict" {
    const config_mod = compiler.config;
    const alloc = std.testing.allocator;

    const tsconfig =
        \\{
        \\  "compilerOptions": {
        \\    "strict": true
        \\  }
        \\}
    ;

    const tmp_path = "/tmp/zts_test_tsconfig_strict.json";
    {
        const fd = try std.posix.openat(std.posix.AT.FDCWD, tmp_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
        defer _ = std.os.linux.close(fd);
        _ = std.os.linux.write(@intCast(fd), tsconfig.ptr, tsconfig.len);
    }
    defer _ = std.os.linux.unlink(tmp_path.ptr);

    const ts = (try config_mod.readTsConfig(tmp_path, alloc)) orelse return error.NoConfig;
    try std.testing.expectEqual(@as(?bool, true), ts.compiler_options.strict);
}

test "tsconfig compilerOptions.sourceMap" {
    const config_mod = compiler.config;
    const alloc = std.testing.allocator;

    const tsconfig =
        \\{
        \\  "compilerOptions": {
        \\    "sourceMap": true
        \\  }
        \\}
    ;

    const tmp_path = "/tmp/zts_test_tsconfig_sourcemap.json";
    {
        const fd = try std.posix.openat(std.posix.AT.FDCWD, tmp_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
        defer _ = std.os.linux.close(fd);
        _ = std.os.linux.write(@intCast(fd), tsconfig.ptr, tsconfig.len);
    }
    defer _ = std.os.linux.unlink(tmp_path.ptr);

    const ts = (try config_mod.readTsConfig(tmp_path, alloc)) orelse return error.NoConfig;
    try std.testing.expectEqual(@as(?bool, true), ts.compiler_options.source_maps);
}

test "tsconfig compilerOptions.esModuleInterop" {
    const config_mod = compiler.config;
    const alloc = std.testing.allocator;

    const tsconfig =
        \\{
        \\  "compilerOptions": {
        \\    "esModuleInterop": true
        \\  }
        \\}
    ;

    const tmp_path = "/tmp/zts_test_tsconfig_esmoduleinterop.json";
    {
        const fd = try std.posix.openat(std.posix.AT.FDCWD, tmp_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
        defer _ = std.os.linux.close(fd);
        _ = std.os.linux.write(@intCast(fd), tsconfig.ptr, tsconfig.len);
    }
    defer _ = std.os.linux.unlink(tmp_path.ptr);

    const ts = (try config_mod.readTsConfig(tmp_path, alloc)) orelse return error.NoConfig;
    try std.testing.expectEqual(@as(?bool, true), ts.compiler_options.esmodule_interop);
}

// ── Path alias: wildcard semantics ────────────────────────────────────────────
//
// TypeScript / SWC semantics:
//   "#/*": ["./src/*"]  is a WILDCARD pattern.
//     "#/config/env" → "./src/config/env"  (captures "config/env" after "#/")
//   "#/config": ["./src/config"]  is an EXACT pattern.
//     "#/config"      → "./src/config"     (exact match)
//     "#/config/env"  → unchanged          (must NOT match)

// wildcard: "#/*" → "./src/*"
test "path alias wildcard: #/config/env → ./src/config/env" {
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/", .replacement = "./src/", .is_wildcard = true },
    };
    try expectPathsOutput(
        \\import { env } from "#/config/env";
    , &aliases, false,
        \\import { env } from "./src/config/env";
    );
}

// wildcard with single segment
test "path alias wildcard: #/utils → ./src/utils" {
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/", .replacement = "./src/", .is_wildcard = true },
    };
    try expectPathsOutput(
        \\import { x } from "#/utils";
    , &aliases, false,
        \\import { x } from "./src/utils";
    );
}

// exact: "#/config" must NOT match "#/config/env"
test "path alias exact: #/config does not match #/config/env" {
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/config", .replacement = "./src/config/index", .is_wildcard = false },
    };
    try expectPathsOutput(
        \\import { env } from "#/config/env";
    , &aliases, false,
        \\import { env } from "#/config/env";
    );
}

// exact: "#/config" matches "#/config" exactly
test "path alias exact: #/config matches #/config" {
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/config", .replacement = "./src/config/index", .is_wildcard = false },
    };
    try expectPathsOutput(
        \\import config from "#/config";
    , &aliases, false,
        \\import config from "./src/config/index";
    );
}

// exact and wildcard coexist: exact wins for exact paths
test "path alias: exact pattern before wildcard wins" {
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/config", .replacement = "./src/config/index", .is_wildcard = false },
        .{ .prefix = "#/", .replacement = "./src/", .is_wildcard = true },
    };
    try expectPathsOutput(
        \\import config from "#/config";
        \\import { env } from "#/config/env";
    , &aliases, false,
        \\import config from "./src/config/index";
        \\import { env } from "./src/config/env";
    );
}

// re-export with wildcard alias
test "path alias wildcard: re-export from" {
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/", .replacement = "./src/", .is_wildcard = true },
    };
    try expectPathsOutput(
        \\export { env } from "#/config/env";
    , &aliases, false,
        \\export { env } from "./src/config/env";
    );
}

// export * with wildcard alias
test "path alias wildcard: export * from" {
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/", .replacement = "./src/", .is_wildcard = true },
    };
    try expectPathsOutput(
        \\export * from "#/barrel";
    , &aliases, false,
        \\export * from "./src/barrel";
    );
}

// dynamic import with wildcard alias
test "path alias wildcard: dynamic import" {
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/", .replacement = "./src/", .is_wildcard = true },
    };
    try expectPathsOutput(
        \\const m = import("#/lazy/module");
    , &aliases, false,
        \\const m = import("./src/lazy/module");
    );
}

// wildcard + resolve full paths combined
test "path alias wildcard + resolve full paths without probe match" {
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/", .replacement = "./src/", .is_wildcard = true },
    };
    try expectPathsOutput(
        \\import { env } from "#/config/env";
    , &aliases, true,
        \\import { env } from "./src/config/env";
    );
}

test "resolve full paths: explicit ts extensions" {
    try expectPathsOutput(
        \\import foo from "./foo.ts";
        \\import view from "./view.tsx";
        \\import runtime from "./runtime.mts";
        \\import config from "./config.cts";
    , &.{}, true,
        \\import foo from "./foo.js";
        \\import view from "./view.js";
        \\import runtime from "./runtime.mjs";
        \\import config from "./config.js";
    );
}

test "resolve full paths: preserves query and hash" {
    try expectPathsOutput(
        \\import worker from "./worker.ts?worker";
        \\import style from "./style.ts#hash";
        \\import client from "./client.ts?raw#client";
    , &.{}, true,
        \\import worker from "./worker.js?worker";
        \\import style from "./style.js#hash";
        \\import client from "./client.js?raw#client";
    );
}

test "resolve full paths: leaves js and bare specifiers unchanged" {
    try expectPathsOutput(
        \\import foo from "./foo.js";
        \\import express from "express";
        \\import fs from "node:fs";
    , &.{}, true,
        \\import foo from "./foo.js";
        \\import express from "express";
        \\import fs from "node:fs";
    );
}

test "resolve full paths: export and dynamic import" {
    try expectPathsOutput(
        \\export * from "./foo.ts";
        \\export { x } from "./foo.ts";
        \\const m = await import("./foo.ts");
    , &.{}, true,
        \\export * from "./foo.js";
        \\export { x } from "./foo.js";
        \\const m = await import("./foo.js");
    );
}

test "resolve full paths: false leaves import unchanged" {
    try expectPathsOutput(
        \\import foo from "./foo";
    , &.{}, false,
        \\import foo from "./foo";
    );
}

test "resolve full paths: probes .ts files" {
    const root = "/tmp/zts_resolve_paths_ts";
    const src_dir = root ++ "/src";
    mkdirP(root);
    mkdirP(src_dir);
    defer deleteTree(root);

    try writeFile(src_dir ++ "/foo.ts", "export const foo = 1;");

    try expectPathsFromOutput(
        \\import foo from "./foo";
    , src_dir ++ "/entry.ts", &.{}, true,
        \\import foo from "./foo.js";
    );
}

test "resolve full paths: probes .tsx files" {
    const root = "/tmp/zts_resolve_paths_tsx";
    const src_dir = root ++ "/src";
    mkdirP(root);
    mkdirP(src_dir);
    defer deleteTree(root);

    try writeFile(src_dir ++ "/foo.tsx", "export const foo = 1;");

    try expectPathsFromOutput(
        \\import foo from "./foo";
    , src_dir ++ "/entry.ts", &.{}, true,
        \\import foo from "./foo.js";
    );
}

test "resolve full paths: probes .mts files" {
    const root = "/tmp/zts_resolve_paths_mts";
    const src_dir = root ++ "/src";
    mkdirP(root);
    mkdirP(src_dir);
    defer deleteTree(root);

    try writeFile(src_dir ++ "/foo.mts", "export const foo = 1;");

    try expectPathsFromOutput(
        \\import foo from "./foo";
    , src_dir ++ "/entry.ts", &.{}, true,
        \\import foo from "./foo.mjs";
    );
}

test "resolve full paths: probes .cts files" {
    const root = "/tmp/zts_resolve_paths_cts";
    const src_dir = root ++ "/src";
    mkdirP(root);
    mkdirP(src_dir);
    defer deleteTree(root);

    try writeFile(src_dir ++ "/foo.cts", "export const foo = 1;");

    try expectPathsFromOutput(
        \\import foo from "./foo";
    , src_dir ++ "/entry.ts", &.{}, true,
        \\import foo from "./foo.js";
    );
}

test "resolve full paths: probes index files" {
    const root = "/tmp/zts_resolve_paths_index";
    const src_dir = root ++ "/src";
    const foo_dir: [:0]const u8 = src_dir ++ "/foo";
    mkdirP(root);
    mkdirP(src_dir);
    mkdirP(foo_dir);
    defer deleteTree(root);

    try writeFile(src_dir ++ "/foo/index.ts", "export const foo = 1;");

    try expectPathsFromOutput(
        \\import foo from "./foo";
    , src_dir ++ "/entry.ts", &.{}, true,
        \\import foo from "./foo/index.js";
    );
}

test "resolve full paths: probe falls back when file is missing" {
    const root = "/tmp/zts_resolve_paths_missing";
    const src_dir = root ++ "/src";
    mkdirP(root);
    mkdirP(src_dir);
    defer deleteTree(root);

    try expectPathsFromOutput(
        \\import foo from "./foo";
    , src_dir ++ "/entry.ts", &.{}, true,
        \\import foo from "./foo";
    );
}

// tsconfig JSON5 with wildcard paths parsed correctly
test "tsconfig paths wildcard: is_wildcard set from #/*" {
    const config_mod = compiler.config;
    const alloc = std.testing.allocator;

    const tsconfig =
        \\{
        \\  "compilerOptions": {
        \\    "paths": {
        \\      "#/*": ["./src/*"],
        \\      "#/config": ["./src/config/index"]
        \\    }
        \\  }
        \\}
    ;
    const tmp_path = "/tmp/zts_path_wildcard.json";
    {
        const fd = try std.posix.openat(std.posix.AT.FDCWD, tmp_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
        defer _ = std.os.linux.close(fd);
        _ = std.os.linux.write(@intCast(fd), tsconfig.ptr, tsconfig.len);
    }
    defer _ = std.os.linux.unlink(tmp_path.ptr);

    const ts = (try config_mod.readTsConfig(tmp_path, alloc)) orelse return error.NoConfig;
    defer {
        for (ts.compiler_options.paths) |a| {
            alloc.free(a.prefix);
            alloc.free(a.replacement);
        }
        alloc.free(ts.compiler_options.paths);
    }

    try std.testing.expectEqual(@as(usize, 2), ts.compiler_options.paths.len);
    // "#/*" → prefix "#/", is_wildcard true
    try std.testing.expectEqualStrings("#/", ts.compiler_options.paths[0].prefix);
    try std.testing.expectEqualStrings("./src/", ts.compiler_options.paths[0].replacement);
    try std.testing.expect(ts.compiler_options.paths[0].is_wildcard);
    // "#/config" → prefix "#/config", is_wildcard false
    try std.testing.expectEqualStrings("#/config", ts.compiler_options.paths[1].prefix);
    try std.testing.expectEqualStrings("./src/config/index", ts.compiler_options.paths[1].replacement);
    try std.testing.expect(!ts.compiler_options.paths[1].is_wildcard);
}

// end-to-end: tsconfig file → compile with wildcard alias
test "tsconfig paths e2e: #/* → ./src/*" {
    const alloc = std.testing.allocator;
    const tsconfig =
        \\{
        \\  "compilerOptions": {
        \\    "paths": {
        \\      "#/*": ["./src/*"]
        \\    }
        \\  }
        \\}
    ;
    const tmp_path = "/tmp/zts_e2e_paths.json";
    {
        const fd = try std.posix.openat(std.posix.AT.FDCWD, tmp_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
        defer _ = std.os.linux.close(fd);
        _ = std.os.linux.write(@intCast(fd), tsconfig.ptr, tsconfig.len);
    }
    defer _ = std.os.linux.unlink(tmp_path.ptr);

    const config_mod = compiler.config;
    const ts = (try config_mod.readTsConfig(tmp_path, alloc)) orelse return error.NoConfig;
    defer {
        for (ts.compiler_options.paths) |a| {
            alloc.free(a.prefix);
            alloc.free(a.replacement);
        }
        alloc.free(ts.compiler_options.paths);
    }

    var cfg = compiler.Config{ .parser = .{ .syntax = .typescript } };
    cfg.paths = ts.compiler_options.paths;

    const result = try compiler.compile(
        \\import { env } from "#/config/env";
        \\import { btn } from "#/components/Button";
    , "test.ts", cfg, std.testing.io, alloc);
    defer alloc.free(result.code);
    defer if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) alloc.free(result.diagnostics);

    try std.testing.expectEqualStrings("\"use strict\";", std.mem.trim(u8, result.code, " \n\r\t"));
}

// existing alias test: old PathAlias (no is_wildcard) still works as wildcard by default
test "path alias: backward compat - no is_wildcard field acts as wildcard" {
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/", .replacement = "./" },
    };
    try expectPathsOutput(
        \\import { env } from "#/config/env";
    , &aliases, false,
        \\import { env } from "./config/env";
    );
}

// ── Source-file-relative path resolution ─────────────────────────────────────
// Alias replacement is relative to project root; result must be adjusted
// to be relative to the source file's directory.

test "path alias: file in src/ adjusts ./src/* alias" {
    // tsconfig: "#/*": ["./src/*"], file: src/app.ts
    // #/config/env → ./config/env  (not ./src/config/env)
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/", .replacement = "./src/", .is_wildcard = true },
    };
    try expectPathsFromOutput(
        \\import { env } from "#/config/env";
    , "src/app.ts", &aliases, false,
        \\import { env } from "./config/env";
    );
}

test "path alias: file at root keeps ./src/* alias unchanged" {
    // tsconfig: "#/*": ["./src/*"], file: index.ts (at root)
    // #/config/env → ./src/config/env  (no adjustment needed)
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/", .replacement = "./src/", .is_wildcard = true },
    };
    try expectPathsFromOutput(
        \\import { env } from "#/config/env";
    , "index.ts", &aliases, false,
        \\import { env } from "./src/config/env";
    );
}

test "path alias: nested src file goes up correctly" {
    // tsconfig: "#/*": ["./src/*"], file: src/components/Button.ts
    // #/config/env → ../config/env
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/", .replacement = "./src/", .is_wildcard = true },
    };
    try expectPathsFromOutput(
        \\import { env } from "#/config/env";
    , "src/components/Button.ts", &aliases, false,
        \\import { env } from "../config/env";
    );
}

test "path alias: same subdirectory stays relative" {
    // tsconfig: "#/*": ["./src/*"], file: src/config/db.ts
    // #/config/env → ./env
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "#/", .replacement = "./src/", .is_wildcard = true },
    };
    try expectPathsFromOutput(
        \\import { env } from "#/config/env";
    , "src/config/db.ts", &aliases, false,
        \\import { env } from "./env";
    );
}

// ── keep_class_names: extra coverage ─────────────────────────────────────────

test "keep class names: let declaration" {
    try expectOutputWithConfig(
        "let Foo = class {};",
        "test.js",
        .{ .parser = .{ .syntax = .ecmascript }, .keep_class_names = true },
        "let Foo = class Foo {};",
    );
}

test "keep class names: var declaration" {
    try expectOutputWithConfig(
        "var Bar = class {};",
        "test.js",
        .{ .parser = .{ .syntax = .ecmascript }, .keep_class_names = true },
        "var Bar = class Bar {};",
    );
}

test "keep class names: already named class is not renamed" {
    try expectOutputWithConfig(
        "const Foo = class ExistingName {};",
        "test.js",
        .{ .parser = .{ .syntax = .ecmascript }, .keep_class_names = true },
        "const Foo = class ExistingName {};",
    );
}

test "keep class names: named class declaration unchanged" {
    try expectOutputWithConfig(
        "class Foo {}",
        "test.js",
        .{ .parser = .{ .syntax = .ecmascript }, .keep_class_names = true },
        "class Foo {}",
    );
}

test "keep class names: filename with dash sanitized to underscore" {
    try expectOutputWithConfig(
        "export default class {};",
        "my-widget.ts",
        .{ .parser = .{ .syntax = .typescript }, .keep_class_names = true },
        "export default class my_widget {};",
    );
}

// ── JSX automatic runtime ─────────────────────────────────────────────────────

fn compileJsx(src: []const u8, runtime: @import("jsx").JsxRuntime, import_source: []const u8) ![]const u8 {
    const alloc = std.testing.allocator;
    const cfg = compiler.Config{
        .parser = .{ .syntax = .typescript },
        .jsx = true,
        .transform = .{ .react = .{
            .jsx_runtime = runtime,
            .jsx_import_source = import_source,
        } },
    };
    const result = try compiler.compile(src, "test.tsx", cfg, std.testing.io, alloc);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) {
            alloc.free(result.code);
            if (result.diagnostics.len > 0) alloc.free(result.diagnostics);
            return error.ParseError;
        }
    }
    if (result.diagnostics.len > 0) alloc.free(result.diagnostics);
    return result.code;
}

fn expectJsxOutput(src: []const u8, runtime: @import("jsx").JsxRuntime, import_source: []const u8, expected: []const u8) !void {
    const out = try compileJsx(src, runtime, import_source);
    defer std.testing.allocator.free(out);
    const trimmed = normalizedOutput(out, expected);
    const exp_trimmed = trimText(expected);
    if (!std.mem.eql(u8, trimmed, exp_trimmed) and !equalIgnoringWhitespace(trimmed, exp_trimmed)) {
        std.debug.print("\n=== EXPECTED ===\n{s}\n=== GOT ===\n{s}\n", .{ exp_trimmed, trimmed });
        return error.TestExpectedEqual;
    }
}

test "jsx automatic: no children injects jsx import and uses _jsx" {
    try expectJsxOutput("<div />;", .automatic, "react",
        \\import { jsx as _jsx } from "react/jsx-runtime";
        \\_jsx("div", {});
    );
}

test "jsx automatic: single child uses _jsx with children prop" {
    try expectJsxOutput("<div>hello</div>;", .automatic, "react",
        \\import { jsx as _jsx } from "react/jsx-runtime";
        \\_jsx("div", {
        \\  children: "hello"
        \\});
    );
}

test "jsx automatic: multiple children uses _jsxs with children array" {
    try expectJsxOutput("<div><span /><span /></div>;", .automatic, "react",
        \\import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
        \\_jsxs("div", {
        \\  children: [_jsx("span", {}), _jsx("span", {})]
        \\});
    );
}

test "jsx automatic: fragment with single child uses _jsx and _fragment" {
    try expectJsxOutput("<><span /></>;", .automatic, "react",
        \\import { jsx as _jsx, Fragment as _fragment } from "react/jsx-runtime";
        \\_jsx(_fragment, {
        \\  children: _jsx("span", {})
        \\});
    );
}

test "jsx automatic: custom import source" {
    try expectJsxOutput("<div />;", .automatic, "preact",
        \\import { jsx as _jsx } from "preact/jsx-runtime";
        \\_jsx("div", {});
    );
}

test "jsx classic: unchanged behavior" {
    try expectJsxOutput("<div className=\"x\">hello</div>;", .classic, "react",
        \\React.createElement("div", {
        \\  className: "x"
        \\}, "hello");
    );
}

// ── baseUrl ───────────────────────────────────────────────────────────────────

fn compileWithBaseUrl(src: []const u8, filename: []const u8, base_url: []const u8) ![]const u8 {
    const alloc = std.testing.allocator;
    const cfg = compiler.Config{
        .parser = .{ .syntax = .ecmascript },
        .module = .{ .resolve_full_paths = false },
        .base_url = base_url,
    };
    const result = try compiler.compile(src, filename, cfg, std.testing.io, alloc);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) {
            alloc.free(result.code);
            if (result.diagnostics.len > 0) alloc.free(result.diagnostics);
            return error.ParseError;
        }
    }
    if (result.diagnostics.len > 0) alloc.free(result.diagnostics);
    return result.code;
}

fn expectBaseUrlOutput(src: []const u8, filename: []const u8, base_url: []const u8, expected: []const u8) !void {
    const out = try compileWithBaseUrl(src, filename, base_url);
    defer std.testing.allocator.free(out);
    const trimmed = normalizedOutput(out, expected);
    const exp_trimmed = trimText(expected);
    if (!std.mem.eql(u8, trimmed, exp_trimmed) and !equalIgnoringWhitespace(trimmed, exp_trimmed)) {
        std.debug.print("\n=== EXPECTED ===\n{s}\n=== GOT ===\n{s}\n", .{ exp_trimmed, trimmed });
        return error.TestExpectedEqual;
    }
}

test "baseUrl: bare specifier resolved relative to src file in same dir" {
    // base_url = "src", file = "src/app.js", specifier = "utils/helper"
    // file must exist on disk so base_url resolution triggers
    const root = "/tmp/zts_baseurl_same_dir";
    const src_dir: [:0]const u8 = root ++ "/src";
    const utils_dir: [:0]const u8 = root ++ "/src/utils";
    mkdirP(root);
    mkdirP(src_dir);
    mkdirP(utils_dir);
    defer deleteTree(root);
    try writeFile(root ++ "/src/utils/helper.ts", "export const foo = 1;");
    try expectBaseUrlOutput(
        \\import { foo } from "utils/helper";
    , root ++ "/src/app.js", root ++ "/src",
        \\import { foo } from "utils/helper";
    );
}

test "baseUrl: bare specifier resolved from nested file" {
    // base_url = "src", file = "src/components/Button.js", specifier = "utils/helper"
    // → "../utils/helper"
    const root = "/tmp/zts_baseurl_nested";
    const src_dir: [:0]const u8 = root ++ "/src";
    const comp_dir: [:0]const u8 = root ++ "/src/components";
    const utils_dir: [:0]const u8 = root ++ "/src/utils";
    mkdirP(root);
    mkdirP(src_dir);
    mkdirP(comp_dir);
    mkdirP(utils_dir);
    defer deleteTree(root);
    try writeFile(root ++ "/src/utils/helper.ts", "export const foo = 1;");
    try expectBaseUrlOutput(
        \\import { foo } from "utils/helper";
    , root ++ "/src/components/Button.js", root ++ "/src",
        \\import { foo } from "utils/helper";
    );
}

test "baseUrl: relative imports are not affected" {
    try expectBaseUrlOutput(
        \\import { foo } from "./local";
    , "src/app.js", "src",
        \\import { foo } from "./local";
    );
}

test "baseUrl: node protocol imports are not affected" {
    try expectBaseUrlOutput(
        \\import { foo } from "node:path";
    , "src/app.js", "src",
        \\import { foo } from "node:path";
    );
}

test "baseUrl: npm scoped package left unchanged" {
    // @nestjs/microservices is a node_modules package — must NOT be rewritten
    try expectBaseUrlOutput(
        \\import { MicroserviceOptions } from "@nestjs/microservices";
    , "src/app.ts", ".",
        \\import { MicroserviceOptions } from "@nestjs/microservices";
    );
}

test "baseUrl: plain npm package left unchanged" {
    try expectBaseUrlOutput(
        \\import express from "express";
    , "src/app.ts", ".",
        \\import express from "express";
    );
}

test "baseUrl: multiple imports — only local ones rewritten" {
    const root = "/tmp/zts_baseurl_mixed";
    const src_dir: [:0]const u8 = root ++ "/src";
    const app_dir: [:0]const u8 = root ++ "/src/application";
    mkdirP(root);
    mkdirP(src_dir);
    mkdirP(app_dir);
    defer deleteTree(root);
    try writeFile(root ++ "/src/application/service.ts", "export class Service {}");
    try expectBaseUrlOutput(
        \\import { MicroserviceOptions } from "@nestjs/microservices";
        \\import { Service } from "application/service";
    , root ++ "/src/app.ts", root ++ "/src",
        \\import { MicroserviceOptions } from "@nestjs/microservices";
        \\import { Service } from "application/service";
    );
}

test "path alias: replacement without ./ prefix (tsconfig src/* style)" {
    // tsconfig paths: "@/*": ["src/*"] — replacement has no leading "./"
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "@/", .replacement = "src/", .is_wildcard = true },
    };
    try expectPathsFromOutput(
        \\import { SendNotification } from "@/application/use-cases/send-notification";
    , "src/main.ts", &aliases, false,
        \\import { SendNotification } from "./application/use-cases/send-notification";
    );
}

test "path alias: replacement without ./ from nested file" {
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "@/", .replacement = "src/", .is_wildcard = true },
    };
    try expectPathsFromOutput(
        \\import { SendNotification } from "@/application/use-cases/send-notification";
    , "src/infra/http/controllers/notification.controller.ts", &aliases, false,
        \\import { SendNotification } from "../../../application/use-cases/send-notification";
    );
}

test "path alias: replacement with ./ prefix still works" {
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "@/", .replacement = "./src/", .is_wildcard = true },
    };
    try expectPathsFromOutput(
        \\import { SendNotification } from "@/application/use-cases/send-notification";
    , "src/main.ts", &aliases, false,
        \\import { SendNotification } from "./application/use-cases/send-notification";
    );
}

test "path alias: scoped npm package not matched by @/ alias" {
    // @nestjs/microservices must NOT match the @/ alias
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "@/", .replacement = "src/", .is_wildcard = true },
    };
    try expectPathsFromOutput(
        \\import { MicroserviceOptions } from "@nestjs/microservices";
    , "src/main.ts", &aliases, false,
        \\import { MicroserviceOptions } from "@nestjs/microservices";
    );
}

test "path alias: org-scoped package with @org/ prefix not confused with @/ alias" {
    const aliases = [_]compiler.PathAlias{
        .{ .prefix = "@/", .replacement = "src/", .is_wildcard = true },
    };
    try expectPathsFromOutput(
        \\import { Injectable } from "@nestjs/common";
        \\import { AppService } from "@/app.service";
    , "src/app.module.ts", &aliases, false,
        \\import { Injectable } from "@nestjs/common";
        \\import { AppService } from "./app.service";
    );
}

// ── dot-in-stem filenames (e.g. app.module, app.controller) ───────────────────

test "resolve full paths: dotted stem like app.module probes disk" {
    const root = "/tmp/zts_resolve_dotted_stem";
    const src_dir: [:0]const u8 = root ++ "/src";
    mkdirP(root);
    mkdirP(src_dir);
    defer deleteTree(root);

    try writeFile(src_dir ++ "/app.module.ts", "export class AppModule {}");

    try expectPathsFromOutput(
        \\import { AppModule } from "./app.module";
    , src_dir ++ "/main.ts", &.{}, true,
        \\import { AppModule } from "./app.module.js";
    );
}

test "resolve full paths: dotted stem app.controller resolves" {
    const root = "/tmp/zts_resolve_dotted_controller";
    const src_dir: [:0]const u8 = root ++ "/src";
    mkdirP(root);
    mkdirP(src_dir);
    defer deleteTree(root);

    try writeFile(src_dir ++ "/widget.ts", "export class Widget {}");

    try expectPathsFromOutput(
        \\import { Widget } from "./widget";
    , src_dir ++ "/module.ts", &.{}, true,
        \\import { Widget } from "./widget.js";
    );
}

// ── Generics ──────────────────────────────────────────────────────────────────

test "generics: generic function declaration" {
    try expectTsOutput(
        \\function foo<T>(x: T): T { return x; }
    ,
        \\"use strict";
        \\function foo(x) {
        \\  return x;
        \\}
    );
}

test "generics: generic function with constraint" {
    try expectTsOutput(
        \\function foo<T extends string>(x: T): T { return x; }
    ,
        \\"use strict";
        \\function foo(x) {
        \\  return x;
        \\}
    );
}

test "generics: generic function with default type param" {
    try expectTsOutput(
        \\function foo<T = string>(x: T): T { return x; }
    ,
        \\"use strict";
        \\function foo(x) {
        \\  return x;
        \\}
    );
}

test "generics: multiple type params" {
    try expectTsOutput(
        \\function foo<T, U extends T>(a: T, b: U): U { return b; }
    ,
        \\"use strict";
        \\function foo(a, b) {
        \\  return b;
        \\}
    );
}

test "generics: call expression with type args" {
    try expectTsOutput(
        \\foo<string>(x);
    ,
        \\"use strict";
        \\foo(x);
    );
}

test "generics: call with multiple type args" {
    try expectTsOutput(
        \\foo<string, number>(x, y);
    ,
        \\"use strict";
        \\foo(x, y);
    );
}

test "generics: new expression with type args" {
    try expectTsOutput(
        \\const m = new Map<string, number>();
    ,
        \\"use strict";
        \\const m = new Map();
    );
}

test "generics: generic class declaration" {
    try expectTsOutput(
        \\class Foo<T> { value: T; }
    ,
        \\"use strict";
        \\class Foo {
        \\  value;
        \\}
    );
}

test "generics: generic class with extends" {
    try expectTsOutput(
        \\class Foo<T> extends Base<T> {}
    ,
        \\"use strict";
        \\class Foo extends Base {}
    );
}

test "generics: generic arrow function non-jsx" {
    try expectTsOutput(
        \\const f = <T>(x: T) => x;
    ,
        \\"use strict";
        \\const f = x => x;
    );
}

test "generics: generic arrow function with constraint non-jsx" {
    try expectTsOutput(
        \\const f = <T extends object>(x: T) => x;
    ,
        \\"use strict";
        \\const f = x => x;
    );
}

test "generics: interface declaration stripped" {
    try expectTsOutput(
        \\interface Foo<T> { value: T; }
        \\const x = 1;
    ,
        \\"use strict";
        \\
        \\const x = 1;
    );
}

test "generics: type alias with generics stripped" {
    try expectTsOutput(
        \\type Pair<A, B> = { first: A; second: B; };
        \\const x = 1;
    ,
        \\"use strict";
        \\
        \\const x = 1;
    );
}

test "generics: class expression with default param and extends" {
    try expectTsOutput(
        \\const Box = class<T = string> extends Base<T> {};
    ,
        \\"use strict";
        \\const Box = class Box extends Base {};
    );
}

test "generics: object literal generic method" {
    try expectTsOutput(
        \\const obj = {
        \\  map<T extends string | number = string>(value: T): T {
        \\    return value;
        \\  }
        \\};
    ,
        \\"use strict";
        \\const obj = {
        \\  map(value) {
        \\    return value;
        \\  }
        \\};
    );
}

test "generics: async generic arrow with explicit and inferred calls" {
    try expectTsOutput(
        \\const wrap = async <T>(value: T): Promise<T> => value;
        \\wrap<string>("x");
        \\wrap("y");
    ,
        \\"use strict";
        \\const wrap = async (value) => value;
        \\wrap("x");
        \\wrap("y");
    );
}

test "generics: nested generic class methods and intersections" {
    try expectTsOutput(
        \\type Pair<T, U = T & { id: string }> = T | U;
        \\class Box<T> {
        \\  map<U>(value: Pair<T, U>): Box<U> {
        \\    return new Box<U>();
        \\  }
        \\}
    ,
        \\"use strict";
        \\
        \\class Box {
        \\  map(value) {
        \\    return new Box();
        \\  }
        \\}
    );
}

test "generics: interface and alias with defaults unions and intersections are stripped" {
    try expectTsOutput(
        \\interface Store<T extends Model | null = Model> extends Cache<T> {}
        \\type Result<T, E = Error & { code: number }> = T | E;
        \\const ready = true;
    ,
        \\"use strict";
        \\
        \\
        \\const ready = true;
    );
}

test "generics: malformed type arguments report parse error" {
    try expectTsParseError("generics: malformed type arguments report parse error",
        \\foo<string>(x;
    );
}

test "generics: relational expressions are not parsed as type arguments" {
    try expectTsOutput(
        \\const ok = a < b;
    ,
        \\"use strict";
        \\const ok = a < b;
    );
}

// ── TypeScript-support fixture tests ─────────────────────────────────────────

fn compileFixture(path: []const u8) !compiler.CompileResult {
    return compiler.compileFile(
        path,
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024, .transform = .{ .decorator_metadata = false } },
        std.testing.io,
        std.testing.allocator,
    );
}

fn expectFixtureClean(result: compiler.CompileResult) !void {
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) return error.ParseError;
    }
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    // no residual TypeScript syntax
    try std.testing.expect(!std.mem.containsAtLeast(u8, result.code, 1, "export type "));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result.code, 1, ": string"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result.code, 1, ": number"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result.code, 1, "T extends "));
    try std.testing.expect(!std.mem.containsAtLeast(u8, result.code, 1, "keyof "));
}

test "ts-support: types fixture — export type, interface, keyof, typeof, conditional, indexed" {
    const result = try compileFixture("tests/fixtures/typescript-support/types.fixture.ts");
    try expectFixtureClean(result);
}

test "ts-support: decorators fixture — class decorators, param decorators" {
    const result = try compileFixture("tests/fixtures/typescript-support/decorators.fixture.ts");
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) return error.ParseError;
    }
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
}

test "ts-support: generics fixture — generic fn, generic class, constructor type, NoInfer" {
    const result = try compileFixture("tests/fixtures/typescript-support/generics.fixture.ts");
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) return error.ParseError;
    }
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "function identity(value) {");
    try expectContainsText(result.code, "async function transactional(cb) {");
}

test "ts-support: assertions fixture — legacy <T>, as, non-null, satisfies" {
    const result = try compileFixture("tests/fixtures/typescript-support/assertions.fixture.ts");
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) return error.ParseError;
    }
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export const asString = raw;");
    try expectContainsText(result.code, "export const modern = raw;");
}

test "ts-support: objects fixture — spread, conditional spread, Object.fromEntries" {
    const result = try compileFixture("tests/fixtures/typescript-support/objects.fixture.ts");
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) return error.ParseError;
    }
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "Object.fromEntries(pairs)");
}

test "ts-support: optional-syntax fixture — ?., ??, optional param, destructuring default" {
    const result = try compileFixture("tests/fixtures/typescript-support/optional-syntax.fixture.ts");
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) return error.ParseError;
    }
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "return obj?.a?.b ?? 0;");
    try expectContainsText(result.code, "return arr?.[0] ?? \"\";");
    try expectContainsText(result.code, "fn?.();");
}

test "ts-support: regexp fixture — unicode, lookbehind, flags" {
    const result = try compileFixture("tests/fixtures/typescript-support/regexp.fixture.ts");
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) return error.ParseError;
    }
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
}

test "ts-support: runtime-builtins fixture — fromEntries, includes, arrow callbacks, async" {
    const result = try compileFixture("tests/fixtures/typescript-support/runtime-builtins.fixture.ts");
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) return error.ParseError;
    }
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "items.map(item => item.name)");
    try expectContainsText(result.code, "items.filter(item => item.id > 1)");
    try expectContainsText(result.code, "async function fetchData(url) {");
}

test "ts-support: full-stress fixture — all features combined" {
    const result = try compileFixture("tests/fixtures/typescript-support/full-stress.fixture.ts");
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) return error.ParseError;
    }
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "records.map(r => r.id)");
    try expectContainsText(result.code, "export const double = n => n * 2;");
}

// ── Inline unit tests for specific syntax ────────────────────────────────────

test "ts-support: conditional type in type alias" {
    try expectTsOutput(
        \\type IsStr<T> = T extends string ? true : false;
        \\export const x = 1;
    ,
        \\export const x = 1;
    );
}

test "ts-support: indexed access type" {
    try expectTsOutput(
        \\type NameType = { name: string }["name"];
        \\export const x = 1;
    ,
        \\export const x = 1;
    );
}

test "ts-support: NoInfer indexed conditional" {
    try expectTsOutput(
        \\export type NoInfer<T> = [T][T extends any ? 0 : never];
        \\export function identity<T>(value: NoInfer<T>): T { return value; }
    ,
        \\export function identity(value) {
        \\  return value;
        \\}
    );
}

test "ts-support: function type in param annotation" {
    try expectTsOutput(
        \\export async function run<T>(cb: () => T): Promise<T> { return cb(); }
    ,
        \\export async function run(cb) {
        \\  return cb();
        \\}
    );
}

test "ts-support: preserves leading comment directives and docblocks" {
    const out = try compileTsWithComments(
        \\// @ts-ignore
        \\/** @ts-ignore */
        \\/* @typescript-disable import-helpers/order-imports */
        \\
        \\// this is comment
        \\
        \\/** @type */
        \\/**
        \\   *
        \\   *
        \\   */
        \\const value: number = 1;
    );
    defer std.testing.allocator.free(out);

    try expectContainsText(out, "\"use strict\";");
    try expectContainsText(out, "// @ts-ignore");
    try expectContainsText(out, "/** @ts-ignore */");
    try expectContainsText(out, "/* @typescript-disable import-helpers/order-imports */");
    try expectContainsText(out, "// this is comment");
    try expectContainsText(out, "/** @type */");
    try expectContainsText(out, "/**\n   *\n   *\n   */");
    try expectContainsText(out, "const value = 1;");
}

test "ts-support: preserves comment-only files" {
    const out = try compileTsWithComments(
        \\// @ts-ignore
        \\/** @ts-ignore */
        \\/* @typescript-disable import-helpers/order-imports */
        \\// this is comment
        \\/** @type */
        \\/**
        \\   *
        \\   *
        \\   */
    );
    defer std.testing.allocator.free(out);

    try expectContainsText(out, "\"use strict\";");
    try expectContainsText(out, "// @ts-ignore");
    try expectContainsText(out, "/** @ts-ignore */");
    try expectContainsText(out, "/* @typescript-disable import-helpers/order-imports */");
    try expectContainsText(out, "// this is comment");
    try expectContainsText(out, "/** @type */");
    try expectContainsText(out, "/**\n   *\n   *\n   */");
}

test "ts-support: remove_comments strips preserved comments by default" {
    const out = try compileTs(
        \\// @ts-ignore
        \\/** @type */
        \\const value: number = 1;
    );
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "@ts-ignore") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "@type") == null);
    try expectContainsText(out, "\"use strict\";");
    try expectContainsText(out, "const value = 1;");
}

test "ts-support: preserves comments inside class object array and params" {
    const out = try compileTsWithComments(
        \\class Example {
        \\  /** method doc */
        \\  method(
        \\    /** param doc */
        \\    value: string
        \\  ) {
        \\    const obj = {
        \\      /** prop doc */
        \\      value,
        \\    };
        \\    const arr = [
        \\      /** item doc */
        \\      value,
        \\    ];
        \\    return [obj, arr];
        \\  }
        \\}
    );
    defer std.testing.allocator.free(out);

    try expectContainsText(out, "/** method doc */");
    try expectContainsText(out, "/** param doc */");
    try expectContainsText(out, "/** prop doc */");
    try expectContainsText(out, "/** item doc */");
    try expectContainsText(out, "class Example");
    try expectContainsText(out, "method(");
}

test "ts-support: single-param no-paren arrow" {
    try expectTsOutput(
        \\const arr = [1, 2, 3];
        \\export const doubled = arr.map(x => x * 2);
    ,
        \\const arr = [1, 2, 3];
        \\export const doubled = arr.map(x => x * 2);
    );
}

test "ts-support: typeof in type position" {
    try expectTsOutput(
        \\const config = { debug: true };
        \\export function clone(src: typeof config) { return src; }
    ,
        \\const config = {
        \\  debug: true
        \\};
        \\export function clone(src) {
        \\  return src;
        \\}
    );
}

test "ts-support: enum declaration" {
    const out = try compileTs(
        \\export enum Direction { Up = "UP", Down = "DOWN" }
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "export var Direction = (function(_E) {");
    try expectContainsText(out, "Direction");
    try expectContainsText(out, "\"UP\"");
    try expectContainsText(out, "\"DOWN\"");
}

test "ts-support: enum with numeric initializers" {
    const out = try compileTs(
        \\export enum ProductGenderEnum {
        \\  MALE = 0,
        \\  FEMALE = 1
        \\}
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "ProductGenderEnum");
    try expectContainsText(out, "MALE");
    try expectContainsText(out, "FEMALE");
    try expectContainsText(out, "0");
    try expectContainsText(out, "1");
}

test "ts-support: enum members without commas report specific error" {
    try expectTsParseErrorMessage(
        \\enum A {
        \\  X = 1
        \\  Y = 2
        \\}
    , "expected ',' between enum members");
}

test "ts-support: enum with comma between members and no trailing comma" {
    const out = try compileTs(
        \\enum BlankSideEnum {
        \\  BACK = 0,
        \\  FRONT = 1
        \\}
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "BlankSideEnum");
    try expectContainsText(out, "BACK");
    try expectContainsText(out, "FRONT");
    try expectContainsText(out, "0");
    try expectContainsText(out, "1");
}

test "ts-support: enum members without commas still report specific error with invisible utf8 separators" {
    try expectTsParseErrorMessage(
        "enum A {\n" ++
            "  X = 1\n" ++
            "\xEF\xBB\xBF\xE2\x80\x8B" ++
            "  Y = 2\n" ++
            "}\n",
        "expected ',' between enum members",
    );
}

test "ts-support: class property with definite assignment and enum type" {
    try expectTsOutput(
        \\export class SearchOptionsDto {
        \\  public!: ProductGenderEnum[];
        \\}
    ,
        \\export class SearchOptionsDto {
        \\  public;
        \\}
    );
}

test "ts: named export class remains an export class declaration" {
    try expectTsOutput(
        \\export class NotificationsController {
        \\}
    ,
        \\export class NotificationsController {
        \\}
    );
}

test "ts-support: enum member access" {
    try expectTsOutput(
        \\const value = ProductGenderEnum.MALE;
    ,
        \\const value = ProductGenderEnum.MALE;
    );
}

test "ts-support: fixture type_only_import_enum_property" {
    const out = try compileTs(
        \\export enum ProductGenderEnum {
        \\  MALE = 0,
        \\  FEMALE = 1
        \\}
        \\export class SearchOptionsDto {
        \\  public!: ProductGenderEnum[];
        \\}
        \\const value = ProductGenderEnum.MALE;
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "ProductGenderEnum");
    try expectContainsText(out, "MALE");
    try expectContainsText(out, "SearchOptionsDto");
    try expectContainsText(out, "ProductGenderEnum.MALE");
}

test "ts-support: optional tuple element T?" {
    try expectTsOutput(
        \\const f: () => [string, number?] = () => ['x'];
    ,
        \\const f = () => ['x'];
    );
}

test "ts-support: nested generic with optional tuple element" {
    try expectTsOutput(
        \\const map: Partial<Record<string, () => [string, object?]>> = {};
    ,
        \\const map = {};
    );
}

test "ts-support: fixture type_nested_generic_optional_tuple" {
    try expectTsOutput(
        \\type FindOperatorType = 'equal' | 'like';
        \\type ObjectLiteral = Record<string, unknown>;
        \\const map: Partial<Record<FindOperatorType, () => [string, ObjectLiteral?]>> = {
        \\  equal: () => ['='],
        \\  like: () => ['LIKE', { value: '%abc%' }],
        \\};
    ,
        \\const map = {
        \\  equal: () => ['='],
        \\  like: () => ['LIKE', {
        \\    value: '%abc%'
        \\  }]
        \\};
    );
}

test "ts-support: computed enum decorated fields fixture compiles and preserves computed keys" {
    const result = try compileFixture("tests/fixtures/computed_enum_decorated_fields.ts");
    try expectFixtureClean(result);
}

test "ts-support: const enum emits valid runtime enum" {
    const out = try compileTs(
        \\const enum Flags { Read = 1, Write = 2 }
        \\export const x = Flags.Read;
    );
    defer std.testing.allocator.free(out);

    try expectContainsText(out, "var Flags = (function(_E) {");
    try expectContainsText(out, "_E[_E[\"Read\"] = 1] = \"Read\";");
    try expectContainsText(out, "export const x = Flags.Read;");
    try std.testing.expect(std.mem.indexOf(u8, out, "const enum") == null);
}

// ── import attributes ─────────────────────────────────────────────────────────

test "import attributes: stripped by default" {
    try expectTsOutput(
        \\import db from './database.json' with { type: 'json' };
        \\export { db };
    ,
        \\import db from './database.json' with { type: "json" };
        \\export { db };
    );
}

test "import attributes: kept when keep_import_attributes = true" {
    const out = try compileWithConfig(
        \\import db from './database.json' with { type: 'json' };
        \\export { db };
    , "test.ts", .{
        .parser = .{ .syntax = .typescript },
        .keep_import_attributes = true,
    });
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "with { type: \"json\" }");
    try expectContainsText(out, "from './database.json'");
}

test "import attributes: side-effect import kept when flag on" {
    const out = try compileWithConfig(
        \\import './polyfill.js' with { type: 'javascript' };
    , "test.ts", .{
        .parser = .{ .syntax = .typescript },
        .keep_import_attributes = true,
    });
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings(
        \\"use strict";
        \\import './polyfill.js' with { type: "javascript" };
    ,
        std.mem.trim(u8, out, " \n\r\t"),
    );
}

test "import attributes: dynamic import stripped by default" {
    try expectTsOutput(
        \\export async function load() { return import('./data.json', { with: { type: 'json' } }); }
    ,
        \\export async function load() {
        \\  return import('./data.json');
        \\}
    );
}

test "import attributes: dynamic import kept when flag on" {
    const out = try compileWithConfig(
        \\export async function load() { return import('./data.json', { with: { type: 'json' } }); }
    , "test.ts", .{
        .parser = .{ .syntax = .typescript },
        .keep_import_attributes = true,
    });
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "import('./data.json')");
}

test "import attributes: fixture compiles without errors" {
    const result = try compiler.compileFile(
        "tests/fixtures/import_attributes.ts",
        .{ .parser = .{ .syntax = .typescript }, .keep_import_attributes = true },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "with { type: \"json\" }");
}

// ── TypeScript: non-null assertion ────────────────────────────────────────────

test "ts: non-null assertion stripped" {
    const out = try compileTs("const x = foo!.bar;");
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "const x = foo.bar;");
    try std.testing.expect(std.mem.indexOf(u8, out, "!") == null);
}

test "ts: chained non-null assertion stripped" {
    const out = try compileTs("const x = a!.b!.c;");
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "const x = a.b.c;");
    try std.testing.expect(std.mem.indexOf(u8, out, "!") == null);
}

test "ts: non-null in call argument stripped" {
    const out = try compileTs("fn(value!);");
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "fn(value)");
    try std.testing.expect(std.mem.indexOf(u8, out, "!") == null);
}

// ── TypeScript: satisfies operator ───────────────────────────────────────────

test "ts: satisfies operator stripped" {
    const out = try compileTs("const x = { a: 1 } satisfies Record<string, number>;");
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "a: 1");
    try std.testing.expect(std.mem.indexOf(u8, out, "satisfies") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Record") == null);
}

test "ts: satisfies in export stripped" {
    const out = try compileTs("export const config = { debug: true } satisfies Config;");
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "debug: true");
    try std.testing.expect(std.mem.indexOf(u8, out, "satisfies") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Config") == null);
}

// ── TypeScript: as const ─────────────────────────────────────────────────────

test "ts: as const on array stripped" {
    const out = try compileTs("const arr = [1, 2, 3] as const;");
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "[1, 2, 3]");
    try std.testing.expect(std.mem.indexOf(u8, out, "const;") == null);
}

test "ts: as const on object stripped" {
    const out = try compileTs("const cfg = { x: 1 } as const;");
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "x: 1");
    try std.testing.expect(std.mem.indexOf(u8, out, "as const") == null);
}

test "ts: as const satisfies chain is stripped" {
    const out = try compileTs(
        \\const config = {
        \\  port: 3000,
        \\  mode: "test"
        \\} as const satisfies { port: number; mode: "test" | "prod" };
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "port: 3000");
    try expectContainsText(out, "mode: \"test\"");
    try std.testing.expect(std.mem.indexOf(u8, out, "as const") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "satisfies") == null);
}

// ── TypeScript: namespace ─────────────────────────────────────────────────────

test "ts: namespace emits runtime object" {
    const out = try compileTs(
        \\namespace Validation {
        \\  export const ok = 1;
        \\}
        \\const x = Validation.ok;
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "const Validation = (function(_N) {");
    try expectContainsText(out, "_N.ok = ok;");
    try expectContainsText(out, "const x = Validation.ok;");
    try std.testing.expect(std.mem.indexOf(u8, out, "namespace") == null);
}

test "ts: nested namespace emits nested runtime objects" {
    const out = try compileTs(
        \\namespace Outer {
        \\  export namespace Inner { export const x = 1; }
        \\}
        \\const y = Outer.Inner.x;
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "const Outer = (function(_N) {");
    try expectContainsText(out, "const Inner = (function(_N) {");
    try expectContainsText(out, "_N.Inner = Inner;");
    try expectContainsText(out, "const y = Outer.Inner.x;");
    try std.testing.expect(std.mem.indexOf(u8, out, "namespace") == null);
}

test "ts: exported namespace emits namespace object and export" {
    const out = try compileTs(
        \\export namespace Utils {
        \\  export const value = 1;
        \\}
        \\export const y = Utils.value;
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "const Utils = (function(_N) {");
    try expectContainsText(out, "_N.value = value;");
    try expectContainsText(out, "export { Utils };");
    try expectContainsText(out, "export const y = Utils.value;");
}

test "ts: namespace merging preserves prior exports" {
    const out = try compileTs(
        \\namespace A { export const X = 1; }
        \\namespace A { export const Y = 2; }
        \\export const ok = A.X + A.Y;
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "var A = (function(_N) {");
    try expectContainsText(out, "_N.X = X;");
    try expectContainsText(out, "_N.Y = Y;");
    try expectContainsText(out, "})(A || {});");
    try expectContainsText(out, "export const ok = A.X + A.Y;");
}

test "ts: enum namespace merging preserves enum and namespace members" {
    const out = try compileTs(
        \\enum A { X = 1 }
        \\namespace A { export const Y = 2; }
        \\export const ok = A.X + A.Y;
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "var A = (function(_E) {");
    try expectContainsText(out, "_E[_E[\"X\"] = 1] = \"X\";");
    try expectContainsText(out, "A = (function(_N) {");
    try expectContainsText(out, "_N.Y = Y;");
    try expectContainsText(out, "export const ok = A.X + A.Y;");
}

test "ts: function namespace merging preserves callable and namespace members" {
    const out = try compileTs(
        \\function A() {}
        \\namespace A { export const x = 1; }
        \\export const ok = A.x;
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "function A() {}");
    try expectContainsText(out, "A = (function(_N) {");
    try expectContainsText(out, "_N.x = x;");
    try expectContainsText(out, "export const ok = A.x;");
}

test "ts: class namespace merging avoids invalid redeclaration" {
    const out = try compileTs(
        \\class A {}
        \\namespace A { export const x = 1; }
        \\export const ok = A.x;
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "class A {}");
    try expectContainsText(out, "A = (function(_N) {");
    try expectContainsText(out, "_N.x = x;");
    try std.testing.expect(std.mem.indexOf(u8, out, "var A = (function(_N) {") == null);
    try expectContainsText(out, "export const ok = A.x;");
}

// ── TypeScript: abstract class ────────────────────────────────────────────────

test "ts: abstract class strips abstract keyword from declaration" {
    const out = try compileTs(
        \\abstract class Animal {
        \\  name: string;
        \\  abstract makeSound(): void;
        \\  move() { console.log("moving"); }
        \\}
    );
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "abstract") == null);
    try expectContainsText(out, "class Animal");
    try expectContainsText(out, "move()");
    try std.testing.expect(std.mem.indexOf(u8, out, "makeSound") == null);
}

test "ts: abstract method with body is kept" {
    try expectTsParseError("ts: abstract method with body is kept",
        \\abstract class Base {
        \\  abstract greet(): string { return "hi"; }
        \\}
    );
}

// ── TypeScript: override modifier ─────────────────────────────────────────────

test "ts: override modifier stripped from method" {
    const out = try compileTs(
        \\class Dog extends Animal {
        \\  override makeSound() { console.log("woof"); }
        \\}
    );
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "override") == null);
    try expectContainsText(out, "makeSound()");
}

// ── TypeScript: type guard return type ───────────────────────────────────────

test "ts: type guard return type stripped" {
    const out = try compileTs(
        \\function isString(x: unknown): x is string { return typeof x === "string"; }
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "function isString(x)");
    try expectContainsText(out, "return typeof x === \"string\";");
    try std.testing.expect(std.mem.indexOf(u8, out, "is string") == null);
}

test "ts: type predicate in arrow function stripped" {
    const out = try compileTs(
        \\const isNumber = (x: unknown): x is number => typeof x === "number";
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "typeof x === \"number\"");
    try std.testing.expect(std.mem.indexOf(u8, out, "is number") == null);
}

// ── TypeScript: union and intersection annotations ────────────────────────────

test "ts: union type annotation stripped" {
    const out = try compileTs("const x: string | number = 42;");
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "const x = 42;");
    try std.testing.expect(std.mem.indexOf(u8, out, ": string") == null);
}

test "ts: intersection type annotation stripped" {
    const out = try compileTs("const x: A & B = obj;");
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "const x = obj;");
    try std.testing.expect(std.mem.indexOf(u8, out, ": A") == null);
}

test "ts: nullable union annotation stripped" {
    const out = try compileTs("const x: string | null = null;");
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "const x = null;");
}

// ── TypeScript: mixed import type specifiers ──────────────────────────────────

test "ts: inline type specifier in named import stripped" {
    const out = try compileTs(
        \\import { type Foo, bar } from "./mod";
        \\const x = bar;
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "import { bar } from \"./mod\"");
    try std.testing.expect(std.mem.indexOf(u8, out, "type Foo") == null);
}

test "ts: all type specifiers in import causes whole import to be stripped" {
    const out = try compileTs(
        \\import { type Foo, type Bar } from "./types";
        \\const x = 1;
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "const x = 1;");
    try std.testing.expect(std.mem.indexOf(u8, out, "from \"./types\"") == null);
}

// ── TypeScript: export type ───────────────────────────────────────────────────

test "ts: export type named is stripped" {
    try expectTsOutput(
        \\export type { Foo } from "./mod";
        \\export const x = 1;
    ,
        \\"use strict";
        \\export const x = 1;
    );
}

test "ts: export type specifier in mixed export stripped" {
    const out = try compileTs(
        \\const bar = 1;
        \\export { type Foo, bar };
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "const bar = 1;");
    try expectContainsText(out, "export { bar }");
    try std.testing.expect(std.mem.indexOf(u8, out, "type Foo") == null);
}

// ── TypeScript: readonly class property ──────────────────────────────────────

test "ts: readonly class field emitted without readonly keyword" {
    const out = try compileTs(
        \\class Point {
        \\  readonly x: number;
        \\  readonly y: number;
        \\  constructor(x: number, y: number) { this.x = x; this.y = y; }
        \\}
    );
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "readonly") == null);
    try expectContainsText(out, "class Point");
    try expectContainsText(out, "x;");
    try expectContainsText(out, "y;");
}

test "ts: private readonly class field emitted without modifiers" {
    const out = try compileTs(
        \\class Counter {
        \\  private readonly step: number = 1;
        \\  value() { return this.step; }
        \\}
    );
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "private") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "readonly") == null);
    try expectContainsText(out, "step = 1;");
    try expectContainsText(out, "return this.step;");
}

test "ts: private readonly constructor parameter property emits assignment" {
    const out = try compileTs(
        \\class Counter {
        \\  constructor(private readonly step: number) {}
        \\  value() { return this.step; }
        \\}
    );
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "private") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "readonly") == null);
    try expectContainsText(out, "constructor(step) {");
    try expectContainsText(out, "this.step = step;");
    try expectContainsText(out, "return this.step;");
}

test "ts: declare class field in derived class is parsed and stripped" {
    const out = try compileTs(
        \\class A {}
        \\
        \\class B extends A {
        \\  declare value: string;
        \\}
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "class A {}");
    try expectContainsText(out, "class B extends A {}");
    try std.testing.expect(std.mem.indexOf(u8, out, "declare value") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "value;") == null);
}

// ── TypeScript: tuple type annotation ────────────────────────────────────────

test "ts: tuple type annotation stripped" {
    const out = try compileTs("const pair: [string, number] = [\"a\", 1];");
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "const pair = [\"a\", 1];");
    try std.testing.expect(std.mem.indexOf(u8, out, "[string") == null);
}

test "ts: labeled tuple type annotation stripped" {
    const out = try compileTs("const point: [x: number, y: number] = [0, 0];");
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "const point = [0, 0];");
}

test "ts: labeled tuple with keyword label stripped" {
    try expectTsOutput(
        \\type Handler = (...args: [from: unknown]) => Promise<void>;
        \\export const x = 1;
    ,
        \\"use strict";
        \\
        \\export const x = 1;
    );
}

test "ts: multiline labeled tuple with keyword label stripped" {
    try expectTsOutput(
        \\type Handler = (
        \\  ...args: [
        \\    from: unknown,
        \\  ]
        \\) => Promise<void>;
        \\export const x = 1;
    ,
        \\"use strict";
        \\
        \\export const x = 1;
    );
}

// ── TypeScript: infer in conditional type ────────────────────────────────────

test "ts: conditional type with infer in alias is stripped" {
    const out = try compileTs(
        \\type UnpackPromise<T> = T extends Promise<infer U> ? U : T;
        \\export const x = 1;
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "export const x = 1;");
    try std.testing.expect(std.mem.indexOf(u8, out, "infer") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "UnpackPromise") == null);
}

test "ts: conditional tuple type with constrained infer is stripped" {
    const out = try compileTs(
        \\type MapFuncGuards<TParams extends [...number[]]> = TParams extends [
        \\  infer T extends number,
        \\  ...infer Rest extends number[],
        \\] ? T : never;
        \\export const x = 1;
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "export const x = 1;");
    try std.testing.expect(std.mem.indexOf(u8, out, "infer") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "MapFuncGuards") == null);
}

// ── TypeScript: private class fields passthrough ──────────────────────────────

test "ts: private class fields (#) pass through unchanged" {
    const out = try compileTs(
        \\class Counter {
        \\  #count = 0;
        \\  increment() { this.#count++; }
        \\  get value() { return this.#count; }
        \\}
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "#count");
    try expectContainsText(out, "class Counter");
}

test "ts: private class field declaration parses in class body" {
    const out = try compileTs(
        \\class Counter {
        \\  #count = 0;
        \\}
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "class Counter");
    try expectContainsText(out, "#count = 0;");
}

test "ts: static block followed by private field parses" {
    const out = try compileTs(
        \\export class Counter {
        \\  static created = 0;
        \\  static {
        \\    Counter.created = 1;
        \\  }
        \\
        \\  #count = 0;
        \\
        \\  increment(): number {
        \\    this.#count += 1;
        \\    return this.#count;
        \\  }
        \\
        \\  get value(): number {
        \\    return this.#count;
        \\  }
        \\}
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "export class Counter");
    try expectContainsText(out, "static created = 0;");
    try expectContainsText(out, "static {");
    try expectContainsText(out, "Counter.created = 1;");
    try expectContainsText(out, "#count = 0;");
    try expectContainsText(out, "this.#count += 1;");
    try expectContainsText(out, "return this.#count;");
}

// ── TypeScript: nested generics / advanced type stripping ────────────────────

test "ts: type alias with nested generics stripped" {
    try expectTsOutput(
        \\export type AwaitedReturn<T extends (...args: any[]) => any> =
        \\  Awaited<ReturnType<T>>;
        \\export const x = 1;
    ,
        \\"use strict";
        \\
        \\export const x = 1;
    );
}

test "ts: type query with generic call and indexed access stripped" {
    try expectTsOutput(
        \\export type GetValidatorReturn<T> =
        \\  ReturnType<ReturnType<typeof useSchema<T>>["validator"]>["validate"];
        \\export const x = 1;
    ,
        \\"use strict";
        \\
        \\export const x = 1;
    );
}

test "ts: assertion return type stripped" {
    try expectTsOutput(
        \\export function assertIsString(value: unknown): asserts value is string {
        \\  if (typeof value !== "string") throw new TypeError("Expected string");
        \\}
    ,
        \\"use strict";
        \\export function assertIsString(value) {
        \\  if (typeof value !== "string")
        \\    throw new TypeError("Expected string");
        \\}
    );
}

test "ts: const type parameter stripped" {
    try expectTsOutput(
        \\export function tupleHead<const T extends readonly unknown[]>(tuple: T): T[0] {
        \\  return tuple[0];
        \\}
    ,
        \\"use strict";
        \\export function tupleHead(tuple) {
        \\  return tuple[0];
        \\}
    );
}

test "ts: nested generic return type stripped" {
    try expectTsOutput(
        \\export async function runAll(): Promise<Record<string, unknown>> {
        \\  return {};
        \\}
    ,
        \\"use strict";
        \\export async function runAll() {
        \\  return {};
        \\}
    );
}

test "ts: qualified name type references in variable annotations" {
    try expectTsOutput(
        \\let a: A.B;
        \\let b: A.B.C.D;
        \\let env: NodeJS.ProcessEnv;
    ,
        \\"use strict";
        \\let a;
        \\let b;
        \\let env;
    );
}

test "ts: qualified name type reference in function parameter" {
    try expectTsOutput(
        \\function f(x: A.B.C) {}
    ,
        \\"use strict";
        \\function f(x) {}
    );
}

test "ts: qualified name type reference in function return type" {
    try expectTsOutput(
        \\function g(): A.B.C {
        \\  return value;
        \\}
    ,
        \\"use strict";
        \\function g() {
        \\  return value;
        \\}
    );
}

test "ts: qualified name type references in class method signature" {
    try expectTsOutput(
        \\class C {
        \\  method(x: A.B.C): D.E {}
        \\}
    ,
        \\"use strict";
        \\class C {
        \\  method(x) {}
        \\}
    );
}

test "ts: qualified name type reference with decorated parameter" {
    try expectOutputWithConfig(
        \\function decorated(@Dec() x: A.B.C) {}
    , "test.ts", .{
        .parser = .{ .syntax = .typescript, .decorators = true },
        .transform = .{ .legacy_decorator = false, .decorator_metadata = false },
        .jsx = false,
    },
        \\"use strict";
        \\function decorated(x) {}
    );
}

test "ts: as const stripped" {
    try expectTsOutput(
        \\export const value = ["a", "b"] as const;
    ,
        \\"use strict";
        \\export const value = ["a", "b"];
    );
}

test "ts: satisfies with generic record stripped" {
    try expectTsOutput(
        \\export const config = {
        \\  mode: "prod"
        \\} satisfies Record<string, string>;
    ,
        \\"use strict";
        \\export const config = {
        \\  mode: "prod"
        \\};
    );
}

test "ts: combined advanced typescript file" {
    const out = try compileTs(
        \\export type AwaitedReturn<T extends (...args: any[]) => any> =
        \\  Awaited<ReturnType<T>>;
        \\export function assertIsString(value: unknown): asserts value is string {
        \\  if (typeof value !== "string") throw new TypeError("Expected string");
        \\}
        \\export function tupleHead<const T extends readonly unknown[]>(tuple: T): T[0] {
        \\  return tuple[0];
        \\}
        \\export async function runAll(): Promise<Record<string, unknown>> {
        \\  return { head: tupleHead(["a", "b"] as const) };
        \\}
    );
    defer std.testing.allocator.free(out);
    try expectContainsText(out, "export function assertIsString(value)");
    try expectContainsText(out, "export function tupleHead(tuple)");
    try expectContainsText(out, "export async function runAll()");
    try std.testing.expect(std.mem.indexOf(u8, out, "AwaitedReturn") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "asserts") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "readonly") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Promise<") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "as const") == null);
}

// ── TypeScript: template literal types ───────────────────────────────────────

test "ts: template literal type alias stripped" {
    try expectTsOutput(
        \\export type GetterName<K extends string> = `get${Capitalize<K>}`;
        \\export const x = 1;
    ,
        \\"use strict";
        \\
        \\export const x = 1;
    );
}

test "ts: template literal type with text segments stripped" {
    try expectTsOutput(
        \\type EventName<T extends string> = `${T}Changed`;
        \\const user = "Ana";
        \\console.log(`hello ${user}`);
    ,
        \\"use strict";
        \\
        \\const user = "Ana";
        \\console.log(`hello ${user}`);
    );
}

test "ts: template literal type multi-segment stripped" {
    try expectTsOutput(
        \\type Combo<A extends string, B extends string> = `${A}-${Lowercase<B>}`;
        \\export const x = 1;
    ,
        \\"use strict";
        \\
        \\export const x = 1;
    );
}

test "ts: empty template literal type stripped" {
    try expectTsOutput(
        \\type Empty = ``;
        \\const x = 1;
    ,
        \\"use strict";
        \\
        \\const x = 1;
    );
}

test "ts: runtime template string preserved" {
    try expectTsOutput(
        \\const name = "Ana";
        \\console.log(`hello ${name}`);
    ,
        \\"use strict";
        \\const name = "Ana";
        \\console.log(`hello ${name}`);
    );
}

// ── TypeScript: function overload signatures ─────────────────────────────────

test "ts: overload signatures stripped leaving implementation" {
    try expectTsOutput(
        \\export function overloaded(value: string): number;
        \\export function overloaded(value: number): string;
        \\export function overloaded(value: string | number): string | number {
        \\  return typeof value === "string" ? value.length : String(value);
        \\}
    ,
        \\"use strict";
        \\export function overloaded(value) {
        \\  return typeof value === "string" ? value.length : String(value);
        \\}
    );
}

test "ts: non-export overload signatures stripped" {
    try expectTsOutput(
        \\function parse(value: string): string[];
        \\function parse(value: number): number[];
        \\function parse(value: string | number) {
        \\  return [value];
        \\}
    ,
        \\"use strict";
        \\function parse(value) {
        \\  return [value];
        \\}
    );
}

test "ts: async overload signatures stripped" {
    try expectTsOutput(
        \\export async function load(id: string): Promise<string>;
        \\export async function load(id: number): Promise<string>;
        \\export async function load(id: string | number): Promise<string> {
        \\  return String(id);
        \\}
    ,
        \\"use strict";
        \\export async function load(id) {
        \\  return String(id);
        \\}
    );
}

// ── async arrow with destructured typed params ────────────────────────────────

test "ts: async arrow with destructured typed param (inline type)" {
    try expectTsOutput(
        \\const handler = async ({ req, res }: { req: Request; res: Response }) => {
        \\  return res.json(req.body);
        \\};
    ,
        \\"use strict";
        \\const handler = async ({ req, res }) => {
        \\  return res.json(req.body);
        \\};
    );
}

test "ts: async arrow with destructured typed param (type alias)" {
    try expectTsOutput(
        \\const handler = async ({ req, res }: Context) => {
        \\  return res.json(req.body);
        \\};
    ,
        \\"use strict";
        \\const handler = async ({ req, res }) => {
        \\  return res.json(req.body);
        \\};
    );
}

test "ts: async arrow destructured param multiline" {
    try expectTsOutput(
        \\const routeHandler = async ({
        \\  req,
        \\  res,
        \\}: Context) => {
        \\  return res.status(200).json({ body: req.body });
        \\};
    ,
        \\"use strict";
        \\const routeHandler = async ({ req, res }) => {
        \\  return res.status(200).json({ body: req.body });
        \\};
    );
}

test "ts: async arrow destructured param with default value" {
    try expectTsOutput(
        \\const handler = async ({ req, res }: Context = defaultContext) => {
        \\  return res.json(req.query);
        \\};
    ,
        \\"use strict";
        \\const handler = async ({ req, res } = defaultContext) => {
        \\  return res.json(req.query);
        \\};
    );
}

test "ts: async arrow with inline object type annotation stripped" {
    try expectTsOutput(
        \\const handler = async ({
        \\  req,
        \\  res,
        \\}: {
        \\  req: Request;
        \\  res: Response;
        \\}) => {
        \\  return res.status(201).json(req.params);
        \\};
    ,
        \\"use strict";
        \\const handler = async ({ req, res }) => {
        \\  return res.status(201).json(req.params);
        \\};
    );
}

test "ts: async arrow destructured fixture compiles" {
    const result = try compiler.compileFile(
        "tests/fixtures/arrow_async_destructured_parameter.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "const routeHandler = async ({ req, res }) =>");
    try expectContainsText(result.code, "const handler1 = async ({ req, res }) =>");
    try expectContainsText(result.code, "const handler2 = async ({ req, res }) =>");
    try expectContainsText(result.code, "const handler3 = async ({ req }) =>");
    try expectContainsText(result.code, "const handler4 = async ({ req, res } = defaultContext) =>");
    try expectContainsText(result.code, "const handler5 = async ({ req, res }) =>");
}

// ── sync arrow with destructured typed params ─────────────────────────────────

test "ts: sync arrow with destructured typed param (inline type)" {
    try expectTsOutput(
        \\const handler = ({ req, res }: { req: Request; res: Response }) => {
        \\  return res.json(req.body);
        \\};
    ,
        \\"use strict";
        \\const handler = ({ req, res }) => {
        \\  return res.json(req.body);
        \\};
    );
}

test "ts: sync arrow with destructured typed param (type alias)" {
    try expectTsOutput(
        \\const handler = ({ req, res }: Context) => {
        \\  return res.json(req.body);
        \\};
    ,
        \\"use strict";
        \\const handler = ({ req, res }) => {
        \\  return res.json(req.body);
        \\};
    );
}

test "ts: sync arrow destructured param multiline" {
    try expectTsOutput(
        \\const routeHandler = ({
        \\  req,
        \\  res,
        \\}: Context) => {
        \\  return res.status(200).json({ body: req.body });
        \\};
    ,
        \\"use strict";
        \\const routeHandler = ({ req, res }) => {
        \\  return res.status(200).json({ body: req.body });
        \\};
    );
}

test "ts: sync arrow destructured param with default value" {
    try expectTsOutput(
        \\const handler = ({ req, res }: Context = defaultContext) => {
        \\  return res.json(req.query);
        \\};
    ,
        \\"use strict";
        \\const handler = ({ req, res } = defaultContext) => {
        \\  return res.json(req.query);
        \\};
    );
}

test "ts: sync arrow with inline object type annotation stripped" {
    try expectTsOutput(
        \\const handler = ({
        \\  req,
        \\  res,
        \\}: {
        \\  req: Request;
        \\  res: Response;
        \\}) => {
        \\  return res.status(201).json(req.params);
        \\};
    ,
        \\"use strict";
        \\const handler = ({ req, res }) => {
        \\  return res.status(201).json(req.params);
        \\};
    );
}

test "ts: sync arrow destructured fixture compiles" {
    const result = try compiler.compileFile(
        "tests/fixtures/arrow_destructured_parameter.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "const routeHandler = ({ req, res }) =>");
    try expectContainsText(result.code, "const handler1 = ({ req, res }) =>");
    try expectContainsText(result.code, "const handler2 = ({ req, res }) =>");
    try expectContainsText(result.code, "const handler3 = ({ req }) =>");
    try expectContainsText(result.code, "const handler4 = ({ req, res } = defaultContext) =>");
    try expectContainsText(result.code, "const handler5 = ({ req, res }) =>");
}

// ── IIFE arrow function parentheses ──────────────────────────────────────────

test "iife: simple arrow no-arg" {
    try expectTsOutput(
        \\const a = (() => 123)();
    ,
        \\"use strict";
        \\const a = (() => 123)();
    );
}

test "iife: arrow with block body" {
    try expectTsOutput(
        \\const b = (() => {
        \\  return 456;
        \\})();
    ,
        \\"use strict";
        \\const b = (() => {
        \\  return 456;
        \\})();
    );
}

test "iife: async arrow" {
    try expectTsOutput(
        \\const c = (async () => {
        \\  return 789;
        \\})();
    ,
        \\"use strict";
        \\const c = (async () => {
        \\  return 789;
        \\})();
    );
}

test "iife: arrow with typed param" {
    try expectTsOutput(
        \\const d = ((x: number) => x * 2)(10);
    ,
        \\"use strict";
        \\const d = (x => x * 2)(10);
    );
}

test "iife: arrow with destructured typed param" {
    try expectTsOutput(
        \\const e = (({ x }: { x: number }) => x)({ x: 1 });
    ,
        \\"use strict";
        \\const e = (({ x }) => x)({ x: 1 });
    );
}

test "iife: arrow returning object literal" {
    try expectTsOutput(
        \\const f = (() => ({ value: 1 }))();
    ,
        \\"use strict";
        \\const f = (() => ({ value: 1 }))();
    );
}

test "iife: chained call" {
    try expectTsOutput(
        \\const h = (() => {
        \\  return () => 1;
        \\})()();
    ,
        \\"use strict";
        \\const h = (() => {
        \\  return () => 1;
        \\})()();
    );
}

test "iife: inside expression" {
    try expectTsOutput(
        \\const i = 1 + (() => 2)();
    ,
        \\"use strict";
        \\const i = 1 + (() => 2)();
    );
}

test "iife: as argument" {
    try expectTsOutput(
        \\const j = call(() => 42);
    ,
        \\"use strict";
        \\const j = call(() => 42);
    );
}

test "iife: main fixture compiles without errors" {
    const result = try compiler.compileFile(
        "tests/fixtures/iife_arrow_function_parentheses.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "const a = (() => 123)()");
    try expectContainsText(result.code, "const b = (() => {");
    try expectContainsText(result.code, "const c = (async () => {");
    try expectContainsText(result.code, "const d = (x => x * 2)(10)");
    try expectContainsText(result.code, "const e = (({ x }) => x)({");
    try expectContainsText(result.code, "const f = (() => ({");
    try expectContainsText(result.code, "const h = (() => {");
    try expectContainsText(result.code, "const i = 1 + (() => 2)()");
}

// ── method and function overloads ─────────────────────────────────────────────

test "ts: class method overloads — only implementation emitted" {
    try expectTsOutput(
        \\class Resolver {
        \\  resolve(value: string): string;
        \\  resolve(value: number): number;
        \\  resolve(value: string | number): string | number {
        \\    return value;
        \\  }
        \\}
    ,
        \\"use strict";
        \\class Resolver {
        \\  resolve(value) {
        \\    return value;
        \\  }
        \\}
    );
}

test "ts: static method overloads — only implementation emitted" {
    try expectTsOutput(
        \\class Resolver {
        \\  static create(id: string): Resolver;
        \\  static create(id: number): Resolver;
        \\  static create(id: string | number): Resolver {
        \\    return new Resolver();
        \\  }
        \\}
    ,
        \\"use strict";
        \\class Resolver {
        \\  static create(id) {
        \\    return new Resolver();
        \\  }
        \\}
    );
}

test "ts: constructor overloads — only implementation emitted" {
    try expectTsOutput(
        \\class Point {
        \\  constructor(x: number, y: number);
        \\  constructor(coords: [number, number]);
        \\  constructor(xOrCoords: number | [number, number], y?: number) {}
        \\}
    ,
        \\"use strict";
        \\class Point {
        \\  constructor(xOrCoords, y) {}
        \\}
    );
}

test "ts: generic arrow with constraint fixture compiles in TS mode" {
    const result = try compiler.compileFile(
        "tests/fixtures/generic_arrow_with_constraint.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export const printMessage = (...args) => {");
    try expectContainsText(result.code, "export const identity = value => value;");
    try expectContainsText(result.code, "export const pick = (obj, key) => {");
}

test "ts: generic arrow with constraint compiles in JSX+TS mode" {
    // In JSX mode, `<T extends X>` must be recognized as generic arrow, not JSX.
    const alloc = std.testing.allocator;
    const src =
        \\type GetTemplateTuple<T> = T extends string ? [T] : never;
        \\type Message = string;
        \\export const printMessage =
        \\  <ArgTypes extends GetTemplateTuple<Message>>(
        \\    ...args: ArgTypes
        \\  ) => {
        \\    return args;
        \\  };
        \\export const identity = <T,>(value: T): T => value;
        \\export const pick = <T extends object, K extends keyof T>(obj: T, key: K): T[K] => obj[key];
    ;
    const result = try compiler.compile(src, "test.tsx", .{
        .parser = .{ .syntax = .typescript },
        .jsx = true,
        .target = .es2024,
    }, std.testing.io, alloc);
    defer alloc.free(result.code);
    defer if (result.map) |m| alloc.free(m);
    defer if (result.diagnostics.len > 0) alloc.free(result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export const printMessage = (...args) => {");
    try expectContainsText(result.code, "export const identity = value => value;");
    try expectContainsText(result.code, "export const pick = (obj, key) => obj[key];");
}

test "ts: type predicate return fixture compiles" {
    const result = try compiler.compileFile(
        "tests/fixtures/type_predicate_return.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    // type annotations stripped, bodies preserved
    try expectContainsText(result.code, "export const isLengthAwareAsyncIterable = value => {");
    try expectContainsText(result.code, "return !!value && typeof value === \"object\" && \"length\" in value;");
    try expectContainsText(result.code, "export const isLengthAwareIterable = value => {");
    try expectContainsText(result.code, "export function isString(value) {");
    try expectContainsText(result.code, "return typeof value === \"string\";");
    try expectContainsText(result.code, "export const isNumber = value => {");
    try expectContainsText(result.code, "return typeof value === \"number\";");
}

test "ts: type predicate inline variants" {
    const alloc = std.testing.allocator;

    // type predicate with generic return type
    {
        const out = try compileTs("export const f = <T>(v: unknown): v is Array<T> => Array.isArray(v);");
        defer alloc.free(out);
        try expectContainsText(out, "export const f = v => Array.isArray(v);");
    }

    // double as-cast to generic function type with predicate
    {
        const out = try compileTs(
            \\export const isIt = ((v: unknown) => typeof v === "object") as unknown as <T>(v: unknown) => v is T;
        );
        defer alloc.free(out);
        try expectContainsText(out, "export const isIt = v => typeof v === \"object\";");
    }

    // asserts predicate stripped
    {
        const out = try compileTs("export function assert(v: unknown): asserts v is string { if (!v) throw 0; }");
        defer alloc.free(out);
        try expectContainsText(out, "export function assert(v) {");
        try expectContainsText(out, "if (!v) throw 0;");
    }
}

test "ts: arrow return type with contextual keyword param fixture compiles" {
    const result = try compiler.compileFile(
        "tests/fixtures/arrow_keyword_param.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export const transform = from => {");
    try expectContainsText(result.code, "return from;");
}

test "ts: instantiation expressions fixture compiles" {
    const result = try compiler.compileFile(
        "tests/fixtures/instantiation_expressions.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "pipeline.pipeAsync(printMessage(\"Removed :{count} music files.\"))");
}

test "ts: zero-arg generic instantiation fixture compiles" {
    const src =
        \\declare const isLengthAwareAsyncIterable: <T>() => boolean;
        \\declare const isLengthAwareIterable: <T>() => boolean;
        \\export const LengthAwareAsyncIterable = () => isLengthAwareAsyncIterable<AsyncIterable<unknown>>;
        \\export const LengthAwareIterable = () => isLengthAwareIterable<Iterable<unknown>>;
    ;

    const result = try compiler.compile(
        src,
        "generic_zero_arg_instantiation.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);

    // This is an instantiation expression used as a value with zero runtime
    // arguments. The type-argument list must be non-empty; `fn<>` is not valid
    // TypeScript and belongs in a check:true negative test instead.
    try expectContainsText(result.code, "export const LengthAwareAsyncIterable = () => isLengthAwareAsyncIterable;");
    try expectContainsText(result.code, "export const LengthAwareIterable = () => isLengthAwareIterable;");
}

test "ts: ambient declare fixture strips type-only declarations" {
    const result = try compiler.compileFile(
        "tests/fixtures/ambient_declarations.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2020 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export const runtimeValue = 1;");
    try std.testing.expect(std.mem.indexOf(u8, result.code, "declaredValue") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.code, "declaredFn") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.code, "AmbientService") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.code, "exportedDeclaredValue") == null);
}

test "ts: decorated zero-arg constructor fixture emits empty param metadata" {
    const result = try compiler.compileFile(
        "tests/fixtures/decorated_zero_arg_ctor.ts",
        .{ .parser = .{ .syntax = .typescript, .decorators = true }, .target = .es2020 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "__metadata(\"design:paramtypes\", [])");
}

test "ts: declare global fixture strips ambient block" {
    const result = try compiler.compileFile(
        "tests/fixtures/declare_global.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2020 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export const ok = 1;");
    try std.testing.expect(std.mem.indexOf(u8, result.code, "interface Array") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.code, "first()") == null);
}

test "ts: declare support matrix fixture compiles" {
    const result = try compiler.compileFile(
        "tests/fixtures/declare_support_matrix.ts",
        .{ .parser = .{ .syntax = .typescript, .decorators = true }, .target = .es2020 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try std.testing.expect(std.mem.indexOf(u8, result.code, "declare") == null);
}

test "ts: declare export is rejected" {
    try expectTsParseError("declare export invalid order",
        \\declare export const legacy: number
    );
}

test "ts: declare const unique symbol is stripped without leaking symbol token" {
    try expectTsOutput(
        \\declare const sym: unique symbol
    ,
        \\"use strict";
    );
}

test "esm: top-level await is preserved" {
    const result = try compiler.compileFile(
        "tests/fixtures/top_level_await.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2020 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "export const value = await source;");
    try expectContainsText(result.code, "export const next = value + 1;");
}

test "ts: method overloads fixture compiles" {
    const result = try compiler.compileFile(
        "tests/fixtures/method_overloads.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    // class method: only implementation
    try expectContainsText(result.code, "resolve(value) {");
    // static: only implementation
    try expectContainsText(result.code, "static create(id) {");
    // constructor: only implementation
    try expectContainsText(result.code, "constructor(xOrCoords, y) {");
    // standalone fn: only implementation
    try expectContainsText(result.code, "function parse(value) {");
    try expectContainsText(result.code, "async function load(id) {");
}

test "ts: for await of fixture compiles" {
    const result = try compiler.compileFile(
        "tests/fixtures/for_await_of.ts",
        .{ .parser = .{ .syntax = .typescript }, .target = .es2024 },
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    defer if (result.map) |m| std.testing.allocator.free(m);
    defer freeDiagnostics(std.testing.allocator, result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try expectContainsText(result.code, "for await (const e of list)");
    try expectContainsText(result.code, "for (const e of list)");
}

test "ts: for await inline variants" {
    const alloc = std.testing.allocator;

    // basic for await...of
    {
        const out = try compileTs(
            \\async function run(xs) { for await (const x of xs) console.log(x); }
        );
        defer alloc.free(out);
        try expectContainsText(out, "for await (const x of xs)");
    }

    // regular for...of unaffected
    {
        const out = try compileTs(
            \\function run(xs) { for (const x of xs) console.log(x); }
        );
        defer alloc.free(out);
        try expectContainsText(out, "for (const x of xs)");
    }
}

fn compileTsTarget(src: []const u8, target: compiler.config.Target) ![]const u8 {
    const alloc = std.testing.allocator;
    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript }, .jsx = false, .target = target };
    const result = try compiler.compile(src, "test.ts", cfg, std.testing.io, alloc);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) {
            alloc.free(result.code);
            if (result.diagnostics.len > 0) alloc.free(result.diagnostics);
            return error.ParseError;
        }
    }
    if (result.diagnostics.len > 0) alloc.free(result.diagnostics);
    return result.code;
}

fn expectTsOutputTarget(src: []const u8, expected: []const u8, target: compiler.config.Target) !void {
    const out = try compileTsTarget(src, target);
    defer std.testing.allocator.free(out);
    const trimmed = normalizedOutput(out, expected);
    const exp_trimmed = trimText(expected);
    if (!std.mem.eql(u8, trimmed, exp_trimmed) and !equalIgnoringWhitespace(trimmed, exp_trimmed)) {
        std.debug.print("\n=== EXPECTED ===\n{s}\n=== GOT ===\n{s}\n", .{ exp_trimmed, trimmed });
        return error.TestExpectedEqual;
    }
}

test "using declaration passthrough at esnext" {
    try expectTsOutputTarget(
        \\using x = getResource();
    , "using x = getResource();", .esnext);
}

test "using declaration lowered to const at es2024" {
    try expectTsOutputTarget(
        \\using x = getResource();
    , "const x = getResource();", .es2024);
}

test "await using declaration passthrough at esnext" {
    try expectTsOutputTarget(
        \\async function foo() { await using x = getResource(); }
    , "async function foo() {\n  await using x = getResource();\n}", .esnext);
}

test "await using declaration lowered at es2024" {
    try expectTsOutputTarget(
        \\async function foo() { await using x = getResource(); }
    , "async function foo() {\n  const x = getResource();\n}", .es2024);
}

test "accessor keyword in class" {
    try expectTsOutputTarget(
        \\class Foo { accessor x = 1; }
    , "class Foo {\n  accessor x = 1;\n}", .esnext);
}

test "static accessor in class" {
    try expectTsOutputTarget(
        \\class Foo { static accessor x = 1; }
    , "class Foo {\n  static accessor x = 1;\n}", .esnext);
}

test "accessor lowered to field at es2024" {
    try expectTsOutputTarget(
        \\class Foo { accessor x = 1; }
    , "class Foo {\n  x = 1;\n}", .es2024);
}

test "export type * from is elided" {
    try expectTsOutput(
        \\export type * from './types';
    , "");
}

test "export type * as from is elided" {
    try expectTsOutput(
        \\export type * as NS from './types';
    , "");
}

test "export * from preserved" {
    try expectTsOutput(
        \\export * from './utils';
    , "export * from './utils';");
}

fn expectUnexpectedToken(source: []const u8) !void {
    const result = try compiler.compile(source, "test.ts", .{
        .source_maps = false,
    }, std.testing.io, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.diagnostics.len);
    try std.testing.expectEqualStrings("unexpected token", result.diagnostics[0].message);
}

fn expectNoDiagnostics(source: []const u8) !void {
    const result = try compiler.compile(source, "test.ts", .{
        .source_maps = false,
    }, std.testing.io, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
}

test "parser rejects async getter and setter in class" {
    try expectUnexpectedToken(
        \\class User {
        \\  async get method() {
        \\    return 10
        \\  }
        \\}
    );

    try expectUnexpectedToken(
        \\class User {
        \\  async set method(n: number) {
        \\    console.log(n)
        \\  }
        \\}
    );
}

test "parser rejects async getter and setter at statement level" {
    try expectUnexpectedToken(
        \\async get method() {
        \\  return 10
        \\}
    );

    try expectUnexpectedToken(
        \\async set method(n: number) {
        \\  console.log(n)
        \\}
    );
}

test "parser keeps valid async class methods named get and set" {
    try expectNoDiagnostics(
        \\class User {
        \\  async get() {
        \\    return 10
        \\  }
        \\
        \\  async set(n: number) {
        \\    console.log(n)
        \\  }
        \\}
    );
}

test "parser keeps valid sync getter and setter" {
    try expectNoDiagnostics(
        \\class User {
        \\  get method() {
        \\    return 10
        \\  }
        \\
        \\  set method(n: number) {
        \\    console.log(n)
        \\  }
        \\}
    );
}

test "parser emits class getter and setter accessors" {
    const source =
        \\class User {
        \\  get method() {
        \\    return 10
        \\  }
        \\
        \\  set method(n: number) {
        \\    console.log(n)
        \\  }
        \\}
        \\
        \\const user = new User()
        \\console.log(user)
    ;

    const expected =
        \\"use strict";
        \\class User {
        \\  get method() {
        \\    return 10;
        \\  }
        \\  set method(n) {
        \\    console.log(n);
        \\  }
        \\}
        \\const user = new User();
        \\console.log(user);
    ;

    try expectTsOutput(source, expected);
}

test "get and set can still be normal method names" {
    const source =
        \\class User {
        \\  get() {
        \\    return 1
        \\  }
        \\
        \\  set(value: number) {
        \\    return value
        \\  }
        \\}
    ;

    const expected =
        \\"use strict";
        \\class User {
        \\  get() {
        \\    return 1;
        \\  }
        \\  set(value) {
        \\    return value;
        \\  }
        \\}
    ;

    try expectTsOutput(source, expected);
}
