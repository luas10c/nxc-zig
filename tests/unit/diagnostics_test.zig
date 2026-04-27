const std = @import("std");

const compiler = @import("compiler");
const diagnostics = @import("diagnostics");

const Diagnostic = diagnostics.Diagnostic;
const dupeDiags = compiler.dupeDiags;

test "dupeDiags owns source line slices" {
    const alloc = std.testing.allocator;

    var list = std.ArrayListUnmanaged(Diagnostic).empty;
    defer list.deinit(alloc);

    const src = try alloc.dupe(u8, "for (using resource = make();; ) {}");
    try list.append(alloc, .{
        .severity = .err,
        .message = "using declarations in for loops are only supported with for...of",
        .filename = "src/main.ts",
        .line = 1,
        .col = 21,
        .source_line = src,
        .len = 1,
    });

    const copied = try dupeDiags(&list, alloc);
    defer {
        for (copied) |d| {
            alloc.free(d.message);
            alloc.free(d.filename);
            if (d.source_line) |line| alloc.free(line);
        }
        alloc.free(copied);
    }

    alloc.free(src);

    try std.testing.expectEqualStrings("src/main.ts", copied[0].filename);
    try std.testing.expectEqualStrings("for (using resource = make();; ) {}", copied[0].source_line.?);
    try std.testing.expectEqualStrings(
        "using declarations in for loops are only supported with for...of",
        copied[0].message,
    );
}
