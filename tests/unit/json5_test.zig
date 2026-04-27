const std = @import("std");

const json5 = @import("json5");

const alloc = std.testing.allocator;

fn sanitizeEql(input: []const u8, expected: []const u8) !void {
    const got = try json5.sanitize(input, alloc);
    defer alloc.free(got);
    try std.testing.expectEqualStrings(expected, got);
}

fn parseStr(input: []const u8, key: []const u8) ![]const u8 {
    const p = try json5.parse(input, alloc);
    defer p.deinit();
    const v = p.value.object.get(key) orelse return error.KeyNotFound;
    if (v != .string) return error.NotString;
    // dupe because parsed value is freed on p.deinit()
    return alloc.dupe(u8, v.string);
}

fn parseFloat(input: []const u8, key: []const u8) !f64 {
    const p = try json5.parse(input, alloc);
    defer p.deinit();
    const v = p.value.object.get(key) orelse return error.KeyNotFound;
    return switch (v) {
        .float => |f| f,
        .integer => |n| @floatFromInt(n),
        .number_string => |s| std.fmt.parseFloat(f64, s) catch return error.NotNumber,
        // NaN/Infinity map to null (unrepresentable in JSON)
        .null => std.math.nan(f64),
        else => error.NotNumber,
    };
}

// ── 1. Line comments ─────────────────────────────────────────────────────────

test "1: line comment stripped" {
    // space before // is preserved (whitespace is not part of the comment)
    try sanitizeEql("// comment\n{\"a\":1}", "{\"a\":1}");
}

test "1: line comment mid-object" {
    const p = try json5.parse(
        \\{
        \\ // this is a comment
        \\ "x": 42
        \\}
    , alloc);
    defer p.deinit();
    try std.testing.expectEqual(@as(i64, 42), p.value.object.get("x").?.integer);
}

// ── 2. Block comments ────────────────────────────────────────────────────────

test "2: block comment stripped" {
    try sanitizeEql(
        \\{"a":/* hello */1}
    ,
        \\{"a":1}
    );
}

test "2: multiline block comment" {
    const p = try json5.parse(
        \\{ /* line1
        \\     line2 */ "x": 7 }
    , alloc);
    defer p.deinit();
    try std.testing.expectEqual(@as(i64, 7), p.value.object.get("x").?.integer);
}

// ── 3. Unquoted object keys ───────────────────────────────────────────────────

test "3: unquoted key" {
    const p = try json5.parse("{foo: 1}", alloc);
    defer p.deinit();
    try std.testing.expectEqual(@as(i64, 1), p.value.object.get("foo").?.integer);
}

test "3: unquoted key with underscore and dollar" {
    const p = try json5.parse("{_bar$: true}", alloc);
    defer p.deinit();
    try std.testing.expect(p.value.object.get("_bar$").?.bool);
}

// ── 4. Trailing comma in objects ─────────────────────────────────────────────

test "4: trailing comma object" {
    const p = try json5.parse(
        \\{"a": 1, "b": 2,}
    , alloc);
    defer p.deinit();
    try std.testing.expectEqual(@as(i64, 2), p.value.object.get("b").?.integer);
}

// ── 5. Trailing comma in arrays ──────────────────────────────────────────────

test "5: trailing comma array" {
    const p = try json5.parse(
        \\{"arr": [1, 2, 3,]}
    , alloc);
    defer p.deinit();
    try std.testing.expectEqual(@as(usize, 3), p.value.object.get("arr").?.array.items.len);
}

// ── 6. Single-quoted strings ─────────────────────────────────────────────────

test "6: single-quoted value" {
    const s = try parseStr("{'k': 'hello'}", "k");
    defer alloc.free(s);
    try std.testing.expectEqualStrings("hello", s);
}

test "6: single-quoted key and value" {
    const p = try json5.parse("{'key': 'val'}", alloc);
    defer p.deinit();
    const v = p.value.object.get("key") orelse return error.KeyNotFound;
    try std.testing.expectEqualStrings("val", v.string);
}

test "6: escaped single quote inside single-quoted string" {
    // 'it\'s' → "it's"
    const p = try json5.parse("{\"k\": 'it\\'s'}", alloc);
    defer p.deinit();
    try std.testing.expectEqualStrings("it's", p.value.object.get("k").?.string);
}

test "6: double quote inside single-quoted string" {
    // '{"nested"}' → "{\"nested\"}"
    const p = try json5.parse("{\"k\": 'say \"hi\"'}", alloc);
    defer p.deinit();
    try std.testing.expectEqualStrings("say \"hi\"", p.value.object.get("k").?.string);
}

// ── 7. Multiline strings with backslash-newline ───────────────────────────────

test "7: backslash-newline continuation in double-quoted string" {
    // "hello \<newline>world" → "hello world" in JSON5
    // sanitizer must strip the \ + \n pair
    const p = try json5.parse("{\"k\": \"hello \\\nworld\"}", alloc);
    defer p.deinit();
    try std.testing.expectEqualStrings("hello world", p.value.object.get("k").?.string);
}

test "7: backslash-newline continuation in single-quoted string" {
    const p = try json5.parse("{\"k\": 'hello \\\nworld'}", alloc);
    defer p.deinit();
    try std.testing.expectEqualStrings("hello world", p.value.object.get("k").?.string);
}

// ── 8. Extra string escapes ───────────────────────────────────────────────────

test "8: \\v escape in string" {
    // JSON5 allows \v (vertical tab, 0x0B); JSON does not
    const p = try json5.parse("{\"k\": \"a\\vb\"}", alloc);
    defer p.deinit();
    // result should be "a" + 0x0B + "b"
    try std.testing.expectEqual(@as(usize, 3), p.value.object.get("k").?.string.len);
}

test "8: \\0 null escape in string" {
    const p = try json5.parse("{\"k\": \"a\\0b\"}", alloc);
    defer p.deinit();
    try std.testing.expectEqual(@as(usize, 3), p.value.object.get("k").?.string.len);
}

// ── 9. Numbers with + sign ────────────────────────────────────────────────────

test "9: +1 positive number" {
    const f = try parseFloat("{\"n\": +1}", "n");
    try std.testing.expectEqual(@as(f64, 1.0), f);
}

test "9: +3.14 positive float" {
    const f = try parseFloat("{\"n\": +3.14}", "n");
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), f, 1e-9);
}

// ── 10. Numbers starting with decimal point ───────────────────────────────────

test "10: .5 leading decimal" {
    const f = try parseFloat("{\"n\": .5}", "n");
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), f, 1e-9);
}

test "10: -.5 negative leading decimal" {
    const f = try parseFloat("{\"n\": -.5}", "n");
    try std.testing.expectApproxEqAbs(@as(f64, -0.5), f, 1e-9);
}

// ── 11. Numbers ending with decimal point ─────────────────────────────────────

test "11: 1. trailing decimal" {
    const f = try parseFloat("{\"n\": 1.}", "n");
    try std.testing.expectEqual(@as(f64, 1.0), f);
}

test "11: -1. negative trailing decimal" {
    const f = try parseFloat("{\"n\": -1.}", "n");
    try std.testing.expectEqual(@as(f64, -1.0), f);
}

// ── 12. Hexadecimal numbers ───────────────────────────────────────────────────

test "12: 0xFF hex" {
    const f = try parseFloat("{\"n\": 0xFF}", "n");
    try std.testing.expectEqual(@as(f64, 255.0), f);
}

test "12: 0x1A2B hex lowercase" {
    const f = try parseFloat("{\"n\": 0x1a2b}", "n");
    try std.testing.expectEqual(@as(f64, 0x1a2b), f);
}

// ── 13. Infinity ──────────────────────────────────────────────────────────────

test "13: Infinity" {
    const f = try parseFloat("{\"n\": Infinity}", "n");
    try std.testing.expect(std.math.isInf(f) and f > 0);
}

// ── 14. +Infinity ─────────────────────────────────────────────────────────────

test "14: +Infinity" {
    const f = try parseFloat("{\"n\": +Infinity}", "n");
    try std.testing.expect(std.math.isInf(f) and f > 0);
}

// ── 15. -Infinity ─────────────────────────────────────────────────────────────

test "15: -Infinity" {
    const f = try parseFloat("{\"n\": -Infinity}", "n");
    try std.testing.expect(std.math.isInf(f) and f < 0);
}

// ── 16. NaN ───────────────────────────────────────────────────────────────────

test "16: NaN" {
    const f = try parseFloat("{\"n\": NaN}", "n");
    try std.testing.expect(std.math.isNan(f));
}

// ── 17. +NaN ──────────────────────────────────────────────────────────────────

test "17: +NaN" {
    const f = try parseFloat("{\"n\": +NaN}", "n");
    try std.testing.expect(std.math.isNan(f));
}

// ── 18. -NaN ──────────────────────────────────────────────────────────────────

test "18: -NaN" {
    const f = try parseFloat("{\"n\": -NaN}", "n");
    try std.testing.expect(std.math.isNan(f));
}

// ── 19. Unicode whitespace ────────────────────────────────────────────────────

test "19: NBSP (0xA0) as whitespace" {
    // U+00A0 in UTF-8 is 0xC2 0xA0
    const input = "{\"k\":\xC2\xA01}";
    const p = try json5.parse(input, alloc);
    defer p.deinit();
    try std.testing.expectEqual(@as(i64, 1), p.value.object.get("k").?.integer);
}

test "19: LINE SEPARATOR (U+2028) as whitespace" {
    // U+2028 in UTF-8 is 0xE2 0x80 0xA8
    const input = "{\"k\":\xE2\x80\xA81}";
    const p = try json5.parse(input, alloc);
    defer p.deinit();
    try std.testing.expectEqual(@as(i64, 1), p.value.object.get("k").?.integer);
}

test "19: PARAGRAPH SEPARATOR (U+2029) as whitespace" {
    // U+2029 in UTF-8 is 0xE2 0x80 0xA9
    const input = "{\"k\":\xE2\x80\xA91}";
    const p = try json5.parse(input, alloc);
    defer p.deinit();
    try std.testing.expectEqual(@as(i64, 1), p.value.object.get("k").?.integer);
}
