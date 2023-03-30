import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

// Port of sdat2img.py to Dart.
// https://github.com/xpirt/sdat2img/blob/master/sdat2img.py

class Range {
  final int begin;
  final int end;
  const Range(this.begin, this.end);
}

class TransferCommand {
  final String command;
  final List<Range> blocks;

  const TransferCommand({
    required this.command,
    required this.blocks,
  });
}

class _TransferListInfo {
  final int version;
  final int newBlocks;
  final List<TransferCommand> commands;
  static const List<String> _validCommands = ["erase", "new", "zero"];

  _TransferListInfo._(this.version, this.newBlocks, this.commands);

  static Future<_TransferListInfo> parse(File transferList) async {
    List<String> lines = await transferList.readAsLines();
    int version = int.parse(lines[0]);
    int newBlocks = int.parse(lines[1]);
    List<TransferCommand> commands = [];

    for (int i = (version >= 2) ? 4 : 2; i < lines.length; i++) {
      // Format: cmd len,block-begin,block-end,block-begin,block-end,...
      String cmd = lines[i].split(' ')[0];
      if (!_validCommands.contains(cmd)) {
        if (int.tryParse(cmd) != null) continue;
        print("Bad command $cmd");
        throw "Bad command";
      }

      List<String> strArgs = (lines[i].split(' ')[1]).split(',');
      List<int> args = strArgs.map((e) => int.parse(e)).toList();
      if (args.length - 1 != (args[0])) {
        print("Bad command args $cmd (${args.length} vs ${args[0]})");
        throw "Invalid length";
      }

      args.removeAt(0);
      List<Range> blocks = [];
      for (int i = 0; i < args.length; i += 2) {
        blocks.add(
          Range(args[i], args[i + 1]),
        );
      }

      commands.add(TransferCommand(
        blocks: blocks,
        command: cmd,
      ));
    }

    return _TransferListInfo._(version, newBlocks, commands);
  }
}

class SDat2Img {
  final File transferList;
  final File newFile;
  final File outputFile;
  static const int blockSize = 4096;

  SDat2Img({
    required this.transferList,
    required this.newFile,
    required this.outputFile,
  });

  Future<Uint8List> _readRange(File file, int from, int to) async {
    var s = file.openRead(from, to);
    Uint8List ret = Uint8List(to - from + 1);
    Completer c = Completer();
    int done = 0;
    s.listen(
      (data) {
        ret.setRange(done, done + data.length, data);
        done += data.length;
      },
      onDone: () => c.complete(),
      onError: (e, st) => c.completeError(e, st),
    );
    await c.future;
    return ret;
  }

  // TODO: fix RAM eater...
  Future<void> convert() async {
    _TransferListInfo info = await _TransferListInfo.parse(transferList);
    IOSink io = outputFile.openWrite();
    int length = 0;
    for (var cmd in info.commands) {
      if (cmd.command != "new") continue;
      for (var block in cmd.blocks) {
        if (length < ((block.end + 1) * blockSize)) {
          length = (block.end + 1) * blockSize;
        }
      }
    }

    Uint8List buffer = Uint8List(length);
    for (var cmd in info.commands) {
      if (cmd.command != "new") {
        print("Skipping ${cmd.command} command...");
        continue;
      }

      for (var block in cmd.blocks) {
        print(
          "Copying ${block.end - block.begin + 1} blocks from ${block.begin} to ${block.end}...",
        );
        var data = await _readRange(
          newFile,
          block.begin * blockSize,
          block.end * blockSize,
        );
        buffer.setRange(
          block.begin * blockSize,
          block.end * blockSize,
          data,
        );
      }
    }

    print("[0/3] Starting to write data...\u001B[1;F");
    io.add(buffer);
    print("[1/3] Flushing data to disk... \u001B[1;F");
    await io.flush();
    print("[2/3] Closing stream...        \u001B[1;F");
    await io.close();
    print("[3/3] Done!                    ");
  }
}
