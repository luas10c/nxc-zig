const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── Core modules ──────────────────────────────────

    const lexer_mod = b.createModule(.{
        .root_source_file = b.path("packages/lexer/lexer.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ast_mod = b.createModule(.{
        .root_source_file = b.path("packages/parser/ast.zig"),
        .target = target,
        .optimize = optimize,
    });
    ast_mod.addImport("lexer", lexer_mod);

    const diagnostics_mod = b.createModule(.{
        .root_source_file = b.path("packages/parser/diagnostics.zig"),
        .target = target,
        .optimize = optimize,
    });

    const parser_mod = b.createModule(.{
        .root_source_file = b.path("packages/parser/parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    parser_mod.addImport("lexer", lexer_mod);
    parser_mod.addImport("ast", ast_mod);
    parser_mod.addImport("diagnostics", diagnostics_mod);

    // ── Resolver modules ───────────────────────────────

    const paths_mod = b.createModule(.{
        .root_source_file = b.path("packages/resolver/paths.zig"),
        .target = target,
        .optimize = optimize,
    });
    paths_mod.addImport("parser", parser_mod);

    const decorators_mod = b.createModule(.{
        .root_source_file = b.path("packages/transform/decorators.zig"),
        .target = target,
        .optimize = optimize,
    });

    decorators_mod.addImport("ast", ast_mod);
    decorators_mod.addImport("lexer", lexer_mod);

    const aliases_mod = b.createModule(.{
        .root_source_file = b.path("packages/resolver/aliases.zig"),
        .target = target,
        .optimize = optimize,
    });
    aliases_mod.addImport("parser", parser_mod);

    // ── Transform ──

    const class_names_mod = b.createModule(.{
        .root_source_file = b.path("packages/transform/class_names.zig"),
        .target = target,
        .optimize = optimize,
    });

    class_names_mod.addImport("ast", ast_mod);

    const json5_mod = b.createModule(.{
        .root_source_file = b.path("packages/transform/json5.zig"),
        .target = target,
        .optimize = optimize,
    });

    const jsx_mod = b.createModule(.{
        .root_source_file = b.path("packages/transform/jsx.zig"),
        .target = target,
        .optimize = optimize,
    });

    jsx_mod.addImport("ast", ast_mod);
    jsx_mod.addImport("lexer", lexer_mod);

    const module_interop_mod = b.createModule(.{
        .root_source_file = b.path("packages/transform/module_interop.zig"),
        .target = target,
        .optimize = optimize,
    });

    module_interop_mod.addImport("ast", ast_mod);
    module_interop_mod.addImport("lexer", lexer_mod);
    module_interop_mod.addImport("json5", json5_mod);

    const modules_mod = b.createModule(.{
        .root_source_file = b.path("packages/transform/modules.zig"),
        .target = target,
        .optimize = optimize,
    });

    modules_mod.addImport("ast", ast_mod);
    modules_mod.addImport("lexer", lexer_mod);
    modules_mod.addImport("json5", json5_mod);
    modules_mod.addImport("module_interop", module_interop_mod);

    const pipeline_mod = b.createModule(.{
        .root_source_file = b.path("packages/transform/pipeline.zig"),
        .target = target,
        .optimize = optimize,
    });
    pipeline_mod.addImport("parser", parser_mod);
    pipeline_mod.addImport("lexer", lexer_mod);
    pipeline_mod.addImport("paths", paths_mod);
    pipeline_mod.addImport("aliases", aliases_mod);
    pipeline_mod.addImport("ast", ast_mod);
    pipeline_mod.addImport("modules", modules_mod);
    pipeline_mod.addImport("decorators", decorators_mod);
    pipeline_mod.addImport("json5", json5_mod);
    pipeline_mod.addImport("jsx", jsx_mod);

    // ── Codegen ─────────────────────────────────────

    const sourcemap_mod = b.createModule(.{
        .root_source_file = b.path("packages/codegen/sourcemap.zig"),
        .target = target,
        .optimize = optimize,
    });

    const codegen_mod = b.createModule(.{
        .root_source_file = b.path("packages/codegen/codegen.zig"),
        .target = target,
        .optimize = optimize,
    });
    codegen_mod.addImport("lexer", lexer_mod);
    codegen_mod.addImport("parser", parser_mod);
    codegen_mod.addImport("ast", ast_mod);
    codegen_mod.addImport("sourcemap", sourcemap_mod);

    // ── Config module ──────────────────────────────

    const config_mod = b.createModule(.{
        .root_source_file = b.path("packages/core/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    config_mod.addImport("pipeline", pipeline_mod);
    config_mod.addImport("aliases", aliases_mod);
    config_mod.addImport("modules", modules_mod);
    config_mod.addImport("jsx", jsx_mod);
    config_mod.addImport("json5", json5_mod);

    // ── Core compiler ──────────────────────────────

    const compiler_mod = b.createModule(.{
        .root_source_file = b.path("packages/core/compiler.zig"),
        .target = target,
        .optimize = optimize,
    });
    compiler_mod.addImport("parser", parser_mod);
    compiler_mod.addImport("pipeline", pipeline_mod);
    compiler_mod.addImport("codegen", codegen_mod);
    compiler_mod.addImport("paths", paths_mod);
    compiler_mod.addImport("aliases", aliases_mod);
    compiler_mod.addImport("config", config_mod);
    compiler_mod.addImport("diagnostics", diagnostics_mod);
    compiler_mod.addImport("ast", ast_mod);
    compiler_mod.addImport("class_names", class_names_mod);
    compiler_mod.addImport("modules", modules_mod);

    // ── CLI library ───────────────────────────────

    const cli_lib_mod = b.createModule(.{
        .root_source_file = b.path("packages/cli/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_lib_mod.addImport("compiler", compiler_mod);
    cli_lib_mod.addImport("parser", parser_mod);
    cli_lib_mod.addImport("diagnostics", diagnostics_mod);

    // ── CLI main ────────────────────────────────

    const cli_mod = b.createModule(.{
        .root_source_file = b.path("packages/cli/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_mod.addImport("compiler", compiler_mod);
    cli_mod.addImport("config", config_mod);
    cli_mod.addImport("cli", cli_lib_mod);

    // ── Executable ────────────────────────────────

    const exe = b.addExecutable(.{ .name = "nxc", .root_module = cli_mod });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run nxc").dependOn(&run_cmd.step);

    // ── Test modules ──────────────────────────────

    const compiler_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/unit/compiler_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    compiler_tests_mod.addImport("compiler", compiler_mod);
    compiler_tests_mod.addImport("pipeline", pipeline_mod);
    compiler_tests_mod.addImport("cli", cli_lib_mod);

    const decorator_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/unit/decorator_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    decorator_tests_mod.addImport("compiler", compiler_mod);

    const json5_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/unit/json5_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    json5_tests_mod.addImport("pipeline", pipeline_mod);

    const jsx_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/unit/jsx_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ansi_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/unit/ansi_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    ansi_tests_mod.addImport("cli", cli_mod);

    const cli_tests_mod = b.createModule(.{
        .root_source_file = b.path("tests/integration/cli_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_tests_mod.addImport("cli", cli_lib_mod);
    cli_tests_mod.addImport("compiler", compiler_mod);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.root_module.addImport("lexer", lexer_mod);
    unit_tests.root_module.addImport("ast", ast_mod);
    unit_tests.root_module.addImport("diagnostics", diagnostics_mod);
    unit_tests.root_module.addImport("parser", parser_mod);
    unit_tests.root_module.addImport("compiler", compiler_mod);
    unit_tests.root_module.addImport("pipeline", pipeline_mod);
    unit_tests.root_module.addImport("cli", cli_lib_mod);
    unit_tests.root_module.addImport("paths", paths_mod);
    unit_tests.root_module.addImport("decorators", decorators_mod);
    unit_tests.root_module.addImport("json5", json5_mod);
    unit_tests.root_module.addImport("jsx", jsx_mod);
    unit_tests.root_module.addImport("sourcemap", sourcemap_mod);
    unit_tests.root_module.addImport("codegen", codegen_mod);
    unit_tests.root_module.addImport("config", config_mod);

    unit_tests.root_module.addImport("cli_main", cli_mod);
    unit_tests.root_module.addImport("compiler_tests", compiler_tests_mod);
    unit_tests.root_module.addImport("decorator_tests", decorator_tests_mod);
    unit_tests.root_module.addImport("json5_tests", json5_tests_mod);
    unit_tests.root_module.addImport("jsx_tests", jsx_tests_mod);
    unit_tests.root_module.addImport("ansi_tests", ansi_tests_mod);
    unit_tests.root_module.addImport("cli_tests", cli_tests_mod);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = lexer_mod })).step);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = cli_mod })).step);
}
