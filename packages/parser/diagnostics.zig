const std = @import("std");

pub const Severity = enum { err, warn, hint };

pub const Diagnostic = struct {
    severity: Severity,
    message: []const u8,
    filename: []const u8,
    line: u32,
    col: u32,
    source_line: ?[]const u8,
    len: u32,
};

pub const DiagnosticList = struct {
    items: std.ArrayListUnmanaged(Diagnostic) = .empty,

    pub fn add(self: *DiagnosticList, alloc: std.mem.Allocator, d: Diagnostic) !void {
        try self.items.append(alloc, d);
    }

    pub fn hasErrors(self: *const DiagnosticList) bool {
        for (self.items.items) |d| {
            if (d.severity == .err) return true;
        }
        return false;
    }

    pub fn render(self: *const DiagnosticList, writer: anytype) !void {
        try renderDiagnostics(self.items.items, writer);
    }
};

pub fn printDiagnostics(diagnostics: []const Diagnostic) void {
    for (diagnostics) |d| {
        const label = switch (d.severity) {
            .err => "error",
            .warn => "warning",
            .hint => "hint",
        };
        std.debug.print("{s}:{d}:{d} {s}: {s}\n", .{ d.filename, d.line, d.col, label, d.message });
        if (d.source_line) |src_line| {
            const line_num_width: usize = if (d.line < 10) 1 else if (d.line < 100) 2 else if (d.line < 1000) 3 else 4;
            std.debug.print("{d} | {s}\n", .{ d.line, src_line });
            for (0..line_num_width) |_| std.debug.print(" ", .{});
            std.debug.print(" | ", .{});
            const col = if (d.col > 0) d.col - 1 else 0;
            for (0..col) |_| std.debug.print(" ", .{});
            for (0..@max(d.len, 1)) |_| std.debug.print("^", .{});
            std.debug.print("\n", .{});
        }
    }
}

pub fn renderDiagnostics(diagnostics: []const Diagnostic, writer: anytype) !void {
    for (diagnostics) |d| {
        const label = switch (d.severity) {
            .err => "error",
            .warn => "warning",
            .hint => "hint",
        };
        try writer.print("{s}:{d}:{d} {s}: {s}\n", .{
            d.filename, d.line, d.col, label, d.message,
        });
        if (d.source_line) |src_line| {
            const line_num_width: usize = if (d.line < 10) 1 else if (d.line < 100) 2 else if (d.line < 1000) 3 else 4;
            try writer.print("{d} | {s}\n", .{ d.line, src_line });
            for (0..line_num_width) |_| try writer.writeByte(' ');
            try writer.print(" | ", .{});
            const col = if (d.col > 0) d.col - 1 else 0;
            for (0..col) |_| try writer.writeByte(' ');
            for (0..@max(d.len, 1)) |_| try writer.writeByte('^');
            try writer.writeByte('\n');
        }
    }
}
