const std = @import("std");

pub const Error = error{
    UnknownOpcode,
    Unimplemented,
};

pub const Chip8 = struct {
    pub const DISPLAY_WIDTH: usize = 64;
    pub const DISPLAY_HEIGHT: usize = 32;
    pub const SPRITE_WIDTH: usize = 8;

    memory: [4096]u8 = undefined,
    registers: [16]u8,
    address_register: u16,

    program_counter: u16,
    stack: std.ArrayList(u16),

    delay_timer: u8,
    sound_timer: u8,

    keys: [16]u8,

    screen: [DISPLAY_HEIGHT][DISPLAY_WIDTH]u1,

    const LOGGER = std.log.scoped(.chip8);

    /// Initialize and return a new Chip8 emulator with the ROM at the given path
    /// loaded into memory.
    pub fn load(path: []const u8) !Chip8 {
        LOGGER.debug("Loading ROM from path: {s}", .{path});
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        var chip = Chip8{
            .memory = undefined,
            .registers = [_]u8{0} ** 16,
            .program_counter = 0x200,
            .stack = std.ArrayList(u16).init(gpa.allocator()),
            .delay_timer = 0,
            .sound_timer = 0,
            .address_register = undefined,
            .keys = undefined, // TODO
            .screen = std.mem.zeroes([DISPLAY_HEIGHT][DISPLAY_WIDTH]u1),
        };

        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var buf_reader = std.io.bufferedReader(file.reader());
        _ = try buf_reader.read(chip.memory[0x200..]);
        LOGGER.debug("Loaded ROM. First byte: {x}", .{chip.memory[0x200]});
        return chip;
    }

    /// Fetch and execute a single opcdode.
    pub fn cycle(self: *Chip8) !void {
        const opcode = self.fetch_opcode();
        const instruction = Instruction.from_opcode(opcode) catch |err| {
            LOGGER.err("Error decoding opcode {x}: {any}", .{ opcode, err });
            return err;
        };
        self.execute(instruction) catch |err| {
            LOGGER.err("Error executing instruction {any}: {any}", .{ instruction, err });
            return err;
        };
    }

    /// Fetch the next opcode from memory.
    fn fetch_opcode(self: *Chip8) u16 {
        const opcode = @as(u16, self.memory[self.program_counter]) << 8 | self.memory[self.program_counter + 1];
        LOGGER.debug("Fetched opcode: {x}", .{opcode});
        self.increment_program_counter();
        return opcode;
    }

    /// Increments the program counter.
    ///
    /// Instructions are 2 bytes long, so we increment the program counter by 2.
    fn increment_program_counter(self: *Chip8) void {
        self.program_counter += 2;
    }

    fn execute(self: *Chip8, instruction: Instruction) !void {
        LOGGER.debug("Executing instruction: {any}", .{instruction});
        switch (instruction) {
            .clear_display => {
                self.screen = std.mem.zeroes([DISPLAY_HEIGHT][DISPLAY_WIDTH]u1);
            },
            .jump => |address| {
                self.program_counter = address;
            },
            .set_register => |params| {
                self.registers[params.register] = params.value;
            },
            .set_address_register => |address| {
                self.address_register = address;
            },
            .draw => |params| {
                var x = self.registers[params.x];
                var y = self.registers[params.y];
                var height = params.height;

                var sprite = self.memory[self.address_register .. self.address_register + height];
                var collision = self.draw_sprite(x, y, sprite);
                self.registers[0xF] = @intFromBool(collision);
            },
            .ignored => {},
            else => return error.Unimplemented,
        }
    }

    fn draw_sprite(self: *Chip8, x: u8, y: u8, sprite: []u8) bool {
        LOGGER.debug("Drawing sprite at ({d}, {d}), height: {d}", .{ x, y, sprite.len });
        var collision = false;
        const y_max = y + sprite.len;
        const x_max = x + SPRITE_WIDTH;
        for (self.screen[y..y_max], y..y_max, sprite) |row, row_index, sprite_row| {
            for (row[x..x_max], x..x_max, 0..8) |curr_pixel, col_index, shift_amount| {
                const pixel = sprite_row >> (@truncate(7 - shift_amount));
                if (pixel == 0) continue;
                if (curr_pixel == 1) collision = true;
                self.screen[row_index][col_index] ^= @truncate(pixel);
            }
        }
        return collision;
    }

    const Instruction = union(enum) {
        clear_display: void,
        return_subroutine: void,
        jump: u16,
        call_subroutine: u16,
        skip_if_eq: struct {
            register: u8,
            value: u8,
        },
        skip_if_ne: struct {
            register: u8,
            value: u8,
        },
        skip_if_registers_eq: struct {
            lhs: u8,
            rhs: u8,
        },
        set_register: struct {
            register: u8,
            value: u8,
        },
        add: struct {
            register: u8,
            value: u8,
        },
        set_register_to_register: struct {
            lhs: u8,
            rhs: u8,
        },
        or_registers: struct {
            lhs: u8,
            rhs: u8,
        },
        and_registers: struct {
            lhs: u8,
            rhs: u8,
        },
        xor_registers: struct {
            lhs: u8,
            rhs: u8,
        },
        add_registers: struct {
            lhs: u8,
            rhs: u8,
        },
        sub_registers: struct {
            lhs: u8,
            rhs: u8,
        },
        shift_right: struct {
            register: u8,
        },
        sub_registers_reverse: struct {
            lhs: u8,
            rhs: u8,
        },
        shift_left: struct {
            register: u8,
        },
        skip_if_registers_ne: struct {
            lhs: u8,
            rhs: u8,
        },
        set_address_register: u16,
        jump_plus_register: u16,
        random: struct {
            register: u8,
            value: u8,
        },
        draw: struct {
            x: u8,
            y: u8,
            height: u8,
        },
        skip_if_key_pressed: u8,
        skip_if_key_not_pressed: u8,
        set_register_to_delay_timer: u8,
        wait_for_key_press: u8,
        set_delay_timer: u8,
        set_sound_timer: u8,
        add_to_address_register: u8,
        set_address_register_to_sprite: u8,
        store_binary_coded_decimal: u8,
        store_registers: u8,
        read_registers: u8,
        ignored: void, // Catch-all for NOP and other system instructions we can safely ignore.

        fn from_opcode(opcode: u16) !Instruction {
            switch ((opcode & 0xF000) >> 12) {
                0x0 => {
                    switch (opcode & 0x00FF) {
                        0x00 => return Instruction{ .ignored = {} },
                        0xE0 => return Instruction{ .clear_display = {} },
                        0xEE => return Instruction{ .return_subroutine = {} },
                        else => return error.UnknownOpcode,
                    }
                },
                0x1 => return Instruction{ .jump = opcode & 0x0FFF },
                0x6 => return Instruction{ .set_register = .{ .register = @truncate(opcode >> 8 & 0x0f), .value = @truncate(opcode) } },
                0xA => return Instruction{ .set_address_register = opcode & 0x0FFF },
                0xD => return Instruction{ .draw = .{
                    .x = @truncate((opcode & 0x0F00) >> 8),
                    .y = @truncate((opcode & 0x00F0) >> 4),
                    .height = @truncate(opcode & 0x000F),
                } },
                else => return error.UnknownOpcode,
            }
        }
    };
};
