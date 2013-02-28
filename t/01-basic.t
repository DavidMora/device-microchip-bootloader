#!/bin/bin/perl
#
# Copyright (C) 2013 by Lieven Hollevoet

# This test runs basic module tests

use strict;
use Test::More;
use Test::Output;
use Test::Exception;

use_ok 'Device::Microchip::Bootloader';

# Check we get an error message on missing input parameters
my $loader;
stderr_like { $loader =  = Device::Microchip::Bootloader->new(); }  qr/Please pass a firmware HEX file for reading/, 'Input parameter check 1';

$loader = Device::Microchip::Bootloader->new(firmware => 't/stim/test.hex', device => '/dev/ttyUSB0');
ok $loader, 'object created';

done_testing();
