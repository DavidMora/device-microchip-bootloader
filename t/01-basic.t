#!/bin/bin/perl
#
# Copyright (C) 2013 by Lieven Hollevoet

# This test runs basic module tests

use strict;
use Test::More;

use_ok 'Device::Microchip::Bootloader';

my $loader = Device::Microchip::Bootloader->new(firmware => 't/stim/test.hex', device => '/dev/ttyUSB0');

done_testing();
