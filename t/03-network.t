#!/bin/bin/perl
#
# Copyright (C) 2013 by Lieven Hollevoet

# This test runs tests for the bootloader connecting over TCP

use strict;

use Test::More;
use Test::Requires qw/Test::SharedFork/;
use Test::SharedFork;
use IO::Select;
use IO::Socket::INET;

BEGIN { use_ok('Device::Microchip::Bootloader'); }

my $debug_mult = 10; # Set this to a big number for longer timeouts when interactively debugging.

my $tcp = IO::Socket::INET->new(Listen => 5, Proto => 'tcp', LocalAddr => '127.0.0.1', LocalPort => 0)
    or plan skip_all => "Failed to open TCP server on loopback address: $!";
my $tcp_port = $tcp->sockport;

my $pid = fork();

# Make a TCP test server in a spearate thread and connect to it with the bootloader from the parent thread
if ($pid == 0) {
    # child
    my $sel = IO::Select->new($tcp);
    $sel->can_read(10*$debug_mult) or die;
    my $client = $tcp->accept;
    ok $client, 'client accepted';
    $sel = IO::Select->new($client);
    $sel->can_read(10*$debug_mult) or die;
    my $buf;
    # Handle bootloader info request
    my $bytes = sysread $client, $buf, 2048;
    is $bytes, 5, 'sync pakcet length';
    is $buf, "\x0F\x00\x00\x00\x04", "Got bootloader info request";
    my $resp = "\x0F\x00\x00\x05\x05\x01\xFF\x84\x01\x02\x03\x00\x78\x94\x04";
    syswrite $client, $resp, length($resp);
    # Handle EEPROM read request
    $sel->can_read(10*$debug_mult) or die;
    $bytes = sysread $client, $buf, 2048;
    is $bytes, 13, "Request EEPROM read count OK";
    is $buf, "\x0f\x05\x05\x00\x00\x00\x00\x05\x04\x00\x57\xc0\x04", "EEPROM read command OK";
    $resp = "\x0F\x31\x32\x33\x34\x05\x04\xBA\x04";
    syswrite $client, $resp, length($resp);
    # Handle Flash read request
    $sel->can_read(10*$debug_mult) or die;
    $bytes = sysread $client, $buf, 2048;
    is $bytes, 11, "Request FLASH read count OK";
    is $buf, "\x0f\x01\x00\x00\x00\x00\x0a\x00\x16\x60\x04", "FLASH read command OK";
    $resp = "\x0F\x01\x02\x03\x05\x04\x05\x05\x06\x07\x08\x09\x00\x04\x42\x04";
    syswrite $client, $resp, length($resp);
    # Handle Flash erase page request
    $sel->can_read(10*$debug_mult) or die;
    $bytes = sysread $client, $buf, 2048;
    is $bytes, 10, "Request FLASH erase count OK";
    is $buf, "\x0f\x03\x00\x01\x00\x00\x02\x80\x0e\x04", "FLASH erase command OK";
    $resp = "\x0F\x03\x00\x00\x04";
    syswrite $client, $resp, length($resp);
    


} elsif ($pid) {
    #parent
    my $loader = Device::Microchip::Bootloader->new(firmware => 't/stim/test.hex', device => '127.0.0.1' . ":" . $tcp_port, verbose => 3);
    ok $loader, 'object created';

	# Connect to controller
	$loader->connect_target();
	
	# Now we're connected to the mocked PIC and we have received the ID and software version
	# Version should be 1.5 by now
	my $version = $loader->bootloader_version();
	is $version->{'major'}, 1, 'Major version of the bootloader OK';
	is $version->{'minor'}, 5, 'Minor version of the bootloader OK';
	
	# Try to read an EEPROM location
	my $data = $loader->read_eeprom(0,4);
	is $data, "31323334", "EEPROM reading";
	
	# Try to read a flash memory location
	$data = $loader->read_flash(0,10);
	is $data, "01020304050607080900", "Flash reading";

	# Try to erase 2 flash pages
	$data = $loader->erase_flash(0x100, 2);
	is $data, "03", "Erased 2 pages";
		
    #is ($loader->program, 1, 'Programming over TCP done');
    waitpid $pid, 0;
    done_testing();
} else {
    die $!;
}
