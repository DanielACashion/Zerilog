const std = @import("std");

pub const ConsoleSink = struct {
    pub fn print(message: []const u8) void {
        std.debug.print("{s}\n", .{message});
    }
};

//extension examples, still working on self referencing for changable file locations
//may look into using a buffer to write to then save instead of writing each time
pub const FileSink = struct {
    pathToFile: []const u8,
    pub fn print(message: []const u8) void {
        const pathToFile = "log.txt";
        const file_exists = std.fs.cwd().access(pathToFile, .{});
        const write_file = if (file_exists != error.FileNotFound)
            std.fs.cwd().openFile(
                pathToFile,
                .{ .mode = .write_only, .lock = .exclusive },
            ) catch {
                std.debug.print("Error opening file: {s}\n", .{pathToFile});
                return;
            }
        else
            std.fs.cwd().createFile(
                pathToFile,
                .{},
            ) catch {
                std.debug.print("Error creating file: {s}\n", .{pathToFile});
                return;
            };
        write_file.seekFromEnd(0) catch {
            std.debug.print("Error seeking to end of file\n", .{});
            return;
        };
        defer write_file.close();

        // Write to file
        _ = write_file.write(message) catch {
            std.debug.print("Error writing to file\n", .{});
            return;
        };
    }
};

pub fn main() !void {
    try lib.Collection.startBackgroundThread();
    lib.Collection.AddSink(ConsoleSink{});
    lib.Collection.AddSink(FileSink{ .pathToFile = "log.txt" });
    lib.Collection.SystemContext("ZigInputReader");
    defer lib.Collection.deinit();
    defer std.debug.print("All Done...\n", .{});

    var buffer: [1024]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    while (true) {
        const input = (stdin.readUntilDelimiterOrEof(&buffer, '\n') catch "exit\n") orelse break;

        // Check if user wants to exit
        const trimmed_input = std.mem.trim(u8, input, " \r\n\t");
        if (trimmed_input.len > 0 and std.mem.eql(u8, trimmed_input, "exit")) {
            break;
        }

        // Add input to logs
        lib.Collection.InsertInfo(input);
    }
    std.debug.print("Exiting...\n", .{});
}

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("Zerilog_lib");
