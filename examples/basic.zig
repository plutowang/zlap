const std = @import("std");
const zap = @import("zap");
const Logger = zap.Logger;
const Handler = zap.Handler;
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var logger = Logger{};

    // Create a simple CLI parser
    var parser = zap.Parser.init(allocator, "basic", "A basic example using zap", &logger);
    defer parser.deinit();

    _ = parser
        .setHandler(handler)
        .option('n', "name", "Developer's name", "NAME");

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    try parser.parse(args);
    try parser.execute();
}

fn handler(parser: *zap.Parser) zap.ParseError!void {
    const logger = parser.logger;
    const name = parser.getOption("name") orelse "Guest";
    logger.info("Hello, {s}!", .{name});
    if (parser.getFlag("verbose")) {
        logger.debug("Verbose mode is ON", .{});
    }
}
