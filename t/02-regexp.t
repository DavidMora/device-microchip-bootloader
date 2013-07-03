#!/bin/bin/perl
#
# Copyright (C) 2013 by Lieven Hollevoet

# Check the regexp for de-escaping the communication stream between the
# controller and the software

use strict;

use Test::More;

BEGIN { use_ok 'Device::Microchip::Bootloader'; }


my $loader = Device::Microchip::Bootloader->new(firmware => 't/stim/test.hex', device => '/dev/ttyUSB0');
ok $loader, 'object created';

# Verify the escaping/unescaping of communication between the bootloader and the software
my $data = "\x00\x0F\x00\x05\x01\xFF\x84\x01\x02\x03\x05\x04\x05\x05\x04";

my $escaped = $loader->_escape($data);
is $escaped, "\x00\x05\x0F\x00\x05\x05\x01\xFF\x84\x01\x02\x03\x05\x05\x05\x04\x05\x05\x05\x05\x05\x04", "Testing escape code for serialization";

my $unescaped = $loader->_unescape($escaped);
is $unescaped, $data, "Unescaping yields original string";

$unescaped = $loader->_unescape("\x00\x01\x02\x03\x05\x04\x05\x05\x06");
is $unescaped, "\x00\x01\x02\x03\x04\x05\x06", "Standalone unescape test";


# Verify the int to string and reverse functions
my $smallint = 10;
my $bigint   = 1025;

my $small_string = $loader->_int2str($smallint);
my $big_string   = $loader->_int2str($bigint);

is $small_string, "0A00", "Small int2str";
is $big_string, "0104",   "Big int2str";

# Verify the CRC funcions
my $input = "\x00\x04\x01\x05\xFF\x84\x00\xFC\x00\x00";
my $crc = $loader->_crc16($input);
is $crc, 0xCBC1, "CRC calculates according to Microchip implementation";

done_testing();
