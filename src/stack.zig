/// A stack of a fixed size, requiring no heap allocation.
pub fn Stack(comptime T: type, comptime size: comptime_int) type {
    return struct {
        data: [size]T,
        stack_pointer: usize,

        pub const Error = error{
            StackFull,
            StackEmpty,
        };

        pub fn init() Stack(T, size) {
            return Stack(T, size){ .data = undefined, .stack_pointer = 0 };
        }

        pub fn push(self: *Stack(T, size), value: T) Error!void {
            if (self.stack_pointer == size) return error.StackFull;
            self.stack_pointer += 1;
            self.data[self.stack_pointer] = value;
        }

        pub fn pop(self: *Stack(T, size)) Error!T {
            if (self.stack_pointer == 0) return error.StackEmpty;
            const v = self.data[self.stack_pointer];
            self.stack_pointer -= 1;
            return v;
        }
    };
}
