# In-Network Cache

In this assignment you will implement a cache for a simple key-value service.

## Key-value service overview

A server contains a store of key-value mappings. A client can read values from
the store by issuing a read request. The read request indicates the key (8-bit
integer) of the object to be read. The server responds to a read request with
the key, along with its corresponding value. If the store doesn't contain a
value for the key, the server responds with the key, along with a flag
indicating the value is not present.


## Key-value Protocol

The client and server communicate with a custom protocol. The protocol has two
types of messages: requests and responses. The header format for requests and
responses is different. The UDP destination and source ports are used to
distinguish requests from responses: requests are sent to UDP *destination
port* 1234, whereas responses are *from UDP source port* 1234. The exact format
of the headers is outlined below.

### Request

Packet sent from client to server:

    +----------------------+
    |       ........       |  Ethernet
    +----------------------+
    |       ........       |  IPv4
    +----------------------+
    |       ........       |  UDP (dstPort=1234)
    +----------------------+
    | key (8 bits)         |  Request header
    +----------------------+


### Response

Response packet from server to client:

    +----------------------+
    |       ........       |  Ethernet
    +----------------------+
    |       ........       |  IPv4
    +----------------------+
    |       ........       |  UDP (srcPort=1234)
    +----------------------+
    | key (8 bits)         |
    | is_valid (8 bits)    |  Response header
    | value (32 bits)      |
    +----------------------+


## Client/Server Programs

Implementations of the client and server are provided for you in `client.py`
and `server.py`. They use the protocol definitions in `cache_protocol.py`. You
can run them locally on your computer (i.e. without the need for running BMV2
or Mininet). Start the server:

    ./server.py


In another terminal, read key `1` with the client:

    ./client.py 127.0.0.1 1

It should print `11`, which is the default value for key `1`. The server's
store has these default values:

    store = {1: 11, 2: 22}

You can override them when you start the server, e.g.

    ./server.py 1=123 2=345 3=678

## Switch-based cache

Packets travel through exactly one switch between the client and the server:

    client (h2) <---> switch (s1) <---> server (h1)

You should implement a cache in the switch. The cache is transparent, in
that neither the server nor the client is aware of the cache. When a client
requests a key, it sends a request packet through the switch. The switch should
parse the request packet, to determine the key that is being requested. If
there is a cache hit (i.e. the requested key is in the switch cache), then the
switch should respond directly to the client with the value in a response
packet. If there is a cache miss, the switch should forward the packet to the
server as normal. Note that the server shouldn't receive the client's request
if there was a cache hit at the switch.

### Updating the switch cache

The switch maintains two types of caches. The first is implemented as a P4
table, and is updatable from the control plane with P4Runtime. The second is
implemented with registers, and is updated from responses from the server.

The switch checks the caches in this order: if there's a cache hit in the
table, it uses the value from the table; if there is a cache hit in the
registers, then it uses the value from the registers; otherwise, it's a cache
miss, and the packet should be forwarded as normal.

To implement the register-based cache, you can use the key as an index into the
register cell that contains the value. This means that with an 8-bit key, the
register array needs at least 2^8 cells.


## Getting started

We have provided a p4app with boilerplate code to get started with:

- `cache.p4` is a boilerplate P4 program in which you should implement your
  cache functionality.

- `main.py` starts a Mininet network with a single switch connecting a client
  and server host. You should extend this with P4Runtime calls to populate
  the table-based cache on the switch.

Before you start implementing the cache functionality, you should get basic
IPv4 forwarding working. You can look at these examples for how to implement
both the data plane and control plane:

- [p4app examples](https://github.com/p4lang/p4app/tree/rc-2.0.0/examples)
- [P4 tutorial exercises](https://github.com/p4lang/tutorials/tree/p4app/p4app-exercises)

Specifically, for implementing IPv4 forwarding, you should look at the [control
plane](https://github.com/p4lang/tutorials/blob/p4app/p4app-exercises/basic.p4app/main.py#L61)
and [data
plane](https://github.com/p4lang/tutorials/blob/p4app/p4app-exercises/basic.p4app/solution/basic.p4#L100)
from the `basic.p4app` tutorial exercise.

## Resources

You can get familiar with the P4_16 language specification:
https://p4.org/p4-spec/docs/P4-16-v1.1.0-spec.html

Registers are not part of the P4 language specfication, but are an extern in
the
[v1model.p4](https://github.com/p4lang/p4c/blob/a1c3e0b868d5be2c7921cc8a80cf1ea6c4aba80d/p4include/v1model.p4#L109)
used by BMV2. For sample usage, take a look at the
[register.p4app](https://github.com/p4lang/p4app/tree/rc-2.0.0/examples/registers.p4app)
example.


## Tips

- If you're changing the packet, don't forget to:
    - update the IP and UPD length fields; and
    - set the UDP checksum to 0.
- Don't use `valid` as a header field, as it conflicts with setValid/setInvalid in P4.
- p4app uses Mininet to connect hosts h1 and h2 to switch s1. The port numbers
  are assigned in increasing order, so h1 is connected to s2 on port 1, and h2 on
  port 2.
- After you run p4app, check that it creates the directory `/tmp/p4app-logs`.
    - If this directory does not exit, there may be a problem with your Docker installation.
- The switch dumps sent/received packets in `/tmp/p4app-logs/s1-eth*.pcap`
    - `eth1` is connected to h1, and `eth2` to h2
    - you can inspect the pcaps with [wireshark](https://www.wireshark.org/)
- You can also run wireshark on a single host, e.g. on host2:

    ~/p4app/p4app exec m h2 tcpdump -Uw - | wireshark -ki -


## Running

First, make sure you have p4app:

    cd ~/
    git clone --branch rc-2.0.0 https://github.com/p4lang/p4app.git

Then run this p4app:

    ~/p4app/p4app run cache.p4app
