const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Logger = @import("logger.zig").Logger;

/// Possible errors during command-line argument parsing.
pub const ParseError = error{
    /// A subcommand was specified but not found in the parser's registry.
    SubCommandNotFound,
    /// No handler function was registered for the active command or subcommand.
    NoHandler,
    /// An option that requires a value was provided without one.
    MissingValue,
    /// An unrecognized option or flag was encountered.
    UnknownOption,
    /// A required positional argument was not provided.
    MissingArgument,
    /// A flag or option was encountered after positional arguments started.
    UnexpectedFlag,
    /// A required option was not provided.
    MissingOption,
} || Allocator.Error;

/// A function type used to handle the logic of a command or subcommand after successful parsing.
pub const Handler = *const fn (*Parser) ParseError!void;

/// Represents a subcommand with its own name, description, and parser.
pub const SubCommand = struct {
    name: []const u8,
    description: []const u8,
    parser: *Parser,

    const Self = @This();

    /// Initializes a new SubCommand instance.
    pub fn init(allocator: Allocator, name: []const u8, desc: []const u8, handler: Handler, logger: *Logger) !*Self {
        const cmd = try allocator.create(Self);
        const parser = try allocator.create(Parser);
        parser.* = Parser.init(allocator, name, desc, logger);
        parser.handler = @ptrCast(handler);
        cmd.* = .{
            .name = name,
            .description = desc,
            .parser = parser,
        };
        return cmd;
    }

    /// Deinitializes the SubCommand and its associated parser.
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.parser.deinit();
        allocator.destroy(self.parser);
        allocator.destroy(self);
    }
};

/// Main command-line argument parser.
///
/// Features:
/// - Support for flags (-v, --verbose)
/// - Support for options with values (-o value, --opt=value)
/// - Support for positional arguments
/// - Support for subcommands
/// - Automatic help generation
/// - Shared logger for debugging
///
/// Note: The '-v' or '--verbose' flag is reserved for "Enable verbose logging"
/// and is automatically added to every Parser instance.
pub const Parser = struct {
    allocator: mem.Allocator,
    program_name: []const u8,
    description: []const u8,
    logger: *Logger,
    handler: ?*const anyopaque,

    flags: std.ArrayList(Flag),
    options: std.ArrayList(Option),
    positional_args: std.ArrayList(PositionalArg),
    sub_commands: std.StringHashMap(*SubCommand),

    parsed_flags: std.StringHashMap(bool),
    parsed_options: std.StringHashMap([]const u8),
    parsed_positional: std.ArrayList([]const u8),
    active_sub_command: ?*SubCommand,

    /// Parent parser for flag/option inheritance.
    /// When a subcommand is created, its parser's parent is set to the
    /// creating parser. This allows getFlag/getOption to traverse up the
    /// chain and find flags/options registered on parent parsers.
    parent: ?*Self,

    /// Configuration for a boolean flag (on/off).
    pub const Flag = struct {
        short: ?u8, // e.g., 'v' for -v
        long: ?[]const u8, // e.g., "verbose" for --verbose
        description: []const u8,
        default: bool = false,
    };

    /// Configuration for an option that takes a value.
    pub const Option = struct {
        short: ?u8,
        long: ?[]const u8,
        description: []const u8,
        value_name: []const u8, // e.g., "FILE", "PATH"
        default: ?[]const u8 = null,
        required: bool = false,
    };

    /// Configuration for a positional argument.
    pub const PositionalArg = struct {
        name: []const u8,
        description: []const u8,
        required: bool = true,
    };

    const Self = @This();

    /// Initializes a new Parser.
    /// Automatically adds the reserved '--verbose' flag.
    pub fn init(allocator: mem.Allocator, program_name: []const u8, description: []const u8, logger: *Logger) Parser {
        var self = Parser{
            .allocator = allocator,
            .program_name = program_name,
            .description = description,
            .logger = logger,
            .handler = null,
            .flags = .empty,
            .options = .empty,
            .positional_args = .empty,
            .sub_commands = std.StringHashMap(*SubCommand).init(allocator),
            .parsed_flags = std.StringHashMap(bool).init(allocator),
            .parsed_options = std.StringHashMap([]const u8).init(allocator),
            .parsed_positional = .empty,
            .active_sub_command = null,
            .parent = null,
        };

        // -v, --verbose is reserved for "Enable verbose logging"
        _ = self.flag('v', "verbose", "Enable verbose logging");

        return self;
    }

    /// Deinitializes the Parser and all its resources.
    pub fn deinit(self: *Self) void {
        // Clean up sub commands
        var sub_iter = self.sub_commands.valueIterator();
        while (sub_iter.next()) |cmd| {
            cmd.*.deinit(self.allocator);
        }

        // Clean up ArrayLists and HashMaps
        self.flags.deinit(self.allocator);
        self.options.deinit(self.allocator);
        self.positional_args.deinit(self.allocator);
        self.sub_commands.deinit();
        self.parsed_flags.deinit();
        self.parsed_options.deinit();
        self.parsed_positional.deinit(self.allocator);
    }

    // =================== Parameter Builders ===================

    /// Adds a boolean flag to the parser.
    /// If both short_char and long_name are provided, both will work.
    pub fn flag(self: *Self, short_char: ?u8, long_name: ?[]const u8, desc: []const u8) *Self {
        const f = Flag{
            .short = short_char,
            .long = long_name,
            .description = desc,
        };
        self.flags.append(self.allocator, f) catch @panic("Failed to add flag");

        return self;
    }

    /// Adds an optional option that takes a value.
    pub fn option(self: *Self, short_char: ?u8, long_name: ?[]const u8, desc: []const u8, value_name: []const u8) *Self {
        const opt = Option{
            .short = short_char,
            .long = long_name,
            .description = desc,
            .value_name = value_name,
        };
        self.options.append(self.allocator, opt) catch @panic("Failed to add option");
        return self;
    }

    /// Adds a required option that takes a value.
    pub fn requiredOption(self: *Self, short_char: ?u8, long_name: ?[]const u8, desc: []const u8, value_name: []const u8) *Self {
        const opt = Option{
            .short = short_char,
            .long = long_name,
            .description = desc,
            .value_name = value_name,
            .required = true,
        };
        self.options.append(self.allocator, opt) catch @panic("Failed to add required option");
        return self;
    }

    /// Adds an option with a default value.
    pub fn optionWithDefault(self: *Self, short_char: ?u8, long_name: ?[]const u8, desc: []const u8, value_name: []const u8, default_val: []const u8) *Self {
        const opt = Option{
            .short = short_char,
            .long = long_name,
            .description = desc,
            .value_name = value_name,
            .default = default_val,
        };
        self.options.append(self.allocator, opt) catch @panic("Failed to add option with default");

        return self;
    }

    /// Adds a positional argument.
    pub fn arg(self: *Self, name: []const u8, desc: []const u8, required: bool) *Self {
        const pos_arg = PositionalArg{
            .name = name,
            .description = desc,
            .required = required,
        };
        self.positional_args.append(self.allocator, pos_arg) catch @panic("Failed to add positional argument");
        return self;
    }

    /// Sets the handler function to be executed when this command is parsed.
    pub fn setHandler(self: *Self, h: Handler) *Self {
        self.handler = @ptrCast(h);
        return self;
    }

    // =================== Subcommand Management ===================

    /// Adds a subcommand to the parser.
    /// Returns the new subcommand's parser for fluent configuration.
    /// The subcommand's parser inherits flags and options from this parent parser
    /// via the parent chain.
    pub fn subCommand(self: *Self, name: []const u8, desc: []const u8, handler: Handler) !*Self {
        const cmd = try SubCommand.init(self.allocator, name, desc, handler, self.logger);
        try self.sub_commands.put(name, cmd);
        cmd.parser.parent = self;
        return cmd.parser;
    }

    /// Returns the active subcommand's parser if one was parsed.
    pub fn getActiveSubCommand(self: *Self) ?*Self {
        if (self.active_sub_command) |cmd| {
            return cmd.parser;
        }

        return null;
    }

    /// Returns the name of the active subcommand if one was parsed.
    pub fn getActiveSubCommandName(self: *Self) ?[]const u8 {
        if (self.active_sub_command) |cmd| {
            return cmd.name;
        }

        return null;
    }

    /// Executes the handler for the active command or subcommand.
    pub fn execute(self: *Self) ParseError!void {
        if (self.active_sub_command) |cmd| {
            return cmd.parser.execute();
        }

        if (self.handler) |h_ptr| {
            const h: Handler = @ptrCast(@alignCast(h_ptr));
            return h(self);
        }

        self.printErrorAndExit("No handler registered for command '{s}'", .{self.program_name});
    }

    // =================== Parsing Logic ===================

    /// Parses the command-line arguments.
    /// The 'args' should include the program name at index 0.
    pub fn parse(self: *Parser, args: []const []const u8) ParseError!void {
        if (args.len == 0) return;

        var i: usize = 1; // Skip program name

        // First pass: parse global flags and options (before subcommand)
        i = try self.parseGlobalOptions(args, i);

        // Second pass: check for and handle subcommand
        i = try self.parseSubCommand(args, i);

        // Third pass: parse remaining positional arguments
        try self.parsePositionalArgs(args, i);

        // Validate all requirements are met
        try self.validateRequiredArgs();
        try self.validateRequiredOptions();
    }

    /// Get a flag value by its long or short name.
    /// Returns the defined default value if the flag was not provided.
    /// Traverses the parent chain if the flag is not found locally,
    /// allowing subcommands to inherit flags from parent parsers.
    pub fn getFlag(self: *const Self, name: []const u8) bool {
        if (self.parsed_flags.get(name)) |v| return v;
        if (self.findFlagByName(name)) |f| return f.default;
        // Traverse parent chain for inherited flags
        if (self.parent) |p| return p.getFlag(name);
        return false;
    }

    /// Get an option value by its long or short name.
    /// Returns the defined default value if the option was not provided.
    /// Traverses the parent chain if the option is not found locally,
    /// allowing subcommands to inherit options from parent parsers.
    pub fn getOption(self: *const Self, name: []const u8) ?[]const u8 {
        if (self.parsed_options.get(name)) |val| return val;
        if (self.findOptionByName(name)) |opt| return opt.default;
        // Traverse parent chain for inherited options
        if (self.parent) |p| return p.getOption(name);
        return null;
    }

    /// Get a positional argument by its index.
    pub fn getArg(self: *const Self, index: usize) ?[]const u8 {
        if (index >= self.parsed_positional.items.len) return null;
        return self.parsed_positional.items[index];
    }

    /// Parses global flags and options before any subcommand.
    fn parseGlobalOptions(self: *Parser, args: []const []const u8, index: usize) ParseError!usize {
        if (index >= args.len) return index;
        var i = index;

        while (i < args.len) {
            const current_arg = args[i];

            // Stop at first non-flag/option argument (positional arg or subcommand)
            if (!mem.startsWith(u8, current_arg, "-")) break;

            // Handle help flag specially
            if (mem.eql(u8, current_arg, "-h") or mem.eql(u8, current_arg, "--help")) {
                self.printHelp();
                std.process.exit(0);
            }

            // Parse the flag/option and update index
            i = if (mem.startsWith(u8, current_arg, "--"))
                try self.parseLongOption(args, i)
            else
                try self.parseShortOption(args, i);

            i += 1; // Move to next argument
        }

        return i;
    }

    /// Parses a long option (e.g., --name or --name=value).
    fn parseLongOption(self: *Parser, args: []const []const u8, index: usize) ParseError!usize {
        if (index >= args.len) return index;

        const current_arg = args[index];
        const long_opt = current_arg[2..]; // Skip "--"

        if (mem.indexOf(u8, long_opt, "=")) |eq_pos| {
            // --option=value format
            const opt_name = long_opt[0..eq_pos];
            const value = long_opt[eq_pos + 1 ..];
            if (self.findOption(null, opt_name)) |opt| {
                try self.setOptionValue(opt, value);
                return index;
            }
            self.printErrorAndExit("Unknown option --{s}", .{opt_name});
        }

        // Check if it's a boolean flag
        if (self.findFlag(null, long_opt)) |f| {
            try self.setFlag(f);
            return index;
        }

        // --option value format
        if (self.findOption(null, long_opt)) |opt| {
            const value_index = index + 1;
            if (value_index >= args.len) {
                self.printErrorAndExit("Option --{s} requires a value", .{long_opt});
            }
            try self.setOptionValue(opt, args[value_index]);
            return value_index;
        }

        self.printErrorAndExit("Unknown option --{s}", .{long_opt});
    }

    /// Parses short options (-o, -ovalue, -o=value, or clustered -abc).
    fn parseShortOption(self: *Parser, args: []const []const u8, index: usize) ParseError!usize {
        if (index >= args.len) return index;

        const current_arg = args[index];
        var opt_index: usize = 1; // skip the '-'

        // Handle -o=value format
        if (current_arg.len > 2 and current_arg[2] == '=') {
            const short_char = current_arg[opt_index];
            const value = current_arg[3..];
            if (self.findOption(short_char, null)) |opt| {
                try self.setOptionValue(opt, value);
                return index;
            }
            self.printErrorAndExit("Unknown option -{c}", .{short_char});
        }

        while (opt_index < current_arg.len) {
            const short_char = current_arg[opt_index];

            // Handle flags: -o
            if (self.findFlag(short_char, null)) |f| {
                try self.setFlag(f);
                opt_index += 1;
                continue;
            }

            // Handle options
            if (self.findOption(short_char, null)) |opt| {
                // -ovalue format (value attached)
                const attached_index = opt_index + 1;
                if (attached_index < current_arg.len) {
                    const value = current_arg[attached_index..];
                    try self.setOptionValue(opt, value);
                    return index;
                }

                // -o value format (value is next argument)
                const next_index = index + 1;
                if (next_index < args.len) {
                    const value = args[next_index];
                    try self.setOptionValue(opt, value);
                    return next_index;
                }
                self.printErrorAndExit("Option -{c} requires a value", .{short_char});
            }

            self.printErrorAndExit("Unknown option -{c}", .{short_char});
        }
        return index;
    }

    /// Handles subcommand detection and delegating parsing to it.
    fn parseSubCommand(self: *Parser, args: []const []const u8, index: usize) ParseError!usize {
        if (index >= args.len) return index;

        const current_arg = args[index];

        // Check if it's a known subcommand
        if (self.sub_commands.get(current_arg)) |cmd| {
            self.active_sub_command = cmd;

            // Prepare arguments for subcommand parsing (skip everything before the subcommand name)
            const subargs = try self.allocator.alloc([]const u8, args.len - index);
            defer self.allocator.free(subargs);

            subargs[0] = self.program_name;
            @memcpy(subargs[1..], args[index + 1 ..]);

            try cmd.parser.parse(subargs);
            return args.len; // Subcommand consumes all remaining args
        }

        return index;
    }

    /// Parses remaining arguments as positional arguments.
    fn parsePositionalArgs(self: *Parser, args: []const []const u8, index: usize) ParseError!void {
        if (index >= args.len) return;

        var i = index;
        while (i < args.len) {
            const current_arg = args[i];

            // Check for help flag
            if (mem.eql(u8, current_arg, "-h") or mem.eql(u8, current_arg, "--help")) {
                self.printHelp();
                std.process.exit(0);
            }

            // Error if flags are found after positional arguments have started
            if (mem.startsWith(u8, current_arg, "-")) {
                self.printErrorAndExit("Unexpected option '{s}' after positional arguments", .{current_arg});
            }

            try self.parsed_positional.append(self.allocator, current_arg);
            i += 1;
        }
    }

    /// Validates that all required positional arguments were provided.
    fn validateRequiredArgs(self: *Parser) ParseError!void {
        for (self.positional_args.items, 0..) |pos_arg, idx| {
            if (pos_arg.required and idx >= self.parsed_positional.items.len) {
                self.printErrorAndExit("Missing required argument: <{s}>", .{pos_arg.name});
            }
        }
    }

    /// Validates that all required options were provided.
    fn validateRequiredOptions(self: *Parser) ParseError!void {
        for (self.options.items) |opt| {
            if (!opt.required) continue;

            var found = false;

            // Check both short and long forms in the parsed results
            if (opt.short) |s| {
                if (self.parsed_options.contains(getShortName(s))) found = true;
            }

            if (opt.long) |l| {
                if (self.parsed_options.contains(l)) found = true;
            }

            if (!found) {
                if (opt.long) |l| {
                    self.printErrorAndExit("Missing required option: --{s}", .{l});
                } else if (opt.short) |s| {
                    self.printErrorAndExit("Missing required option: -{c}", .{s});
                }
            }
        }
    }

    // =================== Internal Helpers ===================

    /// Maps an option's value to both its short and long names in parsed_options.
    fn setOptionValue(self: *Parser, opt: Option, value: []const u8) ParseError!void {
        if (opt.long) |l| try self.parsed_options.put(l, value);
        if (opt.short) |s| try self.parsed_options.put(getShortName(s), value);
    }

    /// Sets a flag to true for both its short and long names in parsed_flags.
    /// Also handles enabling debug mode for the reserved 'verbose' flag.
    fn setFlag(self: *Parser, f: Flag) ParseError!void {
        if (f.long) |l| try self.parsed_flags.put(l, true);
        if (f.short) |s| try self.parsed_flags.put(getShortName(s), true);

        // Special handling for verbose flag to enable logger debug mode
        if ((f.long != null and mem.eql(u8, f.long.?, "verbose")) or
            (f.short != null and f.short.? == 'v'))
        {
            self.logger.debug_mode = true;
        }
    }

    /// Searches for a flag definition by short or long name.
    fn findFlag(self: *const Self, short: ?u8, long: ?[]const u8) ?Flag {
        for (self.flags.items) |fg| {
            if (short) |s| {
                if (fg.short) |fs| {
                    if (s == fs) return fg;
                }
            }
            if (long) |l| {
                if (fg.long) |fl| {
                    if (mem.eql(u8, l, fl)) return fg;
                }
            }
        }
        return null;
    }

    /// Searches for an option definition by short or long name.
    fn findOption(self: *const Self, short: ?u8, long: ?[]const u8) ?Option {
        for (self.options.items) |opt| {
            if (short) |s| {
                if (opt.short) |os| {
                    if (s == os) return opt;
                }
            }
            if (long) |l| {
                if (opt.long) |ol| {
                    if (mem.eql(u8, l, ol)) return opt;
                }
            }
        }
        return null;
    }

    /// Searches for a flag definition by a single name (either short or long).
    fn findFlagByName(self: *const Self, name: []const u8) ?Flag {
        return self.findFlag(if (name.len == 1) name[0] else null, name);
    }

    /// Searches for an option definition by a single name (either short or long).
    fn findOptionByName(self: *const Self, name: []const u8) ?Option {
        return self.findOption(if (name.len == 1) name[0] else null, name);
    }

    /// Prints an error message and the help text, then exits with code 1.
    /// This provides a user-friendly experience instead of a raw error trace.
    fn printErrorAndExit(self: *Parser, comptime fmt: []const u8, args: anytype) noreturn {
        self.logger.err(fmt, args);
        std.debug.print("\n", .{});
        self.printHelp();
        std.process.exit(1);
    }

    /// Prints a comprehensive help message including usage, commands, arguments, and options.
    fn printHelp(self: *Parser) void {
        self.printUsage();
        self.printDescription();
        self.printCommands();
        self.printArguments();
        self.printOptions();
        self.printFooter();
    }

    fn printUsage(self: *Parser) void {
        std.debug.print("Usage: {s}", .{self.program_name});

        if (self.sub_commands.count() > 0) {
            std.debug.print(" <COMMAND>", .{});
        }

        if (self.flags.items.len > 0 or self.options.items.len > 0) {
            std.debug.print(" [OPTIONS]", .{});
        }

        for (self.positional_args.items) |pos| {
            if (pos.required) {
                std.debug.print(" <{s}>", .{pos.name});
            } else {
                std.debug.print(" [{s}]", .{pos.name});
            }
        }

        std.debug.print("\n", .{});
    }

    fn printDescription(self: *Parser) void {
        if (self.description.len > 0) {
            std.debug.print("\n{s}\n", .{self.description});
        }
    }

    fn printCommands(self: *Parser) void {
        if (self.sub_commands.count() == 0) return;

        std.debug.print("\nCommands:\n", .{});
        var iter = self.sub_commands.iterator();
        while (iter.next()) |entry| {
            std.debug.print("  {s:<20} {s}\n", .{ entry.key_ptr.*, entry.value_ptr.*.description });
        }
    }

    fn printOptions(self: *Parser) void {
        if (self.flags.items.len == 0 and self.options.items.len == 0) return;

        std.debug.print("\nOptions:\n", .{});

        // Reuse a single buffer across all iterations to avoid repeated alloc/free.
        var buf = std.ArrayList(u8).empty;
        defer buf.deinit(self.allocator);

        // Print flags
        for (self.flags.items) |fg| {
            buf.clearRetainingCapacity();

            if (fg.short) |s| {
                buf.print(self.allocator, "-{c}", .{s}) catch {};
                if (fg.long != null) {
                    buf.print(self.allocator, ", ", .{}) catch {};
                }
            }
            if (fg.long) |l| {
                buf.print(self.allocator, "--{s}", .{l}) catch {};
            }

            std.debug.print("  {s:<20} {s}\n", .{ buf.items, fg.description });
        }

        // Reuse a second buffer for option descriptions across all iterations.
        var desc_buf = std.ArrayList(u8).empty;
        defer desc_buf.deinit(self.allocator);

        // Print options
        for (self.options.items) |opt| {
            buf.clearRetainingCapacity();

            if (opt.short) |s| {
                buf.print(self.allocator, "-{c} <{s}>", .{ s, opt.value_name }) catch {};
                if (opt.long != null) {
                    buf.print(self.allocator, ", ", .{}) catch {};
                }
            }
            if (opt.long) |l| {
                buf.print(self.allocator, "--{s}=<{s}>", .{ l, opt.value_name }) catch {};
            }

            // Build description with additional info
            desc_buf.clearRetainingCapacity();

            desc_buf.print(self.allocator, "{s}", .{opt.description}) catch {};

            if (opt.required) {
                desc_buf.print(self.allocator, " (required)", .{}) catch {};
            } else if (opt.default) |d| {
                desc_buf.print(self.allocator, " (default: {s})", .{d}) catch {};
            }

            std.debug.print("  {s:<20} {s}\n", .{ buf.items, desc_buf.items });
        }

        // Always show help option
        std.debug.print("  -h, --help           Show this help message\n", .{});
    }

    fn printArguments(self: *Parser) void {
        if (self.positional_args.items.len == 0) return;

        std.debug.print("\nArguments:\n", .{});
        for (self.positional_args.items) |pos| {
            const req_text = if (pos.required) "" else " (optional)";
            std.debug.print("  {s:<20} {s}{s}\n", .{ pos.name, pos.description, req_text });
        }
    }

    fn printFooter(self: *Parser) void {
        if (self.sub_commands.count() > 0) {
            std.debug.print("\nRun '{s} <COMMAND> --help' for more information on a command.\n", .{self.program_name});
        }
        std.debug.print("\n", .{});
    }
};

/// Lookup table for all possible character bytes (0-255).
/// Used to provide stable `[]const u8` slices for single-character keys
/// (like short flags) without heap allocation or transient stack pointers.
const ALL_CHARS = blk: {
    var arr: [256]u8 = undefined;
    for (&arr, 0..) |*c, i| c.* = @intCast(i);
    const final = arr;
    break :blk final;
};

/// Returns a stable, 1-character string slice for the given byte.
/// The returned slice points to the global `ALL_CHARS` array.
fn getShortName(c: u8) []const u8 {
    return ALL_CHARS[c .. c + 1];
}
test "getShortName" {
    try std.testing.expectEqualStrings("v", getShortName('v'));
    try std.testing.expectEqualStrings("a", getShortName('a'));
    try std.testing.expect(getShortName('a').ptr == getShortName('a').ptr);
}
