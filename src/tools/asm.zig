//! GameBoy (LR35902) assembler.
//!
//! Works at comptime (tests embed programs inline) and at runtime (the CLI in
//! utils/asm_cli.zig). No allocator: the caller supplies the output buffer.
//!
//! The opcode table below is *generated* from the encoding rules rather than
//! hand-listed, mirroring how instruction.zig builds its dispatch table. See
//! tests/asm.zig for a cross-check that it stays in sync with the emulator.
//!
//! Syntax (a subset of RGBDS, also accepting the older `0x` / `(...)` spelling):
//!
//!     ; comment
//!     label:              global label
//!     .org $0100          set the address labels resolve against
//!     name equ 5          constant
//!     db 1, 2, $ff        raw bytes
//!     dw $1234            raw words (little-endian)
//!     ds 16               reserve N zero bytes
//!     LD HL, label + 2    instructions; operands may be expressions

const std = @import("std");

pub const Result = struct {
    /// Address the first emitted byte is intended to live at.
    origin: u16,
    /// Number of bytes written to the output buffer.
    len: usize,
};

pub const Error = error{
    UnknownInstruction,
    UnknownSymbol,
    BadExpression,
    BadDirective,
    DuplicateSymbol,
    JumpOutOfRange,
    ValueOutOfRange,
    BackwardOrigin,
    TooManySymbols,
    OutputTooLarge,
};

/// Failure detail. `msg` is a fixed buffer so this works at comptime too.
pub const Diag = struct {
    line: usize = 0,
    buf: [160]u8 = undefined,
    len: usize = 0,

    pub fn msg(self: *const Diag) []const u8 {
        return self.buf[0..self.len];
    }

    fn set(self: *Diag, line: usize, comptime fmt: []const u8, args: anytype) void {
        self.line = line;
        const written = std.fmt.bufPrint(&self.buf, fmt, args) catch self.buf[0..];
        self.len = written.len;
    }
};

// ---------------------------------------------------------------------------
// Instruction table
// ---------------------------------------------------------------------------

/// The immediate an instruction carries after its opcode byte.
pub const Imm = enum {
    none,
    /// Unsigned byte.
    u8,
    /// Signed byte (ADD SP, LD HL,SP+).
    i8,
    /// Little-endian word.
    u16,
    /// Signed byte encoding (target - pc_after_instruction).
    rel,

    fn size(self: Imm) usize {
        return switch (self) {
            .none => 0,
            .u8, .i8, .rel => 1,
            .u16 => 2,
        };
    }
};

const Entry = struct {
    /// Canonical form, e.g. "LD HL,u16". Operands are comma-separated with no spaces.
    form: []const u8,
    op: u8,
    /// Instruction is in the 0xCB-prefixed page.
    cb: bool = false,
    imm: Imm = .none,
};

/// Register operands in GameBoy encoding order.
const R8 = [_][]const u8{ "B", "C", "D", "E", "H", "L", "(HL)", "A" };
/// ALU operations in encoding order (0x80 + op<<3).
const ALU = [_][]const u8{ "ADD", "ADC", "SUB", "SBC", "AND", "XOR", "OR", "CP" };
/// Branch conditions in encoding order.
const CC = [_][]const u8{ "NZ", "Z", "NC", "C" };
/// CB-page shift/rotate operations in encoding order.
const CB_OPS = [_][]const u8{ "RLC", "RRC", "RL", "RR", "SLA", "SRA", "SWAP", "SRL" };
/// 16-bit register groups.
const R16_SP = [_][]const u8{ "BC", "DE", "HL", "SP" };
const R16_AF = [_][]const u8{ "BC", "DE", "HL", "AF" };

pub const TABLE: []const Entry = blk: {
    @setEvalBranchQuota(200_000);
    var t: []const Entry = &.{};

    // LD r, r'  (0x40 + dst<<3 + src), with 0x76 carved out for HALT.
    for (R8, 0..) |dst, d| {
        for (R8, 0..) |src, s| {
            const op = 0x40 + (d << 3) + s;
            if (op == 0x76) continue;
            t = t ++ &[_]Entry{.{
                .form = std.fmt.comptimePrint("LD {s},{s}", .{ dst, src }),
                .op = op,
            }};
        }
    }

    // ALU A, r  /  ALU A, u8  (both also accepted without the explicit A).
    for (ALU, 0..) |alu, a| {
        for (R8, 0..) |src, s| {
            const op = 0x80 + (a << 3) + s;
            t = t ++ &[_]Entry{
                .{ .form = std.fmt.comptimePrint("{s} A,{s}", .{ alu, src }), .op = op },
                .{ .form = std.fmt.comptimePrint("{s} {s}", .{ alu, src }), .op = op },
            };
        }
        const op_imm = 0xC6 + (a << 3);
        t = t ++ &[_]Entry{
            .{ .form = std.fmt.comptimePrint("{s} A,u8", .{alu}), .op = op_imm, .imm = .u8 },
            .{ .form = std.fmt.comptimePrint("{s} u8", .{alu}), .op = op_imm, .imm = .u8 },
        };
    }

    // INC/DEC r, LD r, u8
    for (R8, 0..) |r, i| {
        t = t ++ &[_]Entry{
            .{ .form = std.fmt.comptimePrint("INC {s}", .{r}), .op = 0x04 + (i << 3) },
            .{ .form = std.fmt.comptimePrint("DEC {s}", .{r}), .op = 0x05 + (i << 3) },
            .{ .form = std.fmt.comptimePrint("LD {s},u8", .{r}), .op = 0x06 + (i << 3), .imm = .u8 },
        };
    }

    // 16-bit register ops.
    for (R16_SP, 0..) |rr, i| {
        t = t ++ &[_]Entry{
            .{ .form = std.fmt.comptimePrint("LD {s},u16", .{rr}), .op = 0x01 + (i << 4), .imm = .u16 },
            .{ .form = std.fmt.comptimePrint("INC {s}", .{rr}), .op = 0x03 + (i << 4) },
            .{ .form = std.fmt.comptimePrint("DEC {s}", .{rr}), .op = 0x0B + (i << 4) },
            .{ .form = std.fmt.comptimePrint("ADD HL,{s}", .{rr}), .op = 0x09 + (i << 4) },
        };
    }
    for (R16_AF, 0..) |rr, i| {
        t = t ++ &[_]Entry{
            .{ .form = std.fmt.comptimePrint("PUSH {s}", .{rr}), .op = 0xC5 + (i << 4) },
            .{ .form = std.fmt.comptimePrint("POP {s}", .{rr}), .op = 0xC1 + (i << 4) },
        };
    }

    // Conditional control flow.
    for (CC, 0..) |cc, i| {
        t = t ++ &[_]Entry{
            .{ .form = std.fmt.comptimePrint("JR {s},r8", .{cc}), .op = 0x20 + (i << 3), .imm = .rel },
            .{ .form = std.fmt.comptimePrint("JP {s},u16", .{cc}), .op = 0xC2 + (i << 3), .imm = .u16 },
            .{ .form = std.fmt.comptimePrint("CALL {s},u16", .{cc}), .op = 0xC4 + (i << 3), .imm = .u16 },
            .{ .form = std.fmt.comptimePrint("RET {s}", .{cc}), .op = 0xC0 + (i << 3) },
        };
    }

    // RST n
    for (0..8) |i| {
        t = t ++ &[_]Entry{
            .{ .form = std.fmt.comptimePrint("RST {X:0>2}H", .{i * 8}), .op = 0xC7 + (i << 3) },
            .{ .form = std.fmt.comptimePrint("RST ${X:0>2}", .{i * 8}), .op = 0xC7 + (i << 3) },
        };
    }

    // CB page: shifts/rotates, then BIT/RES/SET.
    for (CB_OPS, 0..) |cbop, o| {
        for (R8, 0..) |r, i| {
            t = t ++ &[_]Entry{.{
                .form = std.fmt.comptimePrint("{s} {s}", .{ cbop, r }),
                .op = (o << 3) + i,
                .cb = true,
            }};
        }
    }
    for ([_][]const u8{ "BIT", "RES", "SET" }, [_]u8{ 0x40, 0x80, 0xC0 }) |name, base| {
        for (0..8) |b| {
            for (R8, 0..) |r, i| {
                t = t ++ &[_]Entry{.{
                    .form = std.fmt.comptimePrint("{s} {d},{s}", .{ name, b, r }),
                    .op = base + (b << 3) + i,
                    .cb = true,
                }};
            }
        }
    }

    // Everything that doesn't follow a family pattern.
    t = t ++ &[_]Entry{
        .{ .form = "NOP", .op = 0x00 },
        .{ .form = "STOP", .op = 0x10 },
        .{ .form = "HALT", .op = 0x76 },
        .{ .form = "DI", .op = 0xF3 },
        .{ .form = "EI", .op = 0xFB },
        .{ .form = "RET", .op = 0xC9 },
        .{ .form = "RETI", .op = 0xD9 },
        .{ .form = "DAA", .op = 0x27 },
        .{ .form = "CPL", .op = 0x2F },
        .{ .form = "SCF", .op = 0x37 },
        .{ .form = "CCF", .op = 0x3F },
        .{ .form = "RLCA", .op = 0x07 },
        .{ .form = "RRCA", .op = 0x0F },
        .{ .form = "RLA", .op = 0x17 },
        .{ .form = "RRA", .op = 0x1F },

        .{ .form = "JR r8", .op = 0x18, .imm = .rel },
        .{ .form = "JP u16", .op = 0xC3, .imm = .u16 },
        .{ .form = "JP HL", .op = 0xE9 },
        .{ .form = "JP (HL)", .op = 0xE9 },
        .{ .form = "CALL u16", .op = 0xCD, .imm = .u16 },

        .{ .form = "LD (BC),A", .op = 0x02 },
        .{ .form = "LD (DE),A", .op = 0x12 },
        .{ .form = "LD (HL+),A", .op = 0x22 },
        .{ .form = "LD (HL-),A", .op = 0x32 },
        .{ .form = "LD A,(BC)", .op = 0x0A },
        .{ .form = "LD A,(DE)", .op = 0x1A },
        .{ .form = "LD A,(HL+)", .op = 0x2A },
        .{ .form = "LD A,(HL-)", .op = 0x3A },
        .{ .form = "LD (HL),u8", .op = 0x36, .imm = .u8 },
        .{ .form = "LD (u16),SP", .op = 0x08, .imm = .u16 },
        .{ .form = "LD (u16),A", .op = 0xEA, .imm = .u16 },
        .{ .form = "LD A,(u16)", .op = 0xFA, .imm = .u16 },
        .{ .form = "LD SP,HL", .op = 0xF9 },
        .{ .form = "LD HL,SP+i8", .op = 0xF8, .imm = .i8 },
        .{ .form = "ADD SP,i8", .op = 0xE8, .imm = .i8 },

        // High-RAM accessors, in both the RGBDS and the (FF00+n) spelling.
        .{ .form = "LDH (u8),A", .op = 0xE0, .imm = .u8 },
        .{ .form = "LDH A,(u8)", .op = 0xF0, .imm = .u8 },
        .{ .form = "LD (FF00+u8),A", .op = 0xE0, .imm = .u8 },
        .{ .form = "LD A,(FF00+u8)", .op = 0xF0, .imm = .u8 },
        .{ .form = "LD (C),A", .op = 0xE2 },
        .{ .form = "LD A,(C)", .op = 0xF2 },
        .{ .form = "LD (FF00+C),A", .op = 0xE2 },
        .{ .form = "LD A,(FF00+C)", .op = 0xF2 },
        .{ .form = "LDH (C),A", .op = 0xE2 },
        .{ .form = "LDH A,(C)", .op = 0xF2 },
    };

    break :blk t;
};

fn lookup(form: []const u8) ?Entry {
    for (TABLE) |e| {
        if (std.mem.eql(u8, e.form, form)) return e;
    }
    return null;
}

/// Immediate width (in bytes) the assembler associates with a base-page opcode,
/// or null if no form emits it. Used by the cross-check test against the emulator.
pub fn immWidthForOpcode(op: u8) ?usize {
    for (TABLE) |e| {
        if (!e.cb and e.op == op) return e.imm.size();
    }
    return null;
}

// ---------------------------------------------------------------------------
// Symbols
// ---------------------------------------------------------------------------

const MAX_SYMBOLS = 256;

const Symbols = struct {
    names: [MAX_SYMBOLS][]const u8 = undefined,
    values: [MAX_SYMBOLS]i32 = undefined,
    count: usize = 0,

    fn get(self: *const Symbols, name: []const u8) ?i32 {
        for (0..self.count) |i| {
            if (eqlIgnoreCase(self.names[i], name)) return self.values[i];
        }
        return null;
    }

    fn put(self: *Symbols, name: []const u8, value: i32) Error!void {
        for (0..self.count) |i| {
            if (eqlIgnoreCase(self.names[i], name)) {
                // Pass 2 re-defines what pass 1 recorded; that is expected.
                self.values[i] = value;
                return;
            }
        }
        if (self.count == MAX_SYMBOLS) return Error.TooManySymbols;
        self.names[self.count] = name;
        self.values[self.count] = value;
        self.count += 1;
    }
};

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toUpper(ca) != std.ascii.toUpper(cb)) return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// Expressions
// ---------------------------------------------------------------------------

/// Evaluates `a + b - c` chains over integer literals and symbols.
fn evalExpr(expr: []const u8, syms: *const Symbols) Error!i32 {
    var acc: i32 = 0;
    var negate = false;
    var i: usize = 0;
    var term_start: usize = 0;
    var have_term = false;

    while (i <= expr.len) : (i += 1) {
        const at_end = i == expr.len;
        const c = if (at_end) '+' else expr[i];

        if (!at_end and c != '+' and c != '-') {
            if (!have_term) {
                term_start = i;
                have_term = true;
            }
            continue;
        }

        if (have_term) {
            const term = std.mem.trim(u8, expr[term_start..i], " \t");
            if (term.len == 0) return Error.BadExpression;
            const value = try evalTerm(term, syms);
            acc = if (negate) acc - value else acc + value;
            have_term = false;
        } else if (!at_end) {
            // A leading sign, e.g. "-2".
            if (acc != 0) return Error.BadExpression;
        }

        if (!at_end) negate = (c == '-');
    }

    return acc;
}

fn evalTerm(term: []const u8, syms: *const Symbols) Error!i32 {
    if (term.len == 0) return Error.BadExpression;

    if (term[0] == '$') {
        return std.fmt.parseInt(i32, term[1..], 16) catch Error.BadExpression;
    }
    if (term.len > 2 and term[0] == '0' and (term[1] == 'x' or term[1] == 'X')) {
        return std.fmt.parseInt(i32, term[2..], 16) catch Error.BadExpression;
    }
    if (term[0] == '%') {
        return std.fmt.parseInt(i32, term[1..], 2) catch Error.BadExpression;
    }
    if (std.ascii.isDigit(term[0])) {
        return std.fmt.parseInt(i32, term, 10) catch Error.BadExpression;
    }
    if (term[0] == '\'' and term.len == 3 and term[2] == '\'') {
        return term[1];
    }
    return syms.get(term) orelse Error.UnknownSymbol;
}

// ---------------------------------------------------------------------------
// Line parsing
// ---------------------------------------------------------------------------

const MAX_OPERANDS = 3;

const Line = struct {
    label: ?[]const u8 = null,
    /// Uppercased mnemonic or directive.
    head: ?[]const u8 = null,
    /// Raw (trimmed) text after the mnemonic.
    rest: []const u8 = "",
};

fn stripComment(raw: []const u8) []const u8 {
    var i: usize = 0;
    var in_char = false;
    while (i < raw.len) : (i += 1) {
        if (raw[i] == '\'') in_char = !in_char;
        if (!in_char and raw[i] == ';') return raw[0..i];
    }
    return raw;
}

fn splitLine(raw: []const u8) Line {
    var text = std.mem.trim(u8, stripComment(raw), " \t\r");
    var out = Line{};

    if (std.mem.indexOfScalar(u8, text, ':')) |colon| {
        out.label = std.mem.trim(u8, text[0..colon], " \t");
        text = std.mem.trim(u8, text[colon + 1 ..], " \t");
    }
    if (text.len == 0) return out;

    const sp = std.mem.indexOfAny(u8, text, " \t") orelse text.len;
    out.head = text[0..sp];
    out.rest = std.mem.trim(u8, text[sp..], " \t");
    return out;
}

/// Normalizes an operand list: uppercased, spaces removed, `[]` rewritten to `()`.
fn canonOperands(rest: []const u8, buf: []u8) Error![]const u8 {
    var n: usize = 0;
    for (rest) |c| {
        if (c == ' ' or c == '\t') continue;
        if (n == buf.len) return Error.BadExpression;
        buf[n] = switch (c) {
            '[' => '(',
            ']' => ')',
            else => std.ascii.toUpper(c),
        };
        n += 1;
    }
    return buf[0..n];
}

/// True if `tok` is a register/condition literal rather than an expression.
fn isRegisterToken(tok: []const u8) bool {
    const fixed = [_][]const u8{
        "A",  "B",     "C",     "D",      "E",      "H",     "L",
        "AF", "BC",    "DE",    "HL",     "SP",     "(BC)",  "(DE)",
        "HL", "(HL)",  "(HL+)", "(HL-)",  "(C)",    "NZ",    "NC",
        "Z",  "SP+I8", "(FF00+C)",
    };
    for (fixed) |f| {
        if (std.mem.eql(u8, f, tok)) return true;
    }
    return false;
}

/// Result of matching a source line against the instruction table.
const Matched = struct {
    entry: Entry,
    /// Text of the immediate operand, if the instruction takes one.
    expr: []const u8,
};

/// Builds the canonical form for a line and finds its table entry.
///
/// The immediate's width is not known until the instruction is identified, so
/// the numeric operand is substituted with each placeholder in turn and the one
/// that matches the table wins. A given mnemonic+shape admits exactly one width.
fn matchInstruction(mnemonic: []const u8, ops: []const u8, form_buf: []u8) Error!Matched {
    var mnem_upper: [8]u8 = undefined;
    if (mnemonic.len > mnem_upper.len) return Error.UnknownInstruction;
    for (mnemonic, 0..) |c, i| mnem_upper[i] = std.ascii.toUpper(c);
    const mnem = mnem_upper[0..mnemonic.len];

    if (ops.len == 0) {
        const form = std.fmt.bufPrint(form_buf, "{s}", .{mnem}) catch return Error.UnknownInstruction;
        return .{ .entry = lookup(form) orelse return Error.UnknownInstruction, .expr = "" };
    }

    // Split operands and locate the one that is an expression (at most one).
    var toks: [MAX_OPERANDS][]const u8 = undefined;
    var ntok: usize = 0;
    var it = std.mem.splitScalar(u8, ops, ',');
    while (it.next()) |tok| {
        if (ntok == MAX_OPERANDS) return Error.UnknownInstruction;
        toks[ntok] = tok;
        ntok += 1;
    }

    // Try the operands verbatim first. This is what matches register-only forms
    // ("LD A,B"), and also the forms whose operand is a literal rather than an
    // expression: "BIT 7,(HL)", "RST 38H".
    if (buildForm(form_buf, mnem, toks[0..ntok], null, "")) |literal| {
        if (lookup(literal)) |e| return .{ .entry = e, .expr = "" };
    } else |_| {}

    var expr_idx: ?usize = null;
    for (0..ntok) |i| {
        if (!isRegisterToken(toks[i])) {
            if (expr_idx != null) return Error.UnknownInstruction;
            expr_idx = i;
        }
    }
    if (expr_idx == null) return Error.UnknownInstruction;


    const idx = expr_idx.?;
    const tok = toks[idx];

    // Peel the shape off the expression operand: (expr), SP+expr, or bare expr.
    var shape: []const u8 = "";
    var expr: []const u8 = tok;
    if (tok.len >= 2 and tok[0] == '(' and tok[tok.len - 1] == ')') {
        expr = tok[1 .. tok.len - 1];
        shape = "()";
        if (std.mem.startsWith(u8, expr, "FF00+")) {
            expr = expr["FF00+".len..];
            shape = "(FF00+)";
        }
    } else if (std.mem.startsWith(u8, tok, "SP+")) {
        expr = tok["SP+".len..];
        shape = "SP+";
    }

    if (expr.len == 0) return Error.UnknownInstruction;

    for ([_][]const u8{ "u8", "u16", "r8", "i8" }) |ph| {
        var sub_buf: [16]u8 = undefined;
        const sub = placeholder(shape, ph, &sub_buf);
        const form = buildForm(form_buf, mnem, toks[0..ntok], idx, sub) catch continue;
        if (lookup(form)) |e| return .{ .entry = e, .expr = expr };
    }
    return Error.UnknownInstruction;
}

/// Wraps a width placeholder in the operand's shape, e.g. "()" + "u16" -> "(U16)".
fn placeholder(shape: []const u8, width: []const u8, buf: []u8) []const u8 {
    const prefix = if (std.mem.eql(u8, shape, "()"))
        "("
    else if (std.mem.eql(u8, shape, "(FF00+)"))
        "(FF00+"
    else if (std.mem.eql(u8, shape, "SP+"))
        "SP+"
    else
        "";
    const suffix = if (std.mem.eql(u8, shape, "()") or std.mem.eql(u8, shape, "(FF00+)")) ")" else "";

    var n: usize = 0;
    for (prefix) |c| {
        buf[n] = c;
        n += 1;
    }
    // Widths stay lowercase to match the placeholders used in TABLE forms.
    for (width) |c| {
        buf[n] = c;
        n += 1;
    }
    for (suffix) |c| {
        buf[n] = c;
        n += 1;
    }
    return buf[0..n];
}

fn buildForm(buf: []u8, mnem: []const u8, toks: []const []const u8, sub_idx: ?usize, sub: []const u8) Error![]const u8 {
    var n: usize = 0;

    const push = struct {
        fn f(dst: []u8, at: *usize, text: []const u8) Error!void {
            if (at.* + text.len > dst.len) return Error.UnknownInstruction;
            @memcpy(dst[at.*..][0..text.len], text);
            at.* += text.len;
        }
    }.f;

    try push(buf, &n, mnem);
    try push(buf, &n, " ");
    for (toks, 0..) |tok, i| {
        if (i > 0) try push(buf, &n, ",");
        if (sub_idx != null and sub_idx.? == i) {
            try push(buf, &n, sub);
        } else {
            try push(buf, &n, tok);
        }
    }
    return buf[0..n];
}

// ---------------------------------------------------------------------------
// Assembly
// ---------------------------------------------------------------------------

/// Assembles `src` into `out`. Two passes: the first records label addresses,
/// the second emits bytes with all symbols resolved.
pub fn assembleBuf(src: []const u8, out: []u8, diag: *Diag) Error!Result {
    var syms = Symbols{};
    var origin: u16 = 0;

    _ = try run(src, null, &syms, &origin, diag);

    var origin2 = origin;
    const len = try run(src, out, &syms, &origin2, diag);
    return .{ .origin = origin, .len = len };
}

/// One pass. When `out` is null this is the sizing/label pass and expressions
/// that reference not-yet-seen labels are tolerated.
fn run(src: []const u8, out: ?[]u8, syms: *Symbols, origin: *u16, diag: *Diag) Error!usize {
    const emitting = out != null;
    var pc: i32 = origin.*;
    var written: usize = 0;
    var origin_seen = false;
    var lineno: usize = 0;

    var lines = std.mem.splitScalar(u8, src, '\n');
    while (lines.next()) |raw| {
        lineno += 1;
        const line = splitLine(raw);

        if (line.label) |lbl| {
            if (lbl.len > 0 and !std.mem.eql(u8, lbl, "")) {
                syms.put(lbl, pc) catch |e| {
                    diag.set(lineno, "cannot define label '{s}'", .{lbl});
                    return e;
                };
            }
        }

        const head = line.head orelse continue;

        // --- directives ---
        if (isDirective(head, "org")) {
            const target = evalExpr(line.rest, syms) catch |e| {
                diag.set(lineno, "bad .org expression '{s}'", .{line.rest});
                return e;
            };
            if (!origin_seen and written == 0) {
                origin.* = @intCast(target & 0xFFFF);
                pc = target;
                origin_seen = true;
            } else {
                if (target < pc) {
                    diag.set(lineno, ".org moves backwards, from ${X:0>4} to ${X:0>4}", .{ @as(u32, @intCast(pc)), @as(u32, @intCast(target)) });
                    return Error.BackwardOrigin;
                }
                const pad: usize = @intCast(target - pc);
                if (emitting) try fill(out.?, &written, pad, 0, diag, lineno);
                pc = target;
            }
            continue;
        }
        if (isDirective(head, "db") or isDirective(head, "byte")) {
            var it = std.mem.splitScalar(u8, line.rest, ',');
            while (it.next()) |item| {
                const t = std.mem.trim(u8, item, " \t");
                if (t.len == 0) continue;
                const v = if (emitting) try evalOrFail(t, syms, diag, lineno) else 0;
                if (emitting) try emit(out.?, &written, @intCast(v & 0xFF), diag, lineno);
                pc += 1;
            }
            continue;
        }
        if (isDirective(head, "dw") or isDirective(head, "word")) {
            var it = std.mem.splitScalar(u8, line.rest, ',');
            while (it.next()) |item| {
                const t = std.mem.trim(u8, item, " \t");
                if (t.len == 0) continue;
                const v = if (emitting) try evalOrFail(t, syms, diag, lineno) else 0;
                if (emitting) {
                    try emit(out.?, &written, @intCast(v & 0xFF), diag, lineno);
                    try emit(out.?, &written, @intCast((v >> 8) & 0xFF), diag, lineno);
                }
                pc += 2;
            }
            continue;
        }
        if (isDirective(head, "ds") or isDirective(head, "space")) {
            const n = evalExpr(line.rest, syms) catch |e| {
                diag.set(lineno, "bad reserve size '{s}'", .{line.rest});
                return e;
            };
            if (n < 0) {
                diag.set(lineno, "negative reserve size", .{});
                return Error.BadDirective;
            }
            if (emitting) try fill(out.?, &written, @intCast(n), 0, diag, lineno);
            pc += n;
            continue;
        }
        // `name equ expr`
        if (line.label == null and std.mem.indexOfAny(u8, line.rest, " \t") != null) {
            const sp = std.mem.indexOfAny(u8, line.rest, " \t").?;
            const kw = line.rest[0..sp];
            if (eqlIgnoreCase(kw, "equ")) {
                const v = evalExpr(std.mem.trim(u8, line.rest[sp..], " \t"), syms) catch |e| {
                    if (!emitting) continue;
                    diag.set(lineno, "bad equ expression", .{});
                    return e;
                };
                syms.put(head, v) catch |e| {
                    diag.set(lineno, "cannot define '{s}'", .{head});
                    return e;
                };
                continue;
            }
        }

        // --- instruction ---
        var ops_buf: [96]u8 = undefined;
        const ops = canonOperands(line.rest, &ops_buf) catch |e| {
            diag.set(lineno, "operand list too long", .{});
            return e;
        };

        var form_buf: [96]u8 = undefined;
        const m = matchInstruction(head, ops, &form_buf) catch |e| {
            diag.set(lineno, "unknown instruction '{s} {s}'", .{ head, line.rest });
            return e;
        };

        const size: i32 = @intCast(1 + @as(usize, if (m.entry.cb) 1 else 0) + m.entry.imm.size());

        if (emitting) {
            if (m.entry.cb) try emit(out.?, &written, 0xCB, diag, lineno);
            try emit(out.?, &written, m.entry.op, diag, lineno);

            switch (m.entry.imm) {
                .none => {},
                .u8, .i8 => {
                    const v = try evalOrFail(m.expr, syms, diag, lineno);
                    if (v < -128 or v > 255) {
                        diag.set(lineno, "value {d} does not fit in a byte", .{v});
                        return Error.ValueOutOfRange;
                    }
                    try emit(out.?, &written, @intCast(v & 0xFF), diag, lineno);
                },
                .u16 => {
                    const v = try evalOrFail(m.expr, syms, diag, lineno);
                    if (v < -32768 or v > 65535) {
                        diag.set(lineno, "value {d} does not fit in a word", .{v});
                        return Error.ValueOutOfRange;
                    }
                    try emit(out.?, &written, @intCast(v & 0xFF), diag, lineno);
                    try emit(out.?, &written, @intCast((v >> 8) & 0xFF), diag, lineno);
                },
                .rel => {
                    const target = try evalOrFail(m.expr, syms, diag, lineno);
                    const delta = target - (pc + size);
                    if (delta < -128 or delta > 127) {
                        diag.set(lineno, "relative jump out of range ({d} bytes; must be -128..127)", .{delta});
                        return Error.JumpOutOfRange;
                    }
                    try emit(out.?, &written, @intCast(delta & 0xFF), diag, lineno);
                },
            }
        }

        pc += size;
    }

    return written;
}

fn isDirective(head: []const u8, name: []const u8) bool {
    if (eqlIgnoreCase(head, name)) return true;
    if (head.len > 1 and head[0] == '.' and eqlIgnoreCase(head[1..], name)) return true;
    return false;
}

fn evalOrFail(expr: []const u8, syms: *const Symbols, diag: *Diag, lineno: usize) Error!i32 {
    return evalExpr(expr, syms) catch |e| {
        diag.set(lineno, "cannot resolve '{s}'", .{expr});
        return e;
    };
}

fn emit(out: []u8, written: *usize, byte: u8, diag: *Diag, lineno: usize) Error!void {
    if (written.* >= out.len) {
        diag.set(lineno, "output exceeds {d} bytes", .{out.len});
        return Error.OutputTooLarge;
    }
    out[written.*] = byte;
    written.* += 1;
}

fn fill(out: []u8, written: *usize, n: usize, byte: u8, diag: *Diag, lineno: usize) Error!void {
    for (0..n) |_| try emit(out, written, byte, diag, lineno);
}

// ---------------------------------------------------------------------------
// Comptime entry point
// ---------------------------------------------------------------------------

/// Assembles at compile time. A malformed program is a compile error, so bad
/// test fixtures never reach runtime.
pub fn assemble(comptime src: []const u8) []const u8 {
    comptime {
        @setEvalBranchQuota(2_000_000);
        var buf: [4096]u8 = undefined;
        var diag = Diag{};
        const res = assembleBuf(src, &buf, &diag) catch |e| {
            @compileError(std.fmt.comptimePrint(
                "assembly failed on line {d}: {s} ({s})",
                .{ diag.line, diag.msg(), @errorName(e) },
            ));
        };
        const final = buf[0..res.len].*;
        return &final;
    }
}

/// Origin (`.org`) of a comptime-assembled program.
pub fn assembleOrigin(comptime src: []const u8) u16 {
    comptime {
        @setEvalBranchQuota(2_000_000);
        var buf: [4096]u8 = undefined;
        var diag = Diag{};
        const res = assembleBuf(src, &buf, &diag) catch @compileError("assembly failed");
        return res.origin;
    }
}
