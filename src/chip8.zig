const std = @import("std");

const Stack = @import("stack.zig").Stack;

pub const Error = error{
    UnknownOpcode,
    Unimplemented,
};

pub const Chip8 = struct {
    pub const DISPLAY_WIDTH: usize = 64;
    pub const DISPLAY_HEIGHT: usize = 32;
    pub const SPRITE_WIDTH: usize = 8;

    /// The type of Chip-8 system this emulator is emulating.
    pub const SystemType = enum {
        Chip8,
        SuperChip,
        XOChip,
        SuperChipLegacy,
    };

    memory: [4096]u8 = undefined,
    registers: [16]u8,
    address_register: u16,

    program_counter: u16,
    stack: Stack(u16, 16),

    delay_timer: u8,
    sound_timer: u8,
    last_timer_update: i64,

    keys: [16]bool,

    screen: [DISPLAY_HEIGHT][DISPLAY_WIDTH]u1,

    rng: std.rand.Random,
    system: SystemType,

    const LOGGER = std.log.scoped(.chip8);

    /// Initialize and return a new Chip8 emulator with the ROM at the given path
    /// loaded into memory.
    pub fn load(path: []const u8, config: struct { system: SystemType = SystemType.Chip8 }) !Chip8 {
        LOGGER.debug("Loading ROM from path: {s}", .{path});
        var sfc64 = std.rand.Sfc64.init(@bitCast(std.time.milliTimestamp()));
        var chip = Chip8{
            .memory = undefined,
            .registers = [_]u8{0} ** 16,
            .program_counter = 0x200,
            .stack = Stack(u16, 16).init(),
            .delay_timer = 0,
            .sound_timer = 0,
            .last_timer_update = std.time.milliTimestamp(),
            .address_register = undefined,
            .keys = undefined, // TODO
            .screen = std.mem.zeroes([DISPLAY_HEIGHT][DISPLAY_WIDTH]u1),
            .rng = sfc64.random(),
            .system = config.system,
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
        self.decrement_timers();
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
            .call_subroutine => |address| {
                try self.stack.push(self.program_counter);
                self.program_counter = address;
            },
            .return_subroutine => {
                const address = try self.stack.pop();
                self.program_counter = address;
            },
            .skip_if_eq => |params| {
                if (self.registers[params.register] == params.value) self.increment_program_counter();
            },
            .skip_if_ne => |params| {
                if (self.registers[params.register] != params.value) self.increment_program_counter();
            },
            .skip_if_registers_eq => |params| {
                if (self.registers[params.lhs] == self.registers[params.rhs]) self.increment_program_counter();
            },
            .skip_if_registers_ne => |params| {
                if (self.registers[params.lhs] != self.registers[params.rhs]) self.increment_program_counter();
            },
            .set_register => |params| {
                self.registers[params.register] = params.value;
            },
            .or_registers => |params| {
                self.registers[params.lhs] |= self.registers[params.rhs];
                if (self.system == SystemType.Chip8) {
                    self.registers[0xF] = 0;
                }
            },
            .and_registers => |params| {
                self.registers[params.lhs] &= self.registers[params.rhs];
                if (self.system == SystemType.Chip8) {
                    self.registers[0xF] = 0;
                }
            },
            .xor_registers => |params| {
                self.registers[params.lhs] ^= self.registers[params.rhs];
                if (self.system == SystemType.Chip8) {
                    self.registers[0xF] = 0;
                }
            },
            .add => |params| {
                const result = @addWithOverflow(self.registers[params.register], params.value);
                self.registers[params.register] = result[0];
            },
            .add_registers => |params| {
                const result = @addWithOverflow(self.registers[params.lhs], self.registers[params.rhs]);
                self.registers[params.lhs] = result[0];
                self.registers[0xF] = result[1];
            },
            .sub_registers => |params| {
                const result = @subWithOverflow(self.registers[params.lhs], self.registers[params.rhs]);
                self.registers[params.lhs] = result[0];
                self.registers[0xF] = 1 ^ result[1];
            },
            .sub_registers_reverse => |params| {
                const result = @subWithOverflow(self.registers[params.rhs], self.registers[params.lhs]);
                self.registers[params.lhs] = result[0];
                self.registers[0xF] = 1 ^ result[1];
            },
            .shift_right => |params| {
                // We temporarily store the flag because it could be one of the registers
                // in params. If it is, we don't want to overwrite the value before it is used.
                const flag = self.registers[params.rhs] & 0x1;
                self.registers[params.lhs] >>= 1;
                self.registers[0xF] = flag;
            },
            .shift_left => |params| {
                const flag = self.registers[params.lhs] >> 7;
                self.registers[params.lhs] <<= 1;
                self.registers[0xF] = flag;
            },
            .add_to_address_register => |register| {
                self.address_register += self.registers[register];
            },
            .set_address_register => |address| {
                self.address_register = address;
            },
            .set_register_to_register => |params| {
                self.registers[params.lhs] = self.registers[params.rhs];
            },
            .jump_plus_register => |amount| {
                self.program_counter = self.registers[0] + amount;
            },
            .random => |params| {
                self.registers[params.register] = self.rng.int(u8) & params.value;
            },
            .draw => |params| {
                var x = self.registers[params.x];
                var y = self.registers[params.y];
                var height = params.height;

                var sprite = self.memory[self.address_register .. self.address_register + height];
                var collision = self.draw_sprite(x, y, sprite);
                self.registers[0xF] = @intFromBool(collision);
            },
            // The dump and load register instructions have conflicting specifications
            // depending on where you look. Some sources say I should be incremented by
            // X, X+1, or not at all.
            .dump_registers => |register| {
                @memcpy(self.memory[self.address_register .. self.address_register + register + 1], self.registers[0 .. register + 1]);
                if (self.system == SystemType.Chip8) {
                    self.address_register += register + 1;
                }
            },
            .load_registers => |register| {
                @memcpy(self.registers[0 .. register + 1], self.memory[self.address_register .. self.address_register + register + 1]);
                if (self.system == SystemType.Chip8) {
                    self.address_register += register + 1;
                }
            },
            .store_binary_coded_decimal => |register| {
                var d = self.registers[register];
                self.memory[self.address_register] = d / 100;
                self.memory[self.address_register + 1] = (d / 10) % 10;
                self.memory[self.address_register + 2] = d % 10;
            },
            .set_delay_timer => |value| {
                self.delay_timer = value;
            },
            .set_register_to_delay_timer => |register| {
                self.registers[register] = self.delay_timer;
            },
            .set_sound_timer => |value| {
                self.sound_timer = value;
            },
            .skip_if_key_pressed => |register| {
                if (self.keys[self.registers[register]]) self.increment_program_counter();
            },
            .skip_if_key_not_pressed => |register| {
                if (!self.keys[self.registers[register]]) self.increment_program_counter();
            },
            .wait_for_key_press => |register| {
                for (self.keys, 0..) |key, i| {
                    if (key) {
                        self.registers[register] = @truncate(i);
                        return;
                    }
                }
                self.program_counter -= 2; // No key pressed, repeat this instruction.
            },
            .set_address_register_to_sprite => |register| {
                _ = register;
                return error.Unimplemented;
            },
            .ignored => {},
        }
    }

    fn draw_sprite(self: *Chip8, x: u8, y: u8, sprite: []u8) bool {
        LOGGER.debug("Drawing sprite at ({d}, {d}), height: {d}", .{ x, y, sprite.len });
        if (y >= DISPLAY_HEIGHT or x > DISPLAY_WIDTH) {
            LOGGER.debug("Sprite is off the screen. Not drawing.", .{});
            return false;
        }
        var collision = false;
        // TODO: What do we do when the sprite is partially off the screen? This code will clip them, but is that right?
        const y_max = @min(y + sprite.len, DISPLAY_HEIGHT);
        const x_max = @min(x + SPRITE_WIDTH, DISPLAY_WIDTH);
        const sprite_max = @min(y_max - y, sprite.len);
        for (self.screen[y..y_max], y..y_max, sprite[0..sprite_max]) |row, row_index, sprite_row| {
            for (row[x..x_max], x..x_max, 0..x_max - x) |curr_pixel, col_index, shift_amount| {
                const pixel = (sprite_row >> @truncate(7 - shift_amount)) & 1;
                if (pixel == 0) continue;
                if (curr_pixel == 1) collision = true;
                self.screen[row_index][col_index] ^= @truncate(pixel);
            }
        }
        return collision;
    }

    fn decrement_timers(self: *Chip8) void {
        const current_time = std.time.milliTimestamp();
        if (current_time - self.last_timer_update < 16) return;
        LOGGER.debug("Decrementing timers. Delay: {d}, Sound: {d}, Timestamp Diff: {d}", .{ self.delay_timer, self.sound_timer, current_time - self.last_timer_update });
        if (self.sound_timer > 0) self.sound_timer -= 1;
        if (self.delay_timer > 0) self.delay_timer -= 1;
        self.last_timer_update = current_time;
    }

    const Instruction = union(enum) {
        /// Parameters for instructions that operate on a register using some value.
        pub const RegisterValueParams = struct {
            register: u8,
            value: u8,
        };

        /// Parameters for instructions that perform an operation between two registers
        pub const RegisterParams = struct {
            lhs: u8,
            rhs: u8,
        };

        clear_display: void,
        return_subroutine: void,
        jump: u16,
        call_subroutine: u16,
        skip_if_eq: RegisterValueParams,
        skip_if_ne: RegisterValueParams,
        skip_if_registers_eq: RegisterParams,
        set_register: RegisterValueParams,
        add: RegisterValueParams,
        set_register_to_register: RegisterParams,
        or_registers: RegisterParams,
        and_registers: RegisterParams,
        xor_registers: RegisterParams,
        add_registers: RegisterParams,
        sub_registers: RegisterParams,
        shift_right: RegisterParams,
        sub_registers_reverse: RegisterParams,
        shift_left: RegisterParams,
        skip_if_registers_ne: RegisterParams,
        set_address_register: u16,
        jump_plus_register: u16,
        random: RegisterValueParams,
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
        dump_registers: u8,
        load_registers: u8,
        ignored: void, // Catch-all for NOP and other system instructions we can safely ignore.

        /// Parse an Instruction variant and any parameters from an opcode.
        ///
        /// Note: Truncation in this function is safe since we only care about 1 or 2 nibbles of the opcode
        /// for a particular parameter.
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
                0x2 => return Instruction{ .call_subroutine = opcode & 0x0FFF },
                0x3 => return Instruction{ .skip_if_eq = Instruction.parse_register_value(opcode) },
                0x4 => return Instruction{ .skip_if_ne = Instruction.parse_register_value(opcode) },
                0x5 => return Instruction{ .skip_if_registers_eq = Instruction.parse_left_right_register(opcode) },
                0x6 => return Instruction{ .set_register = Instruction.parse_register_value(opcode) },
                0x7 => return Instruction{ .add = Instruction.parse_register_value(opcode) },
                0x8 => {
                    switch (opcode & 0x000F) {
                        0x0 => return Instruction{ .set_register_to_register = Instruction.parse_left_right_register(opcode) },
                        0x1 => return Instruction{ .or_registers = Instruction.parse_left_right_register(opcode) },
                        0x2 => return Instruction{ .and_registers = Instruction.parse_left_right_register(opcode) },
                        0x3 => return Instruction{ .xor_registers = Instruction.parse_left_right_register(opcode) },
                        0x4 => return Instruction{ .add_registers = Instruction.parse_left_right_register(opcode) },
                        0x5 => return Instruction{ .sub_registers = Instruction.parse_left_right_register(opcode) },
                        0x6 => return Instruction{ .shift_right = parse_left_right_register(opcode) },
                        0x7 => return Instruction{ .sub_registers_reverse = Instruction.parse_left_right_register(opcode) },
                        0xE => return Instruction{ .shift_left = parse_left_right_register(opcode) },
                        else => return error.UnknownOpcode,
                    }
                },
                0x9 => return Instruction{ .skip_if_registers_ne = Instruction.parse_left_right_register(opcode) },
                0xA => return Instruction{ .set_address_register = opcode & 0x0FFF },
                0xB => return Instruction{ .jump_plus_register = opcode & 0x0FFF },
                0xC => return Instruction{ .random = Instruction.parse_register_value(opcode) },
                0xD => return Instruction{ .draw = .{
                    .x = @truncate((opcode & 0x0F00) >> 8),
                    .y = @truncate((opcode & 0x00F0) >> 4),
                    .height = @truncate(opcode & 0x000F),
                } },
                0xE => {
                    switch (opcode & 0x00FF) {
                        0x9E => return Instruction{ .skip_if_key_pressed = @truncate((opcode & 0x0F00) >> 8) },
                        0xA1 => return Instruction{ .skip_if_key_not_pressed = @truncate((opcode & 0x0F00) >> 8) },
                        else => return error.UnknownOpcode,
                    }
                },
                0xF => {
                    switch (opcode & 0x00FF) {
                        0x07 => return Instruction{ .set_register_to_delay_timer = @truncate((opcode & 0x0F00) >> 8) },
                        0x0A => return Instruction{ .wait_for_key_press = @truncate((opcode & 0x0F00) >> 8) },
                        0x15 => return Instruction{ .set_delay_timer = @truncate((opcode & 0x0F00) >> 8) },
                        0x18 => return Instruction{ .set_sound_timer = @truncate((opcode & 0x0F00) >> 8) },
                        0x1E => return Instruction{ .add_to_address_register = @truncate((opcode & 0x0F00) >> 8) },
                        0x29 => return Instruction{ .set_address_register_to_sprite = @truncate((opcode & 0x0F00) >> 8) },
                        0x33 => return Instruction{ .store_binary_coded_decimal = @truncate((opcode & 0x0F00) >> 8) },
                        0x55 => return Instruction{ .dump_registers = @truncate((opcode & 0x0F00) >> 8) },
                        0x65 => return Instruction{ .load_registers = @truncate((opcode & 0x0F00) >> 8) },
                        else => return error.UnknownOpcode,
                    }
                },
                else => return error.UnknownOpcode,
            }
        }

        fn parse_register_value(opcode: u16) RegisterValueParams {
            return .{ .register = @truncate(opcode >> 8 & 0x0f), .value = @truncate(opcode) };
        }

        fn parse_left_right_register(opcode: u16) RegisterParams {
            return .{ .lhs = @truncate(opcode >> 8 & 0x0f), .rhs = @truncate(opcode >> 4 & 0x0f) };
        }
    };
};
