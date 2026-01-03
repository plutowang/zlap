# ⚡ Zap

A modern, feature-rich command-line argument parsing library for Zig.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## Features

- 🚀 **Fast and lightweight** - Zero external dependencies
- 🔧 **Flexible API** - Supports flags, options, positional arguments, and subcommands
- 📚 **Auto-generated help** - Beautiful help messages with minimal configuration
- 🎯 **Type-safe parsing** - Leverage Zig's type system for safer argument handling
- 🌈 **Colored output** - Built-in logger with colored console output
- ✅ **Validation** - Automatic validation of required arguments and options
- 🔄 **Chainable API** - Fluent interface for easy parser configuration

## Installation

### Using Zig Package Manager (Zig 0.15.2+)

Add zap to your `build.zig.zon`:

#### Option 1: From GitHub (recommended)

```zig
.{
    .name = "your-project",
    .version = "0.0.1-beta",
    .minimum_zig_version = "0.15.2",
    .dependencies = .{
        .zap = .{
            .url = "https://github.com/plutowang/zap/archive/v0.0.1-beta.tar.gz",
            .hash = "[...]",
        },
    },
}
```

#### Option 1b: Latest main branch (bleeding edge)

```zig
.{
    .name = "your-project",
    .version = "0.0.1-beta",
    .minimum_zig_version = "0.15.2",
    .dependencies = .{
        .zap = .{
            .url = "https://github.com/plutowang/zap/archive/main.tar.gz",
            .hash = "[...]",
        },
    },
}
```

> ⚠️ **Warning**: When using `main.tar.gz`, you'll need to run `zig fetch --save https://github.com/plutowang/zap/archive/main.tar.gz` again whenever new commits are pushed to get updates and the new hash.

#### Option 2: Local path (for development)

```zig
.{
    .name = "your-project",
    .version = "0.0.1-beta",
    .minimum_zig_version = "0.15.2",
    .dependencies = .{
        .zap = .{ .path = "../zap" },
    },
}
```

> **Note**: To get the correct hash for the GitHub URL, run `zig fetch --save https://github.com/plutowang/zap/archive/v0.0.1-beta.tar.gz` (or `main.tar.gz` for latest) which will automatically add the dependency with the correct hash to your `build.zig.zon`.
>
> **Recommended**: Use tagged releases (like `v0.0.1-beta`) instead of `main.tar.gz` for stable dependencies.

Then in your `build.zig`:

```zig
const zap = b.dependency("zap", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zap", zap.module("zap"));
```

## API Reference

### Parser Creation

```zig
var parser = zap.Parser.init(allocator, program_name, description, logger);
defer parser.deinit();
```

### Adding Arguments

#### Flags (Boolean options)

```zig
// Add a flag with short and long form
_ = parser.flag('v', "verbose", "Enable verbose output");

// Short form only
_ = parser.flag('q', null, "Quiet mode");

// Long form only
_ = parser.flag(null, "debug", "Enable debug mode");
```

#### Options (Value-taking arguments)

```zig
// Basic option
_ = parser.option('o', "output", "Output file", "FILE");

// Required option
_ = parser.requiredOption('c', "config", "Config file", "CONFIG");

// Option with default value
_ = parser.optionWithDefault('p', "port", "Port number", "PORT", "8080");
```

#### Positional Arguments

```zig
// Required positional argument
_ = parser.arg("input", "Input file to process", true);

// Optional positional argument
_ = parser.arg("output", "Output file (optional)", false);
```

### Argument Formats

Zap supports flexible argument formats for both short and long options:

#### Long Format Options

- `--option=value` - Value attached with equals sign
- `--option value` - Value as separate argument

#### Short Format Options

- `-o` - Flag only (for boolean flags)
- `-ovalue` - Value attached directly (no space)
- `-o=value` - Value attached with equals sign
- `-abc` - Multiple short flags combined (equivalent to `-a -b -c`)

Examples:

```bash
# These are equivalent for a string option:
myapp --output=file.txt
myapp --output file.txt
myapp -ofile.txt
myapp -o=file.txt
myapp -o file.txt

# These are equivalent for flags:
myapp --verbose --debug --quiet
myapp -vdq
```

### Subcommands

Zap supports nested subcommands for complex CLI applications:

```zig
// Handler function for subcommand
fn serveHandler(subparser: *zap.Parser) zap.ParseError!void {
    const port = subparser.getOption("port") orelse "8080";
    subparser.logger.info("Starting server on port {s}", .{port});
}

// Add subcommand
_ = try parser.subCommand("serve", "Start the server", serveHandler)
    .option('p', "port", "Port to listen on", "PORT")
    .flag('d', "daemon", "Run as daemon");

// Parse and execute
try parser.parse(args);
try parser.execute(); // Calls the appropriate handler
```

### Accessing Parsed Values

```zig
// Check if flag was provided
if (parser.hasFlag("verbose")) {
    // verbose mode enabled
}

// Get option value (returns ?[]const u8)
if (parser.getOption("output")) |output_path| {
    // use output_path
}

// Get positional argument by index
if (parser.getPositional(0)) |first_arg| {
    // use first_arg
}

// Get all positional arguments
const positional_args = parser.getAllPositional();
for (positional_args) |arg| {
    parser.logger.info("Arg: {s}", .{arg});
}
```

## Error Handling

Zap provides detailed error information for various parsing scenarios:

```zig
parser.parse(args) catch |err| {
    switch (err) {
        zap.ParseError.MissingArgument => {
            parser.logger.error("Missing required argument");
        },
        zap.ParseError.MissingOption => {
            parser.logger.error("Missing required option");
        },
        zap.ParseError.UnknownOption => {
            parser.logger.error("Unknown option provided");
        },
        zap.ParseError.MissingValue => {
            parser.logger.error("Option requires a value");
        },
        zap.ParseError.SubCommandNotFound => {
            parser.logger.error("Unknown subcommand");
        },
        else => {
            parser.logger.error("Parse error: {}", .{err});
        },
    }
    parser.printHelp();
    std.process.exit(1);
};
```

## Help Generation

Zap automatically generates comprehensive help messages:

```bash
$ myapp --help
Usage: myapp [OPTIONS] <input> [output]

A sample CLI application

Arguments:
  input                Input file to process
  output               Output file (optional)

Options:
  -v, --verbose        Enable verbose output
  -q, --quiet          Suppress output
  -o, --output=<FILE>  Output file path
  -c, --config=<CONFIG> Configuration file (required)
  -h, --help           Show this help message
```

For subcommands:

```bash
$ myapp serve --help
Usage: myapp serve [OPTIONS]

Start the server

Options:
  -p, --port=<PORT>    Port to listen on
  -d, --daemon         Run as daemon
  -h, --help           Show this help message
```

## Building and Testing

```bash
# Build the library and examples
zig build

# Run tests
zig build test

# Run the basic example
./zig-out/bin/basic --help
```

## Examples

Check out the [examples/](examples/) directory for more comprehensive examples:

- [`basic.zig`](examples/basic.zig) - Simple argument parsing
- More examples coming soon!

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Requirements

- Zig 0.15.2 or later

---

⚡ **Zap** - Making command-line parsing in Zig a breeze!
