# Zlap

A modern, feature-rich command-line argument parsing library for Zig.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE) [![CI](https://github.com/plutowang/zlap/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/plutowang/zlap/actions/workflows/ci.yml) [![Zig](https://img.shields.io/badge/Zig-0.15.2+-yellow.svg)](https://ziglang.org/) [![Release](https://img.shields.io/github/v/release/plutowang/zlap?include_prereleases)](https://github.com/plutowang/zlap/releases)

## Real-World Usage

Zlap is used in production CLI tools such as [nvim.pack](https://github.com/plutowang/nvim.pack), a Neovim configuration manager using `vim.pack`. The [`cli`](https://github.com/plutowang/nvim.pack/tree/main/cli) implementation demonstrates:

- Subcommand architecture (`link`, `bench`)
- Flag inheritance from parent to subcommand parsers
- Option parsing with defaults and validation
- Integrated colored logging
- Production-ready CLI patterns

## Features

- **Fast and lightweight** - Zero external dependencies
- **Flexible API** - Supports flags, options, positional arguments, and subcommands
- **Auto-generated help** - Beautiful help messages with minimal configuration
- **Type-safe parsing** - Leverage Zig's type system for safer argument handling
- **Colored output** - Built-in logger with colored console output
- **Validation** - Automatic validation of required arguments and options
- **Chainable API** - Fluent interface for easy parser configuration

## Installation

Add zlap to your `build.zig.zon`:

### Option 1: From GitHub Release (Recommended)

```zig
.dependencies = .{
    .zlap = .{
        .url = "https://github.com/plutowang/zlap/archive/v0.0.1-beta.tar.gz",
        .hash = "...",
    },
},
```

Get the hash: `zig fetch --save https://github.com/plutowang/zlap/archive/v0.0.1-beta.tar.gz`

### Option 2: From Main Branch (Latest)

```zig
.dependencies = .{
    .zlap = .{
        .url = "https://github.com/plutowang/zlap/archive/main.tar.gz",
        .hash = "...",
    },
},
```

> **Note**: Rerun `zig fetch --save https://github.com/plutowang/zlap/archive/main.tar.gz` when main branch updates to get new hash.

### Option 3: Local Development

```zig
.dependencies = .{
    .zlap = .{ .path = "../zlap" },
},
```

Then in your `build.zig`:

```zig
const zlap = b.dependency("zlap", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zlap", zlap.module("zlap"));
```

## API Reference

### Parser Creation

```zig
const zlap = @import("zlap");

// Initialize logger
var logger = zlap.Logger{ .debug_mode = false };

// Create parser
var parser = zlap.Parser.init(allocator, "myapp", "Description", &logger);
defer parser.deinit();
```

> **Note**: The `-v`/`--verbose` flag is **reserved** and automatically added to every Parser. When set by users, it enables `logger.debug()` output. Do not define your own `-v` or `--verbose` flag.

### Adding Arguments

#### Flags (Boolean options)

```zig
// Add a flag with short and long form
_ = parser.flag('d', "debug", "Enable debug mode");

// Short form only
_ = parser.flag('q', null, "Quiet mode");

// Long form only
_ = parser.flag(null, "force", "Force operation");
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

Zlap supports flexible formats:

**Long options:**

- `--option=value` or `--option value`

**Short options:**

- `-o value` or `-ovalue` or `-o=value`
- `-abc` (multiple flags: `-a -b -c`)

Examples:

```bash
# All equivalent:
myapp --output=file.txt
myapp --output file.txt
myapp -ofile.txt

# Multiple flags:
myapp -vdq   # same as -v -d -q
```

### Subcommands

Zlap supports nested subcommands for complex CLI applications:

```zig
// Handler function for subcommand
fn serveHandler(subparser: *zlap.Parser) zlap.ParseError!void {
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
// Check if flag was provided (returns bool)
if (parser.getFlag("verbose")) {
    // verbose mode enabled
}

// Get option value (returns ?[]const u8)
if (parser.getOption("output")) |output_path| {
    // use output_path
}

// Get positional argument by index (returns ?[]const u8)
if (parser.getArg(0)) |first_arg| {
    // use first_arg
}
```

## Error Handling

Zlap provides detailed error information for various parsing scenarios:

```zig
parser.parse(args) catch |err| {
    switch (err) {
        zlap.ParseError.MissingArgument => {
            parser.logger.error("Missing required argument");
        },
        zlap.ParseError.MissingOption => {
            parser.logger.error("Missing required option");
        },
        zlap.ParseError.UnknownOption => {
            parser.logger.error("Unknown option provided");
        },
        zlap.ParseError.MissingValue => {
            parser.logger.error("Option requires a value");
        },
        zlap.ParseError.SubCommandNotFound => {
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

Zlap automatically generates comprehensive help messages:

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

### Production Example

For a complete, real-world example, see [nvim.pack](https://github.com/plutowang/nvim.pack) - specifically the [`cli`](https://github.com/plutowang/nvim.pack/tree/main/cli) implementation. This Neovim configuration manager demonstrates subcommands, flag inheritance, options with defaults, and production-ready patterns.

### Getting Started

Check out the [examples/](examples/) directory for basic examples:

- [`basic.zig`](examples/basic.zig) - Simple argument parsing demonstrating core features

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Requirements

- Zig 0.15.2 or later

---

**Zlap** - Making command-line parsing in Zig a breeze!
