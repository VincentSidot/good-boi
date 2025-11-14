//! Simple GameBoy Assembly Compiler
//! Converts .s assembly files into raw binary data for CPU emulator testing
const std = @import("std");

const Instruction = struct {
    mnemonic: []const u8,
    opcode: u8,
    operands: u8, // Number of additional bytes (0, 1, or 2)
};

// Basic instruction set for testing - focusing on implemented opcodes
const INSTRUCTIONS = [_]Instruction{
    // NOP
    .{ .mnemonic = "NOP", .opcode = 0x00, .operands = 0 },

    // Load instructions
    .{ .mnemonic = "LD BC,", .opcode = 0x01, .operands = 2 },
    .{ .mnemonic = "LD DE,", .opcode = 0x11, .operands = 2 },
    .{ .mnemonic = "LD HL,", .opcode = 0x21, .operands = 2 },
    .{ .mnemonic = "LD SP,", .opcode = 0x31, .operands = 2 },

    .{ .mnemonic = "LD B,", .opcode = 0x06, .operands = 1 },
    .{ .mnemonic = "LD C,", .opcode = 0x0E, .operands = 1 },
    .{ .mnemonic = "LD D,", .opcode = 0x16, .operands = 1 },
    .{ .mnemonic = "LD E,", .opcode = 0x1E, .operands = 1 },
    .{ .mnemonic = "LD H,", .opcode = 0x26, .operands = 1 },
    .{ .mnemonic = "LD L,", .opcode = 0x2E, .operands = 1 },
    .{ .mnemonic = "LD A,", .opcode = 0x3E, .operands = 1 },

    .{ .mnemonic = "LD A,B", .opcode = 0x78, .operands = 0 },
    .{ .mnemonic = "LD A,C", .opcode = 0x79, .operands = 0 },
    .{ .mnemonic = "LD A,D", .opcode = 0x7A, .operands = 0 },
    .{ .mnemonic = "LD A,E", .opcode = 0x7B, .operands = 0 },
    .{ .mnemonic = "LD A,H", .opcode = 0x7C, .operands = 0 },
    .{ .mnemonic = "LD A,L", .opcode = 0x7D, .operands = 0 },
    .{ .mnemonic = "LD A,(HL)", .opcode = 0x7E, .operands = 0 },
    .{ .mnemonic = "LD A,A", .opcode = 0x7F, .operands = 0 },

    // INC/DEC instructions
    .{ .mnemonic = "INC BC", .opcode = 0x03, .operands = 0 },
    .{ .mnemonic = "INC DE", .opcode = 0x13, .operands = 0 },
    .{ .mnemonic = "INC HL", .opcode = 0x23, .operands = 0 },
    .{ .mnemonic = "INC SP", .opcode = 0x33, .operands = 0 },

    .{ .mnemonic = "INC B", .opcode = 0x04, .operands = 0 },
    .{ .mnemonic = "INC C", .opcode = 0x0C, .operands = 0 },
    .{ .mnemonic = "INC D", .opcode = 0x14, .operands = 0 },
    .{ .mnemonic = "INC E", .opcode = 0x1C, .operands = 0 },
    .{ .mnemonic = "INC H", .opcode = 0x24, .operands = 0 },
    .{ .mnemonic = "INC L", .opcode = 0x2C, .operands = 0 },
    .{ .mnemonic = "INC A", .opcode = 0x3C, .operands = 0 },
    .{ .mnemonic = "INC (HL)", .opcode = 0x34, .operands = 0 },

    .{ .mnemonic = "DEC B", .opcode = 0x05, .operands = 0 },
    .{ .mnemonic = "DEC C", .opcode = 0x0D, .operands = 0 },
    .{ .mnemonic = "DEC D", .opcode = 0x15, .operands = 0 },
    .{ .mnemonic = "DEC E", .opcode = 0x1D, .operands = 0 },
    .{ .mnemonic = "DEC H", .opcode = 0x25, .operands = 0 },
    .{ .mnemonic = "DEC L", .opcode = 0x2D, .operands = 0 },
    .{ .mnemonic = "DEC A", .opcode = 0x3D, .operands = 0 },
    .{ .mnemonic = "DEC (HL)", .opcode = 0x35, .operands = 0 },

    // Arithmetic instructions
    .{ .mnemonic = "ADD A,B", .opcode = 0x80, .operands = 0 },
    .{ .mnemonic = "ADD A,C", .opcode = 0x81, .operands = 0 },
    .{ .mnemonic = "ADD A,D", .opcode = 0x82, .operands = 0 },
    .{ .mnemonic = "ADD A,E", .opcode = 0x83, .operands = 0 },
    .{ .mnemonic = "ADD A,H", .opcode = 0x84, .operands = 0 },
    .{ .mnemonic = "ADD A,L", .opcode = 0x85, .operands = 0 },
    .{ .mnemonic = "ADD A,(HL)", .opcode = 0x86, .operands = 0 },
    .{ .mnemonic = "ADD A,A", .opcode = 0x87, .operands = 0 },
    .{ .mnemonic = "ADD A,", .opcode = 0xC6, .operands = 1 },

    // Jump instructions
    .{ .mnemonic = "JP", .opcode = 0xC3, .operands = 2 },
    .{ .mnemonic = "JP NZ,", .opcode = 0xC2, .operands = 2 },
    .{ .mnemonic = "JP Z,", .opcode = 0xCA, .operands = 2 },
    .{ .mnemonic = "JP NC,", .opcode = 0xD2, .operands = 2 },
    .{ .mnemonic = "JP C,", .opcode = 0xDA, .operands = 2 },
    .{ .mnemonic = "JR", .opcode = 0x18, .operands = 1 },
    .{ .mnemonic = "JR NZ,", .opcode = 0x20, .operands = 1 },
    .{ .mnemonic = "JR Z,", .opcode = 0x28, .operands = 1 },
    .{ .mnemonic = "JR NC,", .opcode = 0x30, .operands = 1 },
    .{ .mnemonic = "JR C,", .opcode = 0x38, .operands = 1 },

    // Call/Return instructions
    .{ .mnemonic = "CALL", .opcode = 0xCD, .operands = 2 },
    .{ .mnemonic = "RET", .opcode = 0xC9, .operands = 0 },

    // Stack instructions
    .{ .mnemonic = "PUSH BC", .opcode = 0xC5, .operands = 0 },
    .{ .mnemonic = "PUSH DE", .opcode = 0xD5, .operands = 0 },
    .{ .mnemonic = "PUSH HL", .opcode = 0xE5, .operands = 0 },
    .{ .mnemonic = "PUSH AF", .opcode = 0xF5, .operands = 0 },
    .{ .mnemonic = "POP BC", .opcode = 0xC1, .operands = 0 },
    .{ .mnemonic = "POP DE", .opcode = 0xD1, .operands = 0 },
    .{ .mnemonic = "POP HL", .opcode = 0xE1, .operands = 0 },
    .{ .mnemonic = "POP AF", .opcode = 0xF1, .operands = 0 },
};

const AssemblerError = error{
    InvalidInstruction,
    InvalidNumber,
    OutOfMemory,
    FileNotFound,
    WriteError,
};

const Assembler = struct {
    output: std.array_list.AlignedManaged(u8, null),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        var output = std.ArrayList(u8).empty;
        return Self{
            .output = output.toManaged(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit();
    }

    fn parseNumber(text: []const u8) !u16 {
        // Handle hex numbers (0x prefix or $ prefix)
        if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) {
            return std.fmt.parseInt(u16, text[2..], 16);
        }
        if (std.mem.startsWith(u8, text, "$")) {
            return std.fmt.parseInt(u16, text[1..], 16);
        }
        // Handle binary numbers (0b prefix or % prefix)
        if (std.mem.startsWith(u8, text, "0b") or std.mem.startsWith(u8, text, "0B")) {
            return std.fmt.parseInt(u16, text[2..], 2);
        }
        if (std.mem.startsWith(u8, text, "%")) {
            return std.fmt.parseInt(u16, text[1..], 2);
        }
        // Default to decimal
        return std.fmt.parseInt(u16, text, 10);
    }

    fn trimWhitespace(text: []const u8) []const u8 {
        const start = std.mem.indexOfAnyPos(u8, text, 0, " \t\n\r") orelse return text;
        if (start > 0) return text[0..start];

        var i = start;
        while (i < text.len and (text[i] == ' ' or text[i] == '\t' or text[i] == '\n' or text[i] == '\r')) {
            i += 1;
        }
        return text[i..];
    }

    fn findInstruction(mnemonic: []const u8) ?Instruction {
        for (INSTRUCTIONS) |inst| {
            if (std.mem.eql(u8, inst.mnemonic, mnemonic)) {
                return inst;
            }
        }
        return null;
    }

    pub fn assembleLine(self: *Self, line: []const u8) !void {
        const trimmed = self.trimWhitespace(line);

        // Skip empty lines and comments
        if (trimmed.len == 0 or trimmed[0] == ';' or trimmed[0] == '#') {
            return;
        }

        // Convert to uppercase for case-insensitive matching
        var upper_line = try self.allocator.alloc(u8, trimmed.len);
        defer self.allocator.free(upper_line);

        for (trimmed, 0..) |c, i| {
            upper_line[i] = std.ascii.toUpper(c);
        }

        // Try to match instructions
        var matched = false;
        for (INSTRUCTIONS) |inst| {
            if (std.mem.startsWith(u8, upper_line, inst.mnemonic)) {
                try self.output.append(inst.opcode);

                // Handle operands
                if (inst.operands > 0) {
                    const operand_start = inst.mnemonic.len;
                    if (operand_start < upper_line.len) {
                        var operand_text = self.trimWhitespace(upper_line[operand_start..]);

                        // Remove trailing comma if present
                        if (operand_text.len > 0 and operand_text[operand_text.len - 1] == ',') {
                            operand_text = operand_text[0 .. operand_text.len - 1];
                        }

                        const value = self.parseNumber(operand_text) catch |err| {
                            std.debug.print("Error parsing number '{s}': {}\n", .{ operand_text, err });
                            return AssemblerError.InvalidNumber;
                        };

                        if (inst.operands == 1) {
                            // Single byte operand
                            try self.output.append(@intCast(value & 0xFF));
                        } else if (inst.operands == 2) {
                            // Two byte operand (little-endian)
                            try self.output.append(@intCast(value & 0xFF)); // Low byte
                            try self.output.append(@intCast((value >> 8) & 0xFF)); // High byte
                        }
                    } else {
                        return AssemblerError.InvalidInstruction;
                    }
                }

                matched = true;
                break;
            }
        }

        if (!matched) {
            std.debug.print("Unknown instruction: {s}\n", .{trimmed});
            return AssemblerError.InvalidInstruction;
        }
    }

    pub fn assembleFile(self: *Self, filename: []const u8) !void {
        const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
            std.debug.print("Could not open file '{s}': {}\n", .{ filename, err });
            return AssemblerError.FileNotFound;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB max
        defer self.allocator.free(content);

        // var lines = std.mem.split(u8, content, "\n");
        var lines = std.mem.SplitIterator(u8, "\n");
        while (lines.next()) |line| {
            try self.assembleLine(line);
        }
    }

    pub fn writeOutput(self: *Self, filename: []const u8) !void {
        const file = std.fs.cwd().createFile(filename, .{}) catch |err| {
            std.debug.print("Could not create output file '{s}': {}\n", .{ filename, err });
            return AssemblerError.WriteError;
        };
        defer file.close();

        try file.writeAll(self.output.items);
        std.debug.print("Generated {} bytes to '{s}'\n", .{ self.output.items.len, filename });
    }

    pub fn getOutput(self: *Self) []const u8 {
        return self.output.items;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <input.s> [output.gb]\n", .{args[0]});
        std.debug.print("Simple GameBoy Assembly Compiler\n", .{});
        std.debug.print("Converts .s assembly files to raw binary data\n\n", .{});
        std.debug.print("Supported instructions:\n", .{});
        std.debug.print("  NOP\n", .{});
        std.debug.print("  LD r,n / LD r,r / LD rr,nn\n", .{});
        std.debug.print("  INC r / DEC r / INC rr / DEC rr\n", .{});
        std.debug.print("  ADD A,r / ADD A,n\n", .{});
        std.debug.print("  JP nn / JP cc,nn / JR n / JR cc,n\n", .{});
        std.debug.print("  CALL nn / RET\n", .{});
        std.debug.print("  PUSH rr / POP rr\n", .{});
        std.debug.print("\nNumber formats: 123 (decimal), 0xFF/$FF (hex), 0b1010/%1010 (binary)\n", .{});
        return;
    }

    const input_file = args[1];
    const output_file = if (args.len >= 3) args[2] else "output.gb";

    var assembler = Assembler.init(allocator);
    defer assembler.deinit();

    assembler.assembleFile(input_file) catch |err| {
        std.debug.print("Assembly failed: {}\n", .{err});
        return;
    };

    try assembler.writeOutput(output_file);

    // Print hex dump of output for verification
    const output = assembler.getOutput();
    if (output.len > 0) {
        std.debug.print("\nHex dump:\n");
        for (output, 0..) |byte, i| {
            if (i % 16 == 0) {
                std.debug.print("\n{:04X}: ", .{i});
            }
            std.debug.print("{:02X} ", .{byte});
        }
        std.debug.print("\n");
    }
}
