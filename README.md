# sdat2img.dart
sdat2img.py port to Dart. Why? Idk.

## Usage
```dart
import 'sdat2img.dart';

void main() async {
  var worker = SDat2Img(
    newFile: File("system.new.dat"),
    transferList: File("system.transfer.list"),
    outputFile: File("system.img"),
  );
  await worker.convert();
}
```

## Problems
Due to Dart's File IO, sdat2img.dart allocates all system.img's size as a temporary buffer.
It eats a lot of RAM.

## Pros
Fully working port of sdat2img.py based on dart:io :)
