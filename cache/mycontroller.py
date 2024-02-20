#!/usr/bin/env python3
import argparse
import os
import sys
from time import sleep

# Import P4Runtime lib from parent utils dir.
sys.path.append(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), '/home/joshua/tutorials/utils')
)
import p4runtime_lib.bmv2
import p4runtime_lib.helper
from p4runtime_lib.error_utils import printGrpcError
from p4runtime_lib.switch import ShutdownAllSwitchConnections


def readTableRules(p4info_helper, sw):
    """
    Reads the table entries from all tables on the switch.

    :param p4info_helper: the P4Info helper
    :param sw: the switch connection
    """
    print('\n----- Reading tables rules for %s -----' % sw.name)
    for response in sw.ReadTableEntries():
        for entity in response.entities:
            entry = entity.table_entry
            print(entry)
            print('-----')


def write_rule(p4info_helper, sw, key, value):
    """
    Writes a rule to the given switch. Feel free to modify this function as you need.
    
    :param p4info_helper: the P4Info helper
    :param sw: the switch connection
    :param key: cached key
    :param value: cached value
    """
    # TODO: Create a table entry that points to your cache table. 
    # Refer to tutorials/exercises/p4runtime for a working example
    table_entry = {
        "table_name": "MyIngress.cache1",
        "match_fields": {
            "hdr.request.rkey": key
        },
        "action_name": "MyIngress.cache1_hit",
        "action_params": {
            "is_valid": 11,
            "value": value
        }
    }
    
    # Writing the table entry to the switch
    entry = p4info_helper.buildTableEntry(**table_entry)
    sw.WriteTableEntry(entry)
    
    print("Installed cache rule on %s" % sw.name)

def main(p4info_file_path, bmv2_file_path):
    # Instantiate a P4Runtime helper from the p4info file
    p4info_helper = p4runtime_lib.helper.P4InfoHelper(p4info_file_path)

    try:
        # Create a switch connection object for s1;
        # this is backed by a P4Runtime gRPC connection.
        # Also, dump all P4Runtime messages sent to switch to given txt files.
        s1 = p4runtime_lib.bmv2.Bmv2SwitchConnection(
            name='s1',
            address='127.0.0.1:50051',
            device_id=0,
            proto_dump_file='logs/s1-p4runtime-requests-1.txt')

        # Send master arbitration update message to establish this controller as
        # master (required by P4Runtime before performing any other write operation)
        s1.MasterArbitrationUpdate()

        # Install the P4 program on the switches
        s1.SetForwardingPipelineConfig(p4info=p4info_helper.p4info,
                                       bmv2_json_file_path=bmv2_file_path)
        print("Installed P4 Program using SetForwardingPipelineConfig on s1")
        
        # TODO: Write cache rules (Hint: use the write_rule function)
        write_rule(p4info_helper, s1, 1, 321)
        write_rule(p4info_helper, s1, 2, 543)
        write_rule(p4info_helper, s1, 3, 876)

        # Read table entries from s1
        readTableRules(p4info_helper, s1)

    except KeyboardInterrupt:
        print(" Shutting down.")

    ShutdownAllSwitchConnections()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='P4Runtime Controller')
    parser.add_argument('--p4info', help='p4info proto in text format from p4c',
                        type=str, action="store", required=False,
                        default='./build/cache.p4.p4info.txt')
    parser.add_argument('--bmv2-json', help='BMv2 JSON file from p4c',
                        type=str, action="store", required=False,
                        default='./build/cache.json')
    args = parser.parse_args()

    if not os.path.exists(args.p4info):
        parser.print_help()
        print("\np4info file not found: %s\nHave you pointed to 'cache.p4.p4info.txt'?" % args.p4info)
        parser.exit(1)
    if not os.path.exists(args.bmv2_json):
        parser.print_help()
        print("\nBMv2 JSON file not found: %s\nHave you run  pointed to 'cache.p4.p4info.txt'?" % args.bmv2_json)
        parser.exit(1)
    main(args.p4info, args.bmv2_json)
