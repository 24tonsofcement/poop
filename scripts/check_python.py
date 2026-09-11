import sys, struct
if sys.version_info[:2] != (3, 11) or struct.calcsize("P") != 8:
    raise SystemExit("Python 3.11 x64 required")
