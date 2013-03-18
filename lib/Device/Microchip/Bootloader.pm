use strict;
use warnings;
use 5.012;
use autodie;

package Device::Microchip::Bootloader;

use Moose;
#use namespace::autoclean;

has firmware => (
	is => 'ro', 
	isa => 'Str', 
	required => 1,
);

has device => (
	is => 'ro', 
	isa => 'Str',
	required => 1,
);

use Carp qw/croak carp/;

# ABSTRACT: Bootloader host software for Microchip PIC devices

sub BUILD {
	my $self = shift;
	$self->_read_hexfile;
}

# Read the hexfile containing the program memory data
sub _read_hexfile {

	my $self = shift;

	open my $fh, '<', $self->{firmware}
	  or croak "Could not open firmware hex file for reading: $!";

	my $counter = 0;
	my $offset  = 0;

	while (my $line = <$fh>) {
		chomp($line);

		$counter++;

		# Check for end of file marker
		if ($line =~ /^:[0-9A-F]{6}01/) {

			#print "End of file marker found.\n";
			last;
		}

		# Translate extended Linear Address Records
		if ($line =~ /^:(02000004([0-9A-F]{4}))([0-9A-F]{2})/) {
			$offset = hex($2);
			$self->_check_crc( $1, $3, $counter );

			say(
"Detected HEX386 Extended Linear Address Record in hex file, using offset: $offset\n"
			);
			next;
		}

		# Translate data records
		if ($line =~ /^:(([0-9A-F]{2})([0-9A-F]{4})00([0-9A-F]+))([0-9A-F]{2})/) {

			# $1 = everything but the CRC
			# $2 = nr of words
			# $3 = address
			# $4 = data
			# $5 = crc
			my $address = hex($3);

			# Check if we have valid CRC
			$self->_check_crc( $1, $5, $counter );

			# If CRC was valid, add it to the memory datastructure
			# Be sure to add the $offset from the Linear Address Record!
			$self->_add_to_memory( $address + $offset, $4 );

			next;
		}

		# Catch invalid records
		croak( $self->{firmware} . " contains invalid info on line $counter." );

	}

	close($fh);
}

# Verify the CRC of a line read from the HEX file
#   If CRC is invalid, then suggest the correct one (so you
#   don't have to calculate it yourself when doing instruction
#   level hacking :-) )
sub _check_crc {
	my ( $self, $data, $crc_in, $line_num ) = @_;

	$crc_in = hex($crc_in);

	my $string = pack( "H*", $data );
	my $crc_calc = ( 256 - unpack( "%a*", $string ) % 256 ) % 256;

	if ( $crc_calc != $crc_in ) {
		my $nice_crc = $self->_dec2hex($crc_calc);
		carp(
"Invalid CRC in '$self->{firmware}' on line $line_num, should be 0x$nice_crc"
		);
	}

}

sub _dec2hex {

	my ( $self, $dec, $fill ) = @_;

	my $fmt_string;

	if ( defined($fill) ) {
		$fmt_string = "%0" . $fill . "X";
	} else {
		$fmt_string = "%02X";
	}
	return sprintf( $fmt_string, $dec );
}

sub _add_to_memory {

	my ( $self, $address, $data_in ) = @_;

	my $index;
	my $mem_addr;

	my @data = unpack( "a4" x ( length($data_in) / 4 ), $data_in );

	# Scan the line
	for ( $index = 0 ; $index < scalar(@data) ; $index++ ) {

		# Calculate the actual address ($index * 2) because we read bytes and write shorts
		$mem_addr = ( $index * 2 ) + $address;

		# And add the info if the location is not defined yet
		if ( !defined( $self->{_program}->{$mem_addr} ) ) {
			$self->{_program}->{$mem_addr}->{data} = $data[$index];
		} else {
			my $error =
			  sprintf "Memory location 0x%X defined twice in hex file.\n",
			  $mem_addr;
			croak $error;
		}
	}

}

# Displays the program memory contents in hex format on the screen
sub _print_program_memory {
	my $self = shift;
	
	my $counter = 0;
	
	foreach my $entry (sort {$a<=>$b} keys $self->{_program}) {
		if (($counter % 8) == 0) {
			print "\n $counter\t: ";
		}
		print $self->{_program}->{$entry}->{data};
		$counter++;
	}
}

# Speed up the Moose object construction
__PACKAGE__->meta->make_immutable;

=head1 SYNOPSIS

my $loader = Device::Microchip::Bootloader->new(firmware => 'my_firmware.hex', target => '/dev/ttyUSB0');

=head1 DESCRIPTION

Host software for bootloading a HEX file to a PIC microcontroller that is programmed with the bootloader as described in Microchip AN1310.

The tool allows bootloading over serial port and over ethernet when the device is connected over a serial to ethernet adapter such as a Lantronix XPort.

=method C<new(%parameters)>

This constructor returns a new Device::Microchip::Bootloader object. SUpported parameters are listed below

=over

=item firmware

The hex file that is to be programmed into the target device. Upon creation of the object, the HEX file will be examined and possible errors will be flagged.

=item device

The target device where to send the firmware to. This can be either a serial port object (e.g. /dev/ttyUSB0) or a TCP socket (e.g. 192.168.1.52:10001). 

=back

=cut

1;
