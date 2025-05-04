const std = @import("std");
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const LogLevel = enum {
    Debug,
    Info,
    Warning,
    Error,
};

const Sink = struct {
    callback: *const fn (message: []const u8) void,
};

const Logs = struct {
    //     v  --  may not need this
    type: LogLevel,
    message: []const u8,
    pub fn print(this: *const Logs) void {
        std.debug.print("{s}\n", .{this.message});
    }
};

pub const Collection = struct {
    var _logs = std.ArrayList(Logs).init(allocator);
    var _sinks = std.ArrayList(Sink).init(allocator);
    var _mut = std.Thread.Mutex{};
    var _backgroundThread: ?std.Thread = null;
    var _isThreadRunning: bool = false;
    var _systemInfo: []const u8 = "";

    pub fn SystemContext(system: []const u8) void {
        _systemInfo = system;
    }

    pub fn AddSink(sinkToAdd: anytype) void {
        const SinkType = @TypeOf(sinkToAdd);

        if (!@hasDecl(SinkType, "print")) {
            std.debug.print("Sink must have a print function\n", .{});
            return;
        }

        const sink = Sink{
            .callback = &SinkType.print,
        };

        _mut.lock();
        defer _mut.unlock();
        _sinks.append(sink) catch unreachable;
    }

    pub fn InsertInfo(log: []const u8) void {
        const logLevelString = " INFO: ";

        const currentTime = std.time.timestamp();
        var buffer: [64]u8 = undefined;
        const nowToString = std.fmt.bufPrint(&buffer, "{d} ", .{currentTime}) catch "TimeString Error";

        const totalLength = nowToString.len + log.len + logLevelString.len + _systemInfo.len;
        var message = allocator.alloc(u8, totalLength) catch unreachable;
        @memcpy(message[0..nowToString.len], nowToString);
        @memcpy(message[nowToString.len .. nowToString.len + _systemInfo.len], _systemInfo);
        @memcpy(message[nowToString.len + _systemInfo.len .. nowToString.len + _systemInfo.len + logLevelString.len], logLevelString);
        @memcpy(message[nowToString.len + _systemInfo.len + logLevelString.len ..], log);

        _mut.lock();
        defer _mut.unlock();
        _logs.append(Logs{ .type = LogLevel.Info, .message = message }) catch unreachable;
    }

    pub fn InsertError(log: []const u8) void {
        const logLevelString = " ERR: ";

        const currentTime = std.time.timestamp();
        var buffer: [64]u8 = undefined;
        const nowToString = std.fmt.bufPrint(&buffer, "{d} ", .{currentTime}) catch "TimeString Error";

        const totalLength = nowToString.len + log.len + logLevelString.len + _systemInfo.len;
        var message = allocator.alloc(u8, totalLength) catch unreachable;
        @memcpy(message[0..nowToString.len], nowToString);
        @memcpy(message[nowToString.len .. nowToString.len + _systemInfo.len], _systemInfo);
        @memcpy(message[nowToString.len + _systemInfo.len .. nowToString.len + _systemInfo.len + logLevelString.len], logLevelString);
        @memcpy(message[nowToString.len + _systemInfo.len + logLevelString.len ..], log);

        _mut.lock();
        defer _mut.unlock();
        _logs.append(Logs{ .type = LogLevel.Error, .message = message }) catch unreachable;
    }

    pub fn deinit() void {
        stopBackgroundThread();
        _logs.deinit();
    }

    pub fn items() []Logs {
        return _logs.items;
    }

    fn backgroundWrite() void {
        const num_items = _logs.items.len;
        if (num_items == 0) {
            return;
        }
        var i: usize = 0;

        if (_sinks.items.len == 0) {
            return;
        }
        _mut.lock();
        defer _mut.unlock();
        while (i < num_items) : (i += 1) {
            const log = _logs.items[i];
            for (_sinks.items) |sink| {
                sink.callback(log.message);
            }
        }

        var j: usize = num_items;
        while (j > 0) {
            j -= 1;
            _ = _logs.orderedRemove(j);
        }
    }

    fn backgroundThreadFn() void {
        while (_isThreadRunning) {
            backgroundWrite();
            std.time.sleep(1 * std.time.ns_per_s); // Sleep for 1 second
        }
    }

    pub fn startBackgroundThread() !void {
        if (_backgroundThread != null) return;

        _isThreadRunning = true;
        _backgroundThread = try std.Thread.spawn(.{}, backgroundThreadFn, .{});
    }

    pub fn stopBackgroundThread() void {
        if (_backgroundThread == null) return;

        _isThreadRunning = false;
        _backgroundThread.?.join(); // Wait for the thread to exit
        _backgroundThread = null;
    }
};
