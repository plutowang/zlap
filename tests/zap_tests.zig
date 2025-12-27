const std = @import("std");
const zap = @import("zap");
const Parser = zap.Parser;
const ParseError = zap.ParseError;
const Logger = zap.Logger;

test "shared logger debug mode" {
    const allocator = std.testing.allocator;
    var logger = Logger{ .debug_mode = false };
    var parser = Parser.init(allocator, "test", "test description", &logger);
    defer parser.deinit();

    const args = &[_][]const u8{ "test", "--verbose" };
    try parser.parse(args);

    try std.testing.expect(logger.debug_mode == true);
}

test "shared logger with sub-command" {
    const allocator = std.testing.allocator;
    var logger = Logger{};
    var parser = Parser.init(allocator, "test", "test description", &logger);
    defer parser.deinit();

    const handler = struct {
        fn h(_: *Parser) ParseError!void {}
    }.h;

    _ = try parser.subCommand("sub", "sub-command", handler);

    const args = &[_][]const u8{ "test", "sub", "--verbose" };
    try parser.parse(args);

    try std.testing.expect(logger.debug_mode == true);
}

test "shared logger short flag debug mode" {
    const allocator = std.testing.allocator;
    var logger = Logger{};
    var parser = Parser.init(allocator, "test", "test description", &logger);
    defer parser.deinit();

    const args = &[_][]const u8{ "test", "-v" };
    try parser.parse(args);

    try std.testing.expect(logger.debug_mode == true);
    try std.testing.expect(parser.parsed_flags.get("v").? == true);
}

test "parser flag and option storage" {
    const allocator = std.testing.allocator;
    var logger = Logger{};
    var parser = Parser.init(allocator, "test", "test", &logger);
    defer parser.deinit();

    _ = parser
        .flag('f', "flag", "a flag")
        .option('o', "opt", "an option", "VALUE");

    const args = &[_][]const u8{ "test", "-f", "--opt", "val" };
    try parser.parse(args);

    try std.testing.expect(parser.parsed_flags.get("f").? == true);
    try std.testing.expect(std.mem.eql(u8, parser.parsed_options.get("opt").?, "val"));
}

test "parser helpers and defaults" {
    const allocator = std.testing.allocator;
    var logger = Logger{};
    var parser = Parser.init(allocator, "test", "test", &logger);
    defer parser.deinit();

    _ = parser
        .flag('f', "flag", "a flag")
        .option('o', "opt", "an option", "VALUE")
        .optionWithDefault('d', "default", "with default", "VAL", "8080")
        .arg("input", "input", true);

    const args = &[_][]const u8{ "test", "--flag", "myfile" };
    try parser.parse(args);

    try std.testing.expect(parser.getFlag("flag") == true);
    try std.testing.expect(parser.getFlag("f") == true);
    try std.testing.expect(parser.getOption("default") != null);
    try std.testing.expect(std.mem.eql(u8, parser.getOption("default").?, "8080"));
    try std.testing.expect(std.mem.eql(u8, parser.getOption("d").?, "8080"));
    try std.testing.expect(std.mem.eql(u8, parser.getArg(0).?, "myfile"));
    try std.testing.expect(parser.getArg(1) == null);
}

var test_executed_root: bool = false;
var test_executed_sub: bool = false;

test "parser execute" {
    const allocator = std.testing.allocator;
    var logger = Logger{};
    var parser = Parser.init(allocator, "test", "test", &logger);
    defer parser.deinit();

    test_executed_root = false;
    test_executed_sub = false;

    const root_handler = struct {
        fn h(_: *Parser) ParseError!void {
            test_executed_root = true;
        }
    }.h;

    const sub_handler = struct {
        fn h(_: *Parser) ParseError!void {
            test_executed_sub = true;
        }
    }.h;

    _ = try parser
        .setHandler(root_handler)
        .subCommand("sub", "sub-command", sub_handler);

    // Test root execution
    try parser.parse(&[_][]const u8{"test"});
    try parser.execute();
    try std.testing.expect(test_executed_root == true);
    try std.testing.expect(test_executed_sub == false);

    // Reset and test sub-command execution
    test_executed_root = false;
    try parser.parse(&[_][]const u8{ "test", "sub" });
    try parser.execute();
    try std.testing.expect(test_executed_root == false);
    try std.testing.expect(test_executed_sub == true);
}

test "findByName refinement" {
    const allocator = std.testing.allocator;
    var logger = Logger{};
    var parser = Parser.init(allocator, "test", "test", &logger);
    defer parser.deinit();

    _ = parser
        .flag(null, "f", "1-char long flag")
        .option(null, "o", "1-char long option", "VAL");

    const args = &[_][]const u8{ "test", "--f", "--o", "val" };
    try parser.parse(args);

    // Verify 1-char long names work
    try std.testing.expect(parser.getFlag("f") == true);
    try std.testing.expect(std.mem.eql(u8, parser.getOption("o").?, "val"));

    // Verify empty name doesn't crash and returns default
    try std.testing.expect(parser.getFlag("") == false);
    try std.testing.expect(parser.getOption("") == null);
}
