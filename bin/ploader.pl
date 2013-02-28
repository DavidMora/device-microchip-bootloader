#! /usr/bin/perl -w

use strict;
use warnings;
use 5.012;
use autodie;
use Device::Microchip::Bootloader;

# ABSTRACT: Bootloader for Microchip PIC devices
# PODNAME: ploader.pl

say "Hello";

#if ( defined $ARGV[0] ) {

    # Create the object
    my $loader = Device::Microchip::Bootloader->new( firmware => '../t/stim/test.hex', device => '/dev/ttyUSB0');
    $loader->_print_program_memory();
    

#} else {
#    die
#"Please pass the folder with the files that need to be parsed as command line option";
#}