const std = @import("std");

const parser = @import("parser");
const codegen = @import("codegen");
const diagnostics = @import("diagnostics");
const ast = @import("ast");
const jsx = @import("jsx");

const JsxConfig = jsx.JsxConfig;
const transformJsx = jsx.transformJsx;

fn compileJsxForTest(alloc: std.mem.Allocator, source: []const u8, cfg: JsxConfig) ![]const u8 {
    var arena_backing = std.heap.ArenaAllocator.init(alloc);
    defer arena_backing.deinit();
    const arena_alloc = arena_backing.allocator();

    var node_arena = ast.Arena.init(arena_alloc);
    var diags = diagnostics.DiagnosticList{};

    var p = parser.Parser.init(source, "test.tsx", &node_arena, arena_alloc, &diags, .{
        .typescript = true,
        .jsx = true,
        .source_type = .module,
    });
    const program_id = try p.parseProgram();
    try std.testing.expect(!diags.hasErrors());

    try transformJsx(&node_arena, arena_alloc, cfg, program_id);

    var cg = try codegen.Codegen.init(&node_arena, alloc, .{
        .pretty = true,
        .source_map = false,
        .remove_comments = true,
        .comments = p.comments.items,
    });
    defer cg.deinit();
    try cg.gen(program_id);
    return cg.finish();
}

test "JSX supports hyphenated props and expression prop values" {
    const source =
        \\const el = <section data-value={value} aria-label="Name" />;
    ;

    const out = try compileJsxForTest(std.testing.allocator, source, .{ .runtime = .classic });
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "React.createElement") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"section\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"data-value\": value") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"aria-label\": \"Name\"") != null);
}

test "JSX supports expression children with nested JSX" {
    const source =
        \\const el = <section data-value={value}>{children ?? <span>empty</span>}</section>;
    ;

    const out = try compileJsxForTest(std.testing.allocator, source, .{ .runtime = .classic });
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "\"data-value\": value") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "children ?? React.createElement") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"span\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"empty\"") != null);
}

test "automatic JSX runtime emits children prop" {
    const source =
        \\const el = <Box title={title}>{children ?? <span>empty</span>}</Box>;
    ;

    const out = try compileJsxForTest(std.testing.allocator, source, .{ .runtime = .automatic });
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "import { jsx as _jsx") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "title: title") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "children: children ?? _jsx") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"span\"") != null);
}

test "tsx syntax coverage: generic arrow disambiguation and typed JSX props" {
    const source =
        \\type BoxProps<T> = { value: T };
        \\const identity = <T,>(value: T): T => value;
        \\const constrained = <T extends string>(value: T): T => value;
        \\const el = <Box<string> value={identity("x")} />;
    ;

    const out = try compileJsxForTest(std.testing.allocator, source, .{ .runtime = .automatic });
    defer std.testing.allocator.free(out);

    // The emitter intentionally drops parens for single-identifier arrow params.
    // This test is about TSX generic-arrow disambiguation/type stripping, not
    // about forcing a particular paren style.
    try std.testing.expect(std.mem.indexOf(u8, out, "const identity = value => value") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "const constrained = value => value") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "_jsx(Box") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "value: identity") != null);
}

test "tsx syntax coverage: fragments member names namespace names spread and boolean props" {
    const source =
        \\const page = <>
        \\  <Layout.Header title="Home" />
        \\  <svg:path strokeWidth={2} />
        \\  <Button {...props} disabled data-id={id}>Save</Button>
        \\</>;
    ;

    const out = try compileJsxForTest(std.testing.allocator, source, .{ .runtime = .classic });
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "React.Fragment") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Layout.Header") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "svg:path") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "...props") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "disabled: true") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "data-id") != null);
}

test "tsx syntax coverage: nested JSX expression children and automatic jsxs" {
    const source =
        \\const view = <List>
        \\  {items.map((item: Item) => <List.Item key={item.id}>{item.name ?? "empty"}</List.Item>)}
        \\  <footer>{count satisfies number}</footer>
        \\</List>;
    ;

    const out = try compileJsxForTest(std.testing.allocator, source, .{ .runtime = .automatic });
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "jsxs as _jsxs") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "List.Item") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "item.name ?? \"empty\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "satisfies") == null);
}
