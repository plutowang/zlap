pub const Parser = @import("zlap.zig").Parser;
pub const ParseError = @import("zlap.zig").ParseError;

// Optional: export commonly used types at the top level for convenience
pub const Handler = @import("zlap.zig").Handler;
pub const Flag = @import("zlap.zig").Parser.Flag;
pub const Option = @import("zlap.zig").Parser.Option;
pub const PositionalArg = @import("zlap.zig").Parser.PositionalArg;
pub const Logger = @import("logger.zig").Logger;

// Run tests when `zig build test` is called
test {
    @import("std").testing.refAllDecls(@This());
}
