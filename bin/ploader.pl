#! /usr/bin/perl -w

use strict;
use warnings;
use 5.012;
use autodie;
use Device::Microchip::Bootloader;

# ABSTRACT: Bootloader for Microchip PIC devices
# PODNAME: ploader.pl


#if ( defined $ARGV[0] ) {

    # Create the object
    my $loader = Device::Microchip::Bootloader->new( firmware => 'blinky.hex', device => '192.168.1.57:10002', verbose => 0);
    #my $loader = Device::Microchip::Bootloader->new( firmware => '../t/stim/test.hex');

	$loader->_rewrite_entrypoints("BEEF");
    $loader->_print_program_memory();
	    
	$loader->connect_target();
	my $data;
	
    #$loader->_print_program_memory();
    #my $data = $loader->read_eeprom(0, 4);
	#say "Read from EEPROM: $data";
	$data = $loader->read_flash(0, 2);
	say "Read goto bootloader from FLASH:  $data";
	$data = $loader->read_flash(0xFC00, 100);
	say "Read from FLASH:  $data";

	# Prepare some pages
	#$data = $loader->write_flash(64, "0301000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000000201000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000001111222233334444");	
	#$data = $loader->write_flash(1024, "0301000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000000201000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000001111222233334444");	
	#$data = $loader->write_flash(2048, "0301000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000000201000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000001111222233334444");	
	
	# Erase a page
	#$data = $loader->erase_flash(2048, 3);
	#say "Erased flash: $data";
	
	
	# Read the bootloader location, expecting a 'goto 0xfc02' here
	my $goto_bootloader = $loader->read_flash(0x0000, 2);
	
	say "Read goto bootloader: $goto_bootloader";
	
		
	# Erase the device
	$data = $loader->erase_flash(0xFC00, 64);
	say "Erased flash: $data";
#
#	$data = $loader->read_flash(0xFC00, 100);
#	say "Read from FLASH:  $data";
#	$data = $loader->read_flash(0xFC00 - 64, 64);
#	say "Read from FLASH:  $data";
#
#
#	# Try to overwrite the bootloader
#	$data = $loader->write_flash(0xFC00, "0301000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000000201000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000001111222233334444");	
#	say "Wrote flash: $data";
#	$data = $loader->write_flash(0xFC00 - 64, "0301000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000000201000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000001111222233334444");	
#	say "Wrote flash: $data";
#	
#	$data = $loader->read_flash(0xFC00, 100);
#	say "Read from FLASH:  $data";
#	
#	$data = $loader->read_flash(0xFC00 - 64, 100);
#	say "Read from FLASH:  $data";
#
#	$data = $loader->erase_flash(0xFC00, 3);
#	say "Erased flash: $data";	
#	
#	$data = $loader->read_flash(0xFC00 - 64, 100);
#	say "Read from FLASH:  $data";	
	
	
	# Erase the full chip
	#$data = $loader->erase_flash(0xFC00, )
	
	# 	
	# Write a page
	#$data = $loader->write_flash(0x1000, "0301000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000000201000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000001111222233334444");	
	#say "Wrote flash: $data";
	#$data = $loader->write_flash(64, "0301000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000000201000000000000000000000000000000000000020100000000000000000000000000000000000002010000000000000000000000000000000000001111222233334444");	
	#say "Wrote flash: $data";
	
	# Read the CRCs for the complete flash
	#$data = $loader->read_flash_crc(0, 32);
	#say "Read CRCs:";
	#foreach my $key (sort keys %{$data}) {
	#	print "$key : $data->{$key}\n";
	#}
	
	

#} else {
#    die
#"Please pass the folder with the files that need to be parsed as command line option";
#}
