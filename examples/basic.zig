const std = @import("std");
const zlap = @import("zlap");
const Logger = zlap.Logger;
const Handler = zlap.Handler;
pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var logger = Logger{};

    // Create a simple CLI parser
    var parser = zlap.Parser.init(allocator, "basic", "A basic example using zlap", &logger);
    defer parser.deinit();

    _ = parser
        .setHandler(handler)
        .option('n', "name", "Developer's name", "NAME");

    const args = try init.minimal.args.toSlice(allocator);

    try parser.parse(args);
    try parser.execute();
}

fn handler(parser: *zlap.Parser) zlap.ParseError!void {
    const logger = parser.logger;
    const name = parser.getOption("name") orelse "Guest";
    logger.info("Hello, {s}!", .{name});
    if (parser.getFlag("verbose")) {
        logger.debug("Verbose mode is ON", .{});
    }
}
