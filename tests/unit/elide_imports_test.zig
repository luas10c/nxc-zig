const std = @import("std");

const compiler = @import("compiler");

fn expectContainsText(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) return;
    std.debug.print("expected to find '{s}' in text\n", .{needle});
    return error.TestExpectedEqual;
}

test "ts elide: decorator metadata does not keep type-only parameter import" {
    const source =
        \\import { Post, Body } from "@nestjs/common";
        \\import { CreateNotificationBody } from "../requests/create-notification-body.js";
        \\
        \\class NotificationsController {
        \\  @Post()
        \\  async create(@Body() body: CreateNotificationBody): Promise<any> {
        \\    return body;
        \\  }
        \\}
    ;

    var cfg = compiler.Config{};
    cfg.parser.syntax = .typescript;
    cfg.parser.decorators = true;
    cfg.transform.legacy_decorator = true;
    cfg.transform.decorator_metadata = true;

    const result = try compiler.compile(
        source,
        "test.ts",
        cfg,
        std.testing.io,
        std.testing.allocator,
    );
    defer std.testing.allocator.free(result.code);
    if (result.map) |map| std.testing.allocator.free(map);
    if (result.diagnostics.len > 0) std.testing.allocator.free(result.diagnostics);

    try expectContainsText(result.code, "import { Post, Body } from \"@nestjs/common\"");
    try std.testing.expect(std.mem.indexOf(u8, result.code, "create-notification-body") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.code, "import { CreateNotificationBody }") == null);
    try expectContainsText(result.code, "typeof CreateNotificationBody === \"undefined\" ? Object : CreateNotificationBody");
}
