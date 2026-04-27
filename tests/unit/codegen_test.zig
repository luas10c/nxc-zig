const std = @import("std");

const ast = @import("ast");
const diagnostics = @import("diagnostics");
const parser = @import("parser");
const codegen = @import("codegen");
const compiler = @import("compiler");
const config = @import("config");

const Parser = parser.Parser;
const Codegen = codegen.Codegen;
const Config = config.Config;

fn freeDiagnostics(alloc: std.mem.Allocator, diags: []const diagnostics.Diagnostic) void {
    for (diags) |d| {
        alloc.free(d.message);
        alloc.free(d.filename);
        if (d.source_line) |line| alloc.free(line);
    }
    alloc.free(diags);
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

fn expectCodegen(src: []const u8, expected: []const u8) !void {
    var backing = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer backing.deinit();

    const alloc = backing.allocator();
    var arena = ast.Arena.init(alloc);
    defer arena.deinit();

    var diags = diagnostics.DiagnosticList{};
    defer diags.items.deinit(alloc);

    var p = Parser.init(src, "test.ts", &arena, alloc, &diags, .{ .typescript = true });
    const program = try p.parseProgram();
    try std.testing.expect(!diags.hasErrors());

    var cg = try Codegen.init(&arena, alloc, .{ .pretty = true });
    try cg.gen(program);
    const out = try cg.finish();
    defer alloc.free(out);
    try std.testing.expectEqualStrings(expected, out);
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

fn expectOutputWithConfig(src: []const u8, expected: []const u8, cfg_patch: Config) !void {
    var cfg = cfg_patch;
    cfg.source_maps = false;

    var result = try compiler.compile(src, "src/main.ts", cfg, undefined, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try std.testing.expectEqualStrings(expected, result.code);
}

fn expectTsErrorWithConfig(src: []const u8, cfg_patch: Config) !void {
    var cfg = cfg_patch;
    cfg.source_maps = false;

    var result = try compiler.compile(src, "src/main.ts", cfg, undefined, std.testing.allocator);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(result.diagnostics.len > 0);
}

fn expectContainsText(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) return;
    std.debug.print("expected to find '{s}' in text\n", .{needle});
    return error.TestExpectedEqual;
}

test "codegen supports object generator and async generator methods" {
    try expectCodegen(
        \\const obj = {
        \\  async* aaa(): AsyncGenerator {
        \\    yield true;
        \\  },
        \\  *aaaa(): Generator {
        \\    yield false;
        \\  }
        \\};
    ,
        \\const obj = {
        \\  async *aaa() {
        \\    yield true;
        \\  },
        \\  *aaaa() {
        \\    yield false;
        \\  }
        \\};
    );
}

test "codegen supports class generator and async generator methods" {
    try expectCodegen(
        \\class Example {
        \\  async* aaa(): AsyncGenerator {
        \\    yield true;
        \\  }
        \\  *aaaa(): Generator {
        \\    yield false;
        \\  }
        \\}
    ,
        \\class Example {
        \\  async *aaa() {
        \\    yield true;
        \\  }
        \\  *aaaa() {
        \\    yield false;
        \\  }
        \\}
    );
}

test "codegen supports async computed object methods" {
    try expectCodegen(
        \\const obj = {
        \\  async [Symbol.asyncDispose]() {
        \\    await cleanup();
        \\  }
        \\};
    ,
        \\const obj = {
        \\  async [Symbol.asyncDispose]() {
        \\    await cleanup();
        \\  }
        \\};
    );
}

test "codegen supports async computed class methods" {
    try expectCodegen(
        \\class Resource {
        \\  async [Symbol.asyncDispose]() {
        \\    await cleanup();
        \\  }
        \\}
    ,
        \\class Resource {
        \\  async [Symbol.asyncDispose]() {
        \\    await cleanup();
        \\  }
        \\}
    );
}

test "module syntax: deferred namespace import" {
    try expectTsOutput(
        \\import defer * as deferredFeature from "./expensive-feature.js";
        \\export { deferredFeature };
    ,
        \\import defer * as deferredFeature from "./expensive-feature.js";
        \\export { deferredFeature };
    );
}

test "module syntax: export all with attributes" {
    const out = try compileWithConfig(
        \\export * from "./runtime-module" with { type: "javascript" };
    , "test.ts", .{
        .parser = .{ .syntax = .typescript },
        .keep_import_attributes = true,
    });
    defer std.testing.allocator.free(out);

    try expectContainsText(out, "export * from \"./runtime-module\" with { type: \"javascript\" };");
}

test "object literal: getter and setter" {
    try expectTsOutput(
        \\const objectAccessor = {
        \\  _value: 1,
        \\
        \\  get value() {
        \\    return this._value;
        \\  },
        \\
        \\  set value(next: number) {
        \\    this._value = next;
        \\  },
        \\};
    ,
        \\const objectAccessor = {
        \\  _value: 1,
        \\  get value() {
        \\    return this._value;
        \\  },
        \\  set value(next) {
        \\    this._value = next;
        \\  }
        \\};
    );
}

test "typescript: type query dynamic import" {
    try expectTsOutput(
        \\type DynamicModulePromise = Promise<typeof import("./dynamic-module-2")>;
        \\const ok = true;
    ,
        \\const ok = true;
    );
}

test "class syntax: parenthesized extends expression" {
    try expectTsOutput(
        \\class BaseExpression {}
        \\
        \\class DerivedFromExpression extends (BaseExpression) {
        \\  derived = true;
        \\}
    ,
        \\class BaseExpression {}
        \\class DerivedFromExpression extends BaseExpression {
        \\  derived = true;
        \\}
    );
}

test "class syntax: parenthesized conditional extends expression" {
    try expectTsOutput(
        \\class BaseExpression {}
        \\class Entity {}
        \\const aaaa = true;
        \\class DerivedFromExpression extends (aaaa ? BaseExpression : Entity) {
        \\  derived = true;
        \\}
    ,
        \\class BaseExpression {}
        \\class Entity {}
        \\const aaaa = true;
        \\class DerivedFromExpression extends (aaaa ? BaseExpression : Entity) {
        \\  derived = true;
        \\}
    );
}

test "destructuring: array pattern with default assignment" {
    try expectTsOutput(
        \\const [start, end, inclusive = false] = range;
        \\const [, secondHoleDefault = "missing"] = sparseArray;
    ,
        \\const [start, end, inclusive = false] = range;
        \\const [, secondHoleDefault = "missing"] = sparseArray;
    );
}

test "destructuring: nested object and array pattern with defaults" {
    try expectTsOutput(
        \\const {
        \\  a: {
        \\    b: [firstItem, , thirdItem = 99],
        \\  },
        \\  ...remainingObject
        \\} = complexObject;
    ,
        \\const { a: { b: [firstItem, , thirdItem = 99] }, ...remainingObject } = complexObject;
    );
}

test "destructuring: object shorthand default assignment" {
    try expectTsOutput(
        \\const { truphy = true } = {};
    ,
        \\const { truphy = true } = {};
    );
}

test "typescript: private identifier in expression" {
    try expectTsOutput(
        \\class PrivateCheck {
        \\  #secret = 1;
        \\
        \\  static hasSecret(value: unknown): value is PrivateCheck {
        \\    return typeof value === "object" && value !== null && #secret in value;
        \\  }
        \\}
    ,
        \\class PrivateCheck {
        \\  #secret = 1;
        \\  static hasSecret(value) {
        \\    return typeof value === "object" && value !== null && #secret in value;
        \\  }
        \\}
    );
}

test "module syntax: import assertions emitted for target es2022" {
    try expectOutputWithConfig(
        \\"use strict";
        \\import jsonData from "./fixture.json" assert { type: "json" };
        \\console.log(jsonData);
    ,
        \\"use strict";
        \\import jsonData from "./fixture.json" assert { type: "json" };
        \\console.log(jsonData);
    ,
        .{ .target = .es2022 },
    );
}

test "module syntax: import attributes emitted for target esnext" {
    try expectOutputWithConfig(
        \\"use strict";
        \\import jsonData from "./fixture.json" with { type: "json" };
        \\console.log(jsonData);
    ,
        \\"use strict";
        \\import jsonData from "./fixture.json" with { type: "json" };
        \\console.log(jsonData);
    ,
        .{ .target = .esnext },
    );
}

test "module syntax: assert rejected for target es2024" {
    try expectTsErrorWithConfig(
        \\import jsonData from "./fixture.json" assert { type: "json" };
    ,
        .{ .target = .es2024 },
    );
}

test "module syntax: with rejected before target es2024" {
    try expectTsErrorWithConfig(
        \\import jsonData from "./fixture.json" with { type: "json" };
    ,
        .{ .target = .es2022 },
    );
}

test "module syntax: export attributes follow target" {
    try expectOutputWithConfig(
        \\"use strict";
        \\export { default as data } from "./fixture.json" with { type: "json" };
    ,
        \\"use strict";
        \\export { default as data } from "./fixture.json" with { type: "json" };
    ,
        .{ .target = .es2024 },
    );
}

test "module syntax: duplicate default import binding with attributes" {
    try expectTsErrorWithConfig(
        \\import jsonData from "./fixture.json" with { type: "json" };
        \\import jsonData from "./fixture.json" with { type: "json" };
    ,
        .{ .target = .es2024, .keep_import_attributes = true },
    );
}

test "module syntax: duplicate import binding across import forms" {
    try expectTsErrorWithConfig(
        \\import jsonData from "./fixture.json" with { type: "json" };
        \\import { default as jsonData } from "./fixture.json" with { type: "json" };
    ,
        .{ .target = .es2024, .keep_import_attributes = true },
    );
}

test "module syntax: duplicate namespace import binding" {
    try expectTsErrorWithConfig(
        \\import * as jsonData from "./a.js";
        \\import * as jsonData from "./b.js";
    ,
        .{ .target = .es2024 },
    );
}

test "module syntax: preserve unused import with attributes" {
    try expectOutputWithConfig(
        \\import jsonData from "./fixture.json" with { type: "json" };
    ,
        \\"use strict";
        \\import jsonData from "./fixture.json" with { type: "json" };
    ,
        .{ .target = .es2024, .keep_import_attributes = true },
    );
}
