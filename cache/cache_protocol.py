import struct

UDP_PORT        = 1234


reqHdr = struct.Struct('!B') # key
resHdr = struct.Struct('!B B I') # key, valid, value
