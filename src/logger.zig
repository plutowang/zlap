const std = @import("std");
const print = std.debug.print;

// ANSI color codes
const Color = struct {
    const RED = "\x1b[0;31m";
    const GREEN = "\x1b[0;32m";
    const YELLOW = "\x1b[1;33m";
    const BLUE = "\x1b[0;34m";
    const PURPLE = "\x1b[0;35m";
    const RESET = "\x1b[0m"; // reset any color
};

/// Logger provides colored console output for different log levels.
/// Supports info, success, warning, error, and debug messages.
/// Debug messages are only printed when debug_mode is enabled.
///
/// Example usage:
///     const logger = Logger{ .debug_mode = true };
///     logger.info("Application started", .{});
///     logger.success("Task completed: {s}", .{"backup"});
///     logger.warning("Low memory: {d}MB", .{128});
///     logger.err("Failed to connect: {s}", .{"timeout"});
///     logger.debug("Variable value: {d}", .{42});
pub const Logger = struct {
    // Debug mode flag - set to true to enable debug logging
    debug_mode: bool = false,

    pub fn info(_: Logger, comptime fmt: []const u8, args: anytype) void {
        print("{s}[INFO]{s} " ++ fmt ++ "\n", .{ Color.BLUE, Color.RESET } ++ args);
    }

    pub fn success(_: Logger, comptime fmt: []const u8, args: anytype) void {
        print("{s}[SUCCESS]{s} " ++ fmt ++ "\n", .{ Color.GREEN, Color.RESET } ++ args);
    }

    pub fn warning(_: Logger, comptime fmt: []const u8, args: anytype) void {
        print("{s}[WARNING]{s} " ++ fmt ++ "\n", .{ Color.YELLOW, Color.RESET } ++ args);
    }

    pub fn err(_: Logger, comptime fmt: []const u8, args: anytype) void {
        print("{s}[ERROR]{s} " ++ fmt ++ "\n", .{ Color.RED, Color.RESET } ++ args);
    }

    pub fn debug(self: Logger, comptime fmt: []const u8, args: anytype) void {
        if (self.debug_mode) {
            print("{s}[DEBUG]{s} " ++ fmt ++ "\n", .{ Color.PURPLE, Color.RESET } ++ args);
        }
    }
};
