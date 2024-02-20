/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

const bit<8>  UDP_PROTOCOL = 0x11;
const bit<16> TYPE_IPV4 = 0x800;
const bit<2>  REQUEST = 0x1;
const bit<2>  RESPONSE = 0x2;
const bit<16> REQREPVAL = 1234;
const bit<32> NUMKEYS = 128;

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}

header ipv4_t {
    bit<4>    version;
    bit<4>    ihl;
    bit<8>    diffserv;
    bit<16>   totalLen;
    bit<16>   identification;
    bit<3>    flags;
    bit<13>   fragOffset;
    bit<8>    ttl;
    bit<8>    protocol;
    bit<16>   hdrChecksum;
    ip4Addr_t srcAddr;
    ip4Addr_t dstAddr;
}

header udp_t {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<16> length_;
    bit<16> checksum;
}

header request_t {
    bit<8> rkey;
}

header response_t {
    bit<8> rkey;
    bit<8> is_valid;
    bit<32> value;
}

struct parser_metadata_t {
    bit<2>  packet_type;
}

struct ingress_metadata_t {
    bit<1>  cache_hit;
}

struct metadata {
    parser_metadata_t   parser_metadata;
    ingress_metadata_t  ingress_metadata;
}

struct headers {
    ethernet_t   ethernet;
    ipv4_t       ipv4;
    udp_t        udp;
    request_t    request;
    response_t   response;
}

parser MyParser(packet_in packet,
                out headers hdr,
                inout metadata meta,
                inout standard_metadata_t standard_metadata) {

    state start {
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            UDP_PROTOCOL: parse_udp;
            default: accept;
        }
    }

    state parse_udp {
        packet.extract(hdr.udp);
        transition select(hdr.udp.dstPort, hdr.udp.srcPort) {
            (REQREPVAL, _): parse_request;
            (_, REQREPVAL): parse_response;
            default: accept;
        }
    }

    state parse_request {
        packet.extract(hdr.request);
        meta.parser_metadata.packet_type = REQUEST;
        transition accept;
    }

    state parse_response {
        packet.extract(hdr.response);
        meta.parser_metadata.packet_type = RESPONSE;
        transition accept;
    }
}

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {
    apply {  }
}

control MyIngress(inout headers hdr,
                  inout metadata meta,
                  inout standard_metadata_t standard_metadata) {
    action drop() {
        mark_to_drop(standard_metadata);
    }

    action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
        standard_metadata.egress_spec = port;
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }

    table ipv4_lpm {
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        actions = {
            ipv4_forward;
            drop;
            NoAction;
        }
        size = 1024;
        default_action = drop();
    }

    action cache_hit(bit<32> value) {
        bit<16> tmpPort; bit<48> tmpMAC; ip4Addr_t tmpAddr;

        // Use cached value
        hdr.response.setValid();
        hdr.response.rkey = hdr.request.rkey;
        hdr.response.is_valid = 1;
        hdr.response.value = value;
        hdr.request.setInvalid();

        // Modify the packet type
        meta.parser_metadata.packet_type = RESPONSE;

        // Swap UDP ports
        tmpPort = hdr.udp.srcPort;
        hdr.udp.srcPort = hdr.udp.dstPort;
        hdr.udp.dstPort = tmpPort;

        // Swap the MAC addresses
        tmpMAC = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = hdr.ethernet.srcAddr;
        hdr.ethernet.srcAddr = tmpMAC;

        // Swap the IPv4 addresses
        tmpAddr = hdr.ipv4.dstAddr;
        hdr.ipv4.dstAddr = hdr.ipv4.srcAddr;
        hdr.ipv4.srcAddr = tmpAddr;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;

        // Increment the length of the packet
        hdr.ipv4.totalLen = hdr.ipv4.totalLen + 5;
        hdr.udp.length_ = hdr.udp.length_ + 5;

        // Send the packet back to the port it came from
        standard_metadata.egress_spec = standard_metadata.ingress_port;

        // Denote cache hit
        meta.ingress_metadata.cache_hit = 1;
    }

    table cache1 {
        key = {
            hdr.request.rkey: exact;
        }
        actions = {
            cache_hit;
        }
        size = NUMKEYS;
    }

    // Cache2 values: cached values from the server's responses
    register<bit<32>>(NUMKEYS) cache2;
    // Cache2 present bit: if the key's value is present in the cache
    register<bit<1>>(NUMKEYS) cache2_present;
    bit<32> cache2_val;
    bit<1> cache2_present_val;

    apply {
        meta.ingress_metadata.cache_hit = 0;

        // Update cache2
        if (hdr.response.isValid() && meta.parser_metadata.packet_type == RESPONSE) {
            cache2.write((bit<32>)hdr.response.rkey, hdr.response.value);
            cache2_present.write((bit<32>)hdr.response.rkey, 1);
        }
        // Check cache1
        else if (hdr.request.isValid() && meta.parser_metadata.packet_type == REQUEST) {
            cache1.apply();
            // Check cache2 if cache1 miss
            if (meta.ingress_metadata.cache_hit == 0) {
                cache2_present.read(cache2_present_val, (bit<32>)hdr.request.rkey);
                // Cache2 hit
                if (cache2_present_val == 1) {
                    cache2.read(cache2_val, (bit<32>)hdr.request.rkey);
                    cache_hit(cache2_val);
                }
            }
        }
        if (meta.ingress_metadata.cache_hit == 0 && hdr.ipv4.isValid()) {
            ipv4_lpm.apply();
        }

        hdr.udp.checksum = 0;
    }
}

control MyEgress(inout headers hdr,
                 inout metadata meta,
                 inout standard_metadata_t standard_metadata) {
    apply {  }
}

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
     apply {
        update_checksum(
        hdr.ipv4.isValid(),
            { hdr.ipv4.version,
              hdr.ipv4.ihl,
              hdr.ipv4.diffserv,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16);
    }
}

control MyDeparser(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.udp);
        packet.emit(hdr.request);
        packet.emit(hdr.response);
    }
}

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
