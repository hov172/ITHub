#!/usr/bin/env python3
"""Compile and run the app's focused regression checks with Xcode's Swift compiler."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
developer = Path('/Applications/Xcode.app/Contents/Developer')
with tempfile.TemporaryDirectory(prefix='ithub-validation-') as work:
    binary = Path(work) / 'validation'
    sources = sorted(p for p in (root / 'IT Hub').glob('*.swift') if p.name != 'MyApp.swift')
    subprocess.run([str(developer / 'Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'),
        '-sdk', str(developer / 'Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'),
        '-target', 'arm64-apple-macosx13.0', '-D', 'ITHUB_SANDBOX',
        '-module-cache-path', str(Path(work) / 'cache'),
        *map(str, sources), str(root / 'Validation/main.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
