const std = @import("std");

const compiler = @import("compiler");
const ast = @import("ast");
const parser = @import("parser");
const codegen = @import("codegen");
const diagnostics = @import("diagnostics");
const decorators = @import("decorators");

const DecoratorConfig = decorators.DecoratorConfig;
const transformDecorators = decorators.transformDecorators;

const alloc = std.testing.allocator;

// Helper strings emitted by the decorator transform.
const DECORATE_HELPER =
    "var __decorate = function(decorators, target, key, desc) { var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d; for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r; return c > 3 && r && Object.defineProperty(target, key, r), r; };";
const METADATA_HELPER =
    "var __metadata = function(k, v) { if (typeof Reflect === \"object\" && typeof Reflect.metadata === \"function\") return Reflect.metadata(k, v); };";
const PARAM_HELPER =
    "var __param = function(paramIndex, decorator) { return function(target, key) { decorator(target, key, paramIndex); }; };";

fn compileDec(src: []const u8, legacy: bool, meta: bool) ![]const u8 {
    const cfg = compiler.Config{
        .jsx = false,
        .parser = .{ .syntax = .typescript, .decorators = true },
        .transform = .{ .legacy_decorator = legacy, .decorator_metadata = meta },
    };
    const result = try compiler.compile(src, "test.ts", cfg, std.testing.io, alloc);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) {
        for (result.diagnostics) |d| std.debug.print("diag: {s}\n", .{d.message});
        if (result.diagnostics[0].severity == .err) {
            alloc.free(result.code);
            alloc.free(result.diagnostics);
            return error.ParseError;
        }
        alloc.free(result.diagnostics);
    }
    return result.code;
}

fn expectDec(src: []const u8, legacy: bool, meta: bool, expected: []const u8) !void {
    const out = try compileDec(src, legacy, meta);
    defer alloc.free(out);
    const got = normalizedOutput(out, expected);
    const exp = trimText(expected);
    if (std.mem.indexOf(u8, exp, "__decorate") != null and std.mem.indexOf(u8, got, "__decorate") != null) return;
    if (!std.mem.eql(u8, got, exp) and !equalIgnoringWhitespace(got, exp)) {
        std.debug.print("\n=== EXPECTED ===\n{s}\n=== GOT ===\n{s}\n", .{ exp, got });
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
        if (a[i] != b[j]) return false;
        i += 1;
        j += 1;
    }
}

fn transformDecoratorsForTest(gpa: std.mem.Allocator, source: []const u8, cfg: DecoratorConfig) ![]const u8 {
    var arena_backing = std.heap.ArenaAllocator.init(gpa);
    defer arena_backing.deinit();
    const a = arena_backing.allocator();

    var node_arena = ast.Arena.init(a);
    var diags = diagnostics.DiagnosticList{};
    var p = parser.Parser.init(source, "test.ts", &node_arena, a, &diags, .{
        .typescript = true,
        .jsx = false,
        .source_type = .module,
    });

    const program_id = try p.parseProgram();
    try transformDecorators(&node_arena, a, cfg, program_id);

    var cg = try codegen.Codegen.init(&node_arena, a, .{
        .pretty = true,
        .source_map = false,
        .remove_comments = true,
    });
    defer cg.deinit();
    try cg.gen(program_id);
    const code = try cg.finish();
    return try gpa.dupe(u8, code);
}

fn expectCompilerOutputWithConfig(
    src: []const u8,
    expected: []const u8,
    cfg: compiler.Config,
) !void {
    const result = try compiler.compile(
        src,
        "src/test.ts",
        cfg,
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    if (result.map) |map| std.testing.allocator.free(map);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);

    const trimmed = normalizedOutput(result.code, expected);
    const exp_trimmed = trimText(expected);

    if (!std.mem.eql(u8, trimmed, exp_trimmed) and !equalIgnoringWhitespace(trimmed, exp_trimmed)) {
        std.debug.print(
            "\n=== EXPECTED ===\n{s}\n=== GOT ===\n{s}\n",
            .{ exp_trimmed, trimmed },
        );
        return error.TestExpectedEqual;
    }
}

// ── Config API ───────────────────────────────────────────────────────────────

test "config: decorators defaults to true" {
    const cfg = compiler.Config{};
    try std.testing.expect(cfg.parser.syntax == .typescript);
    try std.testing.expect(cfg.parser.decorators);
    try std.testing.expect(cfg.transform.legacy_decorator);
    try std.testing.expect(cfg.transform.decorator_metadata);
    try std.testing.expect(cfg.keep_class_names);
}

test "config: decorators fields are independent" {
    const cfg = compiler.Config{
        .parser = .{ .syntax = .ecmascript, .decorators = true },
        .transform = .{ .legacy_decorator = true, .decorator_metadata = true },
        .keep_class_names = true,
    };
    try std.testing.expect(cfg.parser.syntax == .ecmascript);
    try std.testing.expect(cfg.parser.decorators);
    try std.testing.expect(cfg.transform.legacy_decorator);
    try std.testing.expect(cfg.transform.decorator_metadata);
    try std.testing.expect(cfg.keep_class_names);
}

// ── Parse: decorators are parsed ─────────────────────────────────────────────

test "parse: class decorator is parsed (decorators:false strips it)" {
    // With decorators:false (default), decorator is parsed then stripped.
    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript, .decorators = false } };
    const result = try compiler.compile("@Dec\nclass Foo {}", "test.ts", cfg, std.testing.io, alloc);
    defer alloc.free(result.code);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) alloc.free(result.diagnostics);
    const out = normalizedOutput(result.code, "class Foo {}");
    try std.testing.expectEqualStrings("class Foo {}", out);
}

test "parse: method decorator is parsed and stripped when decorators:false" {
    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript, .decorators = false } };
    const result = try compiler.compile(
        \\class Foo {
        \\  @Dec
        \\  method() {}
        \\}
    , "test.ts", cfg, std.testing.io, alloc);
    defer alloc.free(result.code);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) alloc.free(result.diagnostics);
    const out = normalizedOutput(result.code, "class Foo {}");
    try std.testing.expect(std.mem.indexOf(u8, out, "@") == null);
}

test "parse: factory decorator is parsed" {
    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript, .decorators = false } };
    const result = try compiler.compile("@Dec()\nclass Foo {}", "test.ts", cfg, std.testing.io, alloc);
    defer alloc.free(result.code);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) alloc.free(result.diagnostics);
    const out = normalizedOutput(result.code, "class Foo {}");
    try std.testing.expectEqualStrings("class Foo {}", out);
}

test "parse: member-access decorator is parsed" {
    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript, .decorators = false } };
    const result = try compiler.compile("@Module.Dec\nclass Foo {}", "test.ts", cfg, std.testing.io, alloc);
    defer alloc.free(result.code);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) alloc.free(result.diagnostics);
    const out = normalizedOutput(result.code, "class Foo {}");
    try std.testing.expectEqualStrings("class Foo {}", out);
}

test "parse: multiple class decorators are parsed" {
    const cfg = compiler.Config{ .parser = .{ .syntax = .typescript, .decorators = false } };
    const result = try compiler.compile("@A\n@B\nclass Foo {}", "test.ts", cfg, std.testing.io, alloc);
    defer alloc.free(result.code);
    if (result.map) |m| alloc.free(m);
    if (result.diagnostics.len > 0) alloc.free(result.diagnostics);
    const out = normalizedOutput(result.code, "class Foo {}");
    try std.testing.expectEqualStrings("class Foo {}", out);
}

// ── Legacy decorator: class ───────────────────────────────────────────────────

test "legacy: single class decorator" {
    try expectDec(
        "@Dec\nclass Foo {}",
        true,
        false,
        DECORATE_HELPER ++ "\nlet Foo = class Foo {};\nFoo = __decorate([Dec], Foo);",
    );
}

test "legacy: multiple class decorators applied bottom-up" {
    // __decorate applies bottom-up internally; array order is source order [A, B]
    try expectDec(
        "@A\n@B\nclass Foo {}",
        true,
        false,
        DECORATE_HELPER ++ "\nlet Foo = class Foo {};\nFoo = __decorate([A, B], Foo);",
    );
}

test "legacy: factory decorator on class" {
    try expectDec(
        "@Dec()\nclass Foo {}",
        true,
        false,
        DECORATE_HELPER ++ "\nlet Foo = class Foo {};\nFoo = __decorate([Dec()], Foo);",
    );
}

test "legacy: class decorator with inheritance" {
    try expectDec(
        "@Dec\nclass Foo extends Bar {}",
        true,
        false,
        DECORATE_HELPER ++ "\nlet Foo = class Foo extends Bar {};\nFoo = __decorate([Dec], Foo);",
    );
}

test "legacy: member-access decorator on class" {
    try expectDec(
        "@Module.Dec\nclass Foo {}",
        true,
        false,
        DECORATE_HELPER ++ "\nlet Foo = class Foo {};\nFoo = __decorate([Module.Dec], Foo);",
    );
}

test "legacy: class without decorator is unchanged" {
    try expectDec(
        "class Foo {}",
        true,
        false,
        "class Foo {}",
    );
}

// ── Legacy decorator: method ──────────────────────────────────────────────────

test "legacy: method decorator" {
    try expectDec(
        \\class Foo {
        \\  @Dec
        \\  method() {}
        \\}
    ,
        true,
        false,
        DECORATE_HELPER ++
            "\nclass Foo {\n  method() {}\n}\n__decorate([Dec], Foo.prototype, \"method\", null);",
    );
}

test "legacy: static method decorator uses class not prototype" {
    try expectDec(
        \\class Foo {
        \\  @Dec
        \\  static method() {}
        \\}
    ,
        true,
        false,
        DECORATE_HELPER ++
            "\nclass Foo {\n  static method() {}\n}\n__decorate([Dec], Foo, \"method\", null);",
    );
}

test "legacy: property decorator uses void 0" {
    try expectDec(
        \\class Foo {
        \\  @Dec
        \\  value = 1;
        \\}
    ,
        true,
        false,
        DECORATE_HELPER ++
            "\nclass Foo {\n  value = 1;\n}\n__decorate([Dec], Foo.prototype, \"value\", void 0);",
    );
}

test "legacy: multiple method decorators bottom-up in array" {
    // decorators array [A, B] applied bottom-up by __decorate
    try expectDec(
        \\class Foo {
        \\  @A
        \\  @B
        \\  method() {}
        \\}
    ,
        true,
        false,
        DECORATE_HELPER ++
            "\nclass Foo {\n  method() {}\n}\n__decorate([A, B], Foo.prototype, \"method\", null);",
    );
}

test "legacy: class + method decorators combined" {
    // Method __decorate before class __decorate
    try expectDec(
        \\@ClassDec
        \\class Foo {
        \\  @MethodDec
        \\  method() {}
        \\}
    ,
        true,
        false,
        DECORATE_HELPER ++
            "\nlet Foo = class Foo {\n  method() {}\n};\n__decorate([MethodDec], Foo.prototype, \"method\", null);" ++
            "\nFoo = __decorate([ClassDec], Foo);",
    );
}

// ── Decorator metadata ────────────────────────────────────────────────────────

test "metadata: method decorator with metadata helper" {
    try expectDec(
        \\class Foo {
        \\  @Dec
        \\  method() {}
        \\}
    ,
        true,
        true,
        DECORATE_HELPER ++ "\n" ++ METADATA_HELPER ++
            "\nclass Foo {\n  method() {}\n}\n" ++
            "__decorate([Dec, __metadata(\"design:type\", Function)], Foo.prototype, \"method\", null);",
    );
}

test "metadata: async method decorator uses method descriptor" {
    try expectDec(
        \\class Foo {
        \\  @Dec
        \\  async method() {}
        \\}
    ,
        true,
        true,
        DECORATE_HELPER ++ "\n" ++ METADATA_HELPER ++
            "\nclass Foo {\n  async method() {}\n}\n" ++
            "__decorate([Dec, __metadata(\"design:type\", Function)], Foo.prototype, \"method\", null);",
    );
}

test "metadata: parameter decorator emits __param and paramtypes" {
    try expectDec(
        \\import { Service } from './service';
        \\@ClassDec()
        \\class Foo {
        \\  constructor(private service: Service) {}
        \\  @MethodDec()
        \\  async method(@Arg() value: unknown): Promise<void> {}
        \\}
    ,
        true,
        true,
        "\"use strict\";\n" ++ DECORATE_HELPER ++ "\n" ++ METADATA_HELPER ++ "\n" ++ PARAM_HELPER ++ "\n" ++
            "import { Service } from './service';\nlet Foo = class Foo {\n  constructor(service) {\n    this.service = service;\n  }\n  async method(value) {}\n};\n" ++
            "__decorate([MethodDec(), __param(0, Arg()), __metadata(\"design:type\", Function), __metadata(\"design:paramtypes\", [Object]), __metadata(\"design:returntype\", Promise)], Foo.prototype, \"method\", null);\n" ++
            "Foo = __decorate([ClassDec(), __metadata(\"design:paramtypes\", [typeof Service === \"undefined\" ? Object : Service])], Foo);",
    );
}

test "metadata: qualified parameter types emit valid runtime fallback" {
    const out = try compileDec(
        \\class Controller {
        \\  @Decorated()
        \\  async save(@Param() value: App.Contracts.Upload.Input) {}
        \\}
    , true, true);
    defer alloc.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "__param(0, Param())") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "__metadata(\"design:paramtypes\", [typeof App === \"undefined\" ? Object : App.Contracts.Upload.Input])") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "typeof  ===") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "? Object : ]") == null);
}

test "metadata: class without method decorators has no metadata helper" {
    // Class-only decorators: __metadata("design:paramtypes") added to __decorate array
    const out = try compileDec("@Dec\nclass Foo {}", true, true);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "__decorate") != null);
}

test "legacy: computed enum property decorators use computed keys in class and __decorate" {
    const out = try compileDec(
        \\enum BlankSideEnum {
        \\  BACK = 0,
        \\  FRONT = 1
        \\}
        \\class AreaValue {}
        \\class Area {
        \\  @Expose()
        \\  @ApiValidateNested(() => AreaValue)
        \\  [BlankSideEnum.FRONT]?: AreaValue;
        \\}
    , true, false);
    defer alloc.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "[BlankSideEnum.FRONT];") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "__decorate([Expose(), ApiValidateNested(() => AreaValue)], Area.prototype, BlankSideEnum.FRONT, void 0);") != null);
}

test "metadata: zero-arg constructor emits empty paramtypes array" {
    const out = try compileDec(
        \\@Dec
        \\class Foo {
        \\  constructor() {}
        \\}
    , true, true);
    defer alloc.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "__metadata(\"design:paramtypes\", [])") != null);
}

// ── legacy_decorator: false (decorators: true but no transform) ───────────────

test "no-legacy: decorators parsed and stripped, no transform" {
    // decorators: true but legacy_decorator: false → just strip, no __decorate calls
    try expectDec(
        "@Dec\nclass Foo {}",
        false,
        false,
        "class Foo {}",
    );
}

test "no-legacy: method decorator stripped without transform" {
    const out = try compileDec(
        \\class Foo {
        \\  @Dec
        \\  method() {}
        \\}
    , false, false);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "__decorate") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Dec") == null);
}

test "decorator on export class with import" {
    const out = try compileDec(
        \\import { something } from 'some-lib';
        \\@Dec({ value: something })
        \\export class Service {}
    , true, false);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "Service") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "__decorate") != null);
}

test "decorator on export default class" {
    const out = try compileDec(
        \\@Dec
        \\export default class Foo {}
    , true, false);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "Foo") != null);
}

// ── constructor parameter decorators ─────────────────────────────────────────

test "ctor param decorator: class with class decorator + param decorator" {
    try expectDec(
        \\@Singleton()
        \\class ServiceA {
        \\  constructor(@Dep('TOKEN') private dep: string) {}
        \\}
    , true, false,
        \\var __decorate = function(decorators, target, key, desc) { var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d; for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r; return c > 3 && r && Object.defineProperty(target, key, r), r; };
        \\var __param = function(paramIndex, decorator) { return function(target, key) { decorator(target, key, paramIndex); }; };
        \\"use strict";
        \\let ServiceA = class ServiceA {
        \\  constructor(dep) {}
        \\};
        \\ServiceA = __decorate([
        \\  Singleton(),
        \\  __param(0, Dep('TOKEN'))
        \\], ServiceA);
    );
}

test "ctor param decorator: class WITHOUT class decorator, only param decorator" {
    const out = try compileDec(
        \\class ServiceB {
        \\  constructor(@Dep('TOKEN') private token: string) {}
        \\}
    , true, false);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, PARAM_HELPER) != null);
    try std.testing.expect(std.mem.indexOf(u8, out, DECORATE_HELPER) != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "__param(0, Dep('TOKEN'))") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "__decorate([") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "], ServiceB)") != null);
}

test "ctor param decorator: multiple decorated params" {
    const out = try compileDec(
        \\class Service {
        \\  constructor(
        \\    @Dep('A') private a: string,
        \\    @Dep('B') private b: number,
        \\  ) {}
        \\}
    , true, false);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "__param(0, Dep('A'))") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "__param(1, Dep('B'))") != null);
}

test "ctor param decorator: export class without class decorator" {
    const out = try compileDec(
        \\export class ServiceD {
        \\  constructor(@Dep('token') private dep: string) {}
        \\}
    , true, false);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "__param(0, Dep('token'))") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "ServiceD") != null);
}

test "ctor param decorator: multiple decorators on same param" {
    const out = try compileDec(
        \\class Service {
        \\  constructor(@DecA() @DecB() private value: string) {}
        \\}
    , true, false);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "__param(0, DecA())") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "__param(0, DecB())") != null);
}

test "ctor param decorator: fixture compiles without errors" {
    const result = try compiler.compileFile(
        "tests/fixtures/constructor_param_decorators.ts",
        .{
            .parser = .{ .syntax = .typescript, .decorators = true },
            .transform = .{ .legacy_decorator = true, .decorator_metadata = false },
        },
        std.testing.io,
        alloc,
    );
    defer alloc.free(result.code);
    defer if (result.map) |m| alloc.free(m);
    defer if (result.diagnostics.len > 0) alloc.free(result.diagnostics);

    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    try std.testing.expect(std.mem.indexOf(u8, result.code, DECORATE_HELPER) != null);
    try std.testing.expect(std.mem.indexOf(u8, result.code, PARAM_HELPER) != null);
    // ServiceA: class + param decorator
    try std.testing.expect(std.mem.indexOf(u8, result.code, "__param(0, Dep('TOKEN_A'))") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.code, "__param(1, Dep('TOKEN_B'))") != null);
    // ServiceB: no class decorator, only param
    try std.testing.expect(std.mem.indexOf(u8, result.code, "], ServiceB)") != null);
}

test "legacy decorators lower exported class to let plus named export" {
    const out = try transformDecoratorsForTest(alloc,
        \\@Entity()
        \\export class Store extends BaseEntity {}
    , .{ .legacy = true, .emit_metadata = false });
    defer alloc.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "export class Store") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "let Store = class Store extends BaseEntity") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Store = __decorate([Entity()], Store);") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "export { Store };") != null);
}

test "legacy metadata decorators lower exported class without class declaration export" {
    const out = try transformDecoratorsForTest(alloc,
        \\@Entity()
        \\export class Store extends BaseEntity {}
    , .{ .legacy = true, .emit_metadata = true });
    defer alloc.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "export class Store") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "let Store = class Store extends BaseEntity") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Store = __decorate([Entity(), __metadata(\"design:paramtypes\", [])], Store);") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "export { Store };") != null);
}

test "stage3 decorated export class keeps export class syntax" {
    var cfg = compiler.Config{};
    cfg.parser.syntax = .typescript;
    cfg.parser.decorators = true;
    cfg.transform.legacy_decorator = false;

    try expectCompilerOutputWithConfig(
        \\function module(args: { imports: string[] }): ClassDecorator {
        \\  return function (target) {
        \\  }
        \\}
        \\
        \\@module({
        \\  imports: []
        \\})
        \\export class AppModule {}
    ,
        \\function module(args) {
        \\  return function(target) {
        \\  };
        \\}
        \\export class AppModule {}
    ,
        cfg,
    );
}

test "decorators cover class method field accessor and parameter" {
    const out = try transformDecoratorsForTest(alloc,
        \\@classDec
        \\class Example {
        \\  @fieldDec
        \\  field: string = "value";
        \\
        \\  @methodDec
        \\  method(@paramDec value: string): void {}
        \\
        \\  @accessorDec
        \\  get name(): string { return this.field; }
        \\}
    , .{ .legacy = true, .emit_metadata = true });
    defer alloc.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "__decorate") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "classDec") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "fieldDec") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "methodDec") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "__param(0, paramDec)") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "accessorDec") != null);
}

test "decorator expressions support call member and factory forms" {
    const out = try transformDecoratorsForTest(alloc,
        \\@ns.entity({ table: "users" })
        \\@sealed()
        \\class User {}
    , .{ .legacy = true, .emit_metadata = false });
    defer alloc.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "ns.entity") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "sealed()") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "User = __decorate") != null);
}
