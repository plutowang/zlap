pub const Parser = @import("zap.zig").Parser;
pub const ParseError = @import("zap.zig").ParseError;

// Optional: export commonly used types at the top level for convenience
pub const Handler = @import("zap.zig").Handler;
pub const Flag = @import("zap.zig").Parser.Flag;
pub const Option = @import("zap.zig").Parser.Option;
pub const PositionalArg = @import("zap.zig").Parser.PositionalArg;
pub const Logger = @import("logger.zig").Logger;

// Run tests when `zig build test` is called
test {
    @import("std").testing.refAllDecls(@This());
}
