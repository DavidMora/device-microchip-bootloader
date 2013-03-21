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


my $tcp = IO::Socket::INET->new(Listen => 5, Proto => 'tcp', LocalAddr => '127.0.0.1', LocalPort => 0)
    or plan skip_all => "Failed to open TCP server on loopback address: $!";
my $tcp_port = $tcp->sockport;

my $pid = fork();

# Make a TCP test server in a spearate thread and connect to it with the bootloader from the parent thread
if ($pid == 0) {
    # child
    my $sel = IO::Select->new($tcp);
    $sel->can_read(10) or die;
    my $client = $tcp->accept;
    ok $client, 'client accepted';
    $sel = IO::Select->new($client);
    $sel->can_read(10) or die;
    my $buf;
    my $bytes = sysread $client, $buf, 2048;
    is $bytes, 10, 'sync pakcet length';
    my $resp = "\x0F";
    syswrite $client, $resp, length($resp);
    $sel->can_read(10) or die;
    $bytes = sysread $client, $buf, 2048;
    is $bytes, 5, "Request status";
    $resp = "\x0F\x00\x01\x01\x01\x00\x04";
    syswrite $client, $resp, length($resp);


} elsif ($pid) {
    #parent
    my $loader = Device::Microchip::Bootloader->new(firmware => 't/stim/test.hex', device => '127.0.0.1' . ":" . $tcp_port, verbose => 4);
    ok $loader, 'object created';


    is ($loader->program, 1, 'Programming over TCP done');
    waitpid $pid, 0;
    done_testing();
} else {
    die $!;
}
