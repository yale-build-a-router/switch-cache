#!/usr/bin/env python

import sys
import socket
from cache_protocol import *


if len(sys.argv) != 3:
    print("Usage: %s HOST KEY" % sys.argv[0])
    sys.exit(1)

host = sys.argv[1]
key = int(sys.argv[2])

addr = (host, UDP_PORT)

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(2)

req = reqHdr.pack(key)
s.sendto(req, addr)

res, addr2 = s.recvfrom(1024)

key2, valid, value = resHdr.unpack(res)
# print(key2, valid, value)

assert key2 == key

if valid:
    print(value)
else:
    print("NOTFOUND")
