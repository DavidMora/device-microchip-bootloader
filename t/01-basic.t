#!/bin/bin/perl
#
# Copyright (C) 2013 by Lieven Hollevoet

# This test runs basic module tests

use strict;
use Test::More;

BEGIN { use_ok 'Device::Microchip::Bootloader'; }
BEGIN { use_ok 'Test::Exception'; }

# Check we get an error message on missing input parameters
my $loader;

throws_ok { $loader = Device::Microchip::Bootloader->new() } qr/Please pass a firmware HEX file for reading/, "Checking missing HEX file input";
throws_ok { $loader = Device::Microchip::Bootloader->new(firmware => 't/stim/test.hex') } qr/Please pass a target device/, "Checking missing target device";
throws_ok { $loader = Device::Microchip::Bootloader->new(firmware => 't/stim/missing_file.hex', device => 'flubber') } qr/Could not open/, "Checking missing hex file";

$loader = Device::Microchip::Bootloader->new(firmware => 't/stim/test.hex', device => '/dev/ttyUSB0');
ok $loader, 'object created';

done_testing();
