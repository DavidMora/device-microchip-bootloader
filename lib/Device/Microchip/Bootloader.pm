use strict;    # To keep Test::Perl::Critic happy, Moose does enable this too...

package Device::Microchip::Bootloader;

use Moose;
use namespace::autoclean;
use 5.012;
use autodie;

use Fcntl;
use IO::Socket::INET;
use Digest::CRC qw(crc16);
use Data::Dumper;

has firmware => (
	is       => 'ro',
	isa      => 'Str',
	required => 1,
);

has device => (
	is       => 'ro',
	isa      => 'Str',
	required => 1,
);

has verbose => (
	is      => 'ro',
	isa     => 'Int',
	default => '0',
);

use Carp qw/croak carp/;

# Ensure we read the hexfile after constructing the Bootloader object
sub BUILD {
	my $self = shift;
	$self->{_connected} = 0;
	$self->_read_hexfile;
}

# Program the target device
sub program {
	my $self = shift;

	# Connect to the target device if this is not the case yet
	if (! $self->{_connected}) {
		$self->connect_target();
	}

	return 0 if !$self->{_connected};

	# TODO complete this function to do the actual programming
	
	return 1;
}

# Open the connection to the target device (serial port or TCP)
# depending on the target parameters that were passed
sub connect_target {
	my $self = shift;

	# Open the port
	$self->_device_open();

	# Request bootloader operation
	$self->_debug( 1, "Anybody home?" );
	$self->_write_packet("00");

	my $response = $self->_read_packet(20);

	# Process the info that was returned
	#$self->_debug( 4, "Got response: " . Dumper($bytes));
	$self->{'bootloader_version_minor'} = $self->_get_byte($response, 2);
	$self->{'bootloader_version_major'} = $self->_get_byte($response, 3);
	
	
	return $response;

}

sub bootloader_version {
 	my $self = shift;
 	my $version->{'major'} = $self->{'bootloader_version_major'};
 	$version->{'minor'} = $self->{'bootloader_version_minor'};
 	
 	return $version;
}

sub read_eeprom {
	my ($self, $start_addr, $numbytes) = @_;
	
	croak "Please enter start address" if (!defined($start_addr));
	croak "Please tell how many bytes to read" if (!defined($numbytes));
		
	my $command = "05" . $self->_int2str($start_addr) . "0000" . $self->_int2str($numbytes);
	
	$self->_write_packet($command);
	my $response = $self->_read_packet(10);
	
	return $response;
}

sub read_flash {
	my ($self, $start_addr, $numbytes) = @_;

	croak "Please enter start address" if (!defined($start_addr));
	croak "Please tell how many bytes to read" if (!defined($numbytes));
		
	my $command = "01" . $self->_int2flashstr($start_addr) . "00" . $self->_int2str($numbytes);
	
	$self->_write_packet($command);
	my $response = $self->_read_packet(10);
	
	return $response;
	
}

sub erase_flash {
	my ($self, $stop_addr, $pages) = @_;

	croak "Please enter stop address" if (!defined($stop_addr));
	croak "Please tell how many pages to erase" if (!defined($pages));
		
	my $command = "03" . $self->_int2flashstr($stop_addr) . "00" . $self->_dec2hex($pages);
	
	$self->_write_packet($command);
	my $response = $self->_read_packet(10);
	
	return $response;
	
	
}

# open the port to a device, be it a serial port or a socket
sub _device_open {
	my $self = shift;

	my $dev = $self->device();
	my $fh;
	my $baud = 115200;

	if ( $dev =~ /\// ) {
		if ( -S $dev ) {
			$fh = IO::Socket::UNIX->new($dev)
			  or croak("Unix domain socket connect to '$dev' failed: $!\n");
		} else {
			require Symbol;
			require Device::SerialPort;
			import Device::SerialPort qw( :PARAM :STAT 0.07 );
			$fh = Symbol::gensym();
			my $sport = tie( *$fh, 'Device::SerialPort', $dev )
			  or $self->argh("Could not tie serial port to file handle: $!\n");
			$sport->baudrate($baud);
			$sport->databits(8);
			$sport->parity("none");
			$sport->stopbits(1);
			$sport->datatype("raw");
			$sport->write_settings();
			sysopen( $fh, $dev, O_RDWR | O_NOCTTY | O_NDELAY )
			  or croak("open of '$dev' failed: $!\n");
			$fh->autoflush(1);
		}
	} else {
		$dev .= ':' . ('10001') unless ( $dev =~ /:/ );
		$fh = IO::Socket::INET->new($dev)
		  or croak("TCP connect to '$dev' failed: $!\n");
	}

	$self->_debug( 1, "Port opened" );

	$self->{_fh} = $fh;
	return;

}

## write_serial
#   Prints data to the serial port.
#   the controller
#   Takes a string of hex characters as input (e.g. "DEADBEEF").
#   Tho characters get converted to a single byte that will be sent
sub _write_packet {

	my ( $self, $data ) = @_;

	# Create packet for transmission
	my $string = pack( "H*", $data );

	my $crc = crc16($string);
	my $packet = $string . pack( "C", $crc % 256 ) . pack( "C", $crc / 256 );

	$packet = $self->_escape($packet);
	
	$packet = pack( "C", 15 ) . $packet . pack( "C", 4 );

	$self->_debug( 3, "Writing: " . $self->_hexdump($packet) );

	# Write
	syswrite( $self->{_fh}, $packet, length($packet) );

}

## read_serial(timeout)
#   Reads data from the serial port. Times out if nothing is
#   received after <timeout> seconds.
sub _read_packet {

	my ( $self, $timeout) = @_;

	my @numresult;
	my $result;

	eval {

		# Set alarm
		alarm($timeout);

		# Execute receive code
		my $waiting = 1;
		$result = "";
		my $bytes;
		while ($waiting) {

			# Read reply, could be in multiple passes, so we need to add as offset the current length of the receiving variable
			$bytes = $self->{_fh}->sysread( $result, 2048, length($result) );

 # Verify we have the entire string (should end with 0x04 and no preceding 0x05)
			$self->_debug( 4, "RX # " . $self->_hexdump($result) );
			#if ( $sync && $result =~ /\x0F/ ) {
			#	$waiting = 0;
			#}
			
			# Stop reading when we receive an end of line marker
			if ( $result =~ /\x04$/) {
				$waiting = 0;
				# unless we received and 0x04 that was escaped because then we were not at the end of the packet
				$waiting = 1 if ($result =~ /\x05\x04$/);
				# Unless it was an escaped \x05
				$waiting = 0 if ($result =~ /\x05\x05\x04$/);	
			}
			
		}

		# Clear alarm
		alarm(0);
	};

	# Check what happened in the eval loop
	if ($@) {
		if ( $@ =~ /timeout/ ) {

			# Oops, we had a timeout
			croak("Timeout waiting for data from device");
		} else {

			# Oops, we died
			alarm(0);    # clear the still-pending alarm
			die;         # propagate unexpected exception
		}

	}

	#return 1 if ($sync);

	# We get here if the eval exited normally
	$result = $self->_parse_response($result);

	return $result;
}

## parse_response
# Decode the response from the embedded device, i.e. remove
# protocol overhead, and return the remaining result.
sub _parse_response {
	my ( $self, $input ) = @_;

	# Verify packet structure <STX><STX><...><ETX>
	if (
		!(
			   ( $input =~ /^\x0F/ )
			&& ( $input =~ /\x04$/ )
			&& (!( $input =~ /\x05\x04$/ ) || ($input =~ /\x05\x05\x04$/))
		)
	  )
	{
		croak("Received invalid packet structure from PIC\n");
	}


	# Skip the header byte, no need to verify again the value, was verified with regexp already
	$_ = $input;
	s/^.//s;
	# pop the trailing end of transmission marker
	s/.$//s;
	
	$input = $self->_unescape($_);

	#say "Received after processing: " . $self->_hexdump($input);
	
	# Process the received data
	my @numresult = unpack( "C*", $input );

	# Verify the CRC
	my $crc_check = 0;


	# Received CRC
	my $rx_crc = pop(@numresult);
	$rx_crc = $rx_crc * 256 + pop(@numresult);
	
	# Calculate the CRC on the received string minus the CRC and trailing 0x04
	$crc_check = crc16(substr($input, 0, length($input) - 3));
	
	# The CRCs should match, otherwise inform the user
	if ( $crc_check != $rx_crc ) {
		carp("Received invalid CRC in response from PIC, rx: " . $self->_dec2hex($rx_crc) . " -- calc: " . $self->_dec2hex($crc_check). "\n");
	}

	# Convert back to string of hex characters
	# TODO optimize this into pack
	#my $res_string = pack ("C");
	my $res_string;
	foreach (@numresult) {
		$res_string .= sprintf("%02X", $_);
	}
	return $res_string;

}

# Read the hexfile containing the program memory data
sub _read_hexfile {

	my $self = shift;

	open my $fh, '<', $self->{firmware};

	#        or croak "Could not open firmware hex file for reading: $!";

	my $counter = 0;
	my $offset  = 0;

	while ( my $line = <$fh> ) {
		chomp($line);

		$counter++;

		# Check for end of file marker
		if ( $line =~ /^:[0-9A-F]{6}01/ ) {

			#print "End of file marker found.\n";
			last;
		}

		# Translate extended Linear Address Records
		if ( $line =~ /^:(02000004([0-9A-F]{4}))([0-9A-F]{2})/ ) {
			$offset = hex($2);
			$self->_check_crc( $1, $3, $counter );

			$self->_debug( 2,
"Detected HEX386 Extended Linear Address Record in hex file, using offset: $offset"
			);

			next;
		}

		# Translate data records
		if ( $line =~
			/^:(([0-9A-F]{2})([0-9A-F]{4})00([0-9A-F]+))([0-9A-F]{2})/ )
		{

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

# Helper function converting dec2hex
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

# Add an entry to the memory variable that will be used to flash the PIC
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
			my $error
			  = sprintf "Memory location 0x%X defined twice in hex file.\n",
			  $mem_addr;
			croak $error;
		}
	}

}

# Displays the program memory contents in hex format on the screen
sub _print_program_memory {
	my $self = shift;

	my $counter = 0;

	foreach my $entry ( sort { $a <=> $b } keys $self->{_program} ) {
		if ( ( $counter % 8 ) == 0 ) {
			print "\n $counter\t: ";
		}
		print $self->{_program}->{$entry}->{data};
		$counter++;
	}
}

# debug
#   Debug print supporting multiple log levels
sub _debug {

	my ( $self, $debuglevel, $logline ) = @_;

	if ( $debuglevel <= $self->verbose() ) {
		say "+$debuglevel= $logline";
	}
}

# Print input string of characters as hex
sub _hexdump {
	my ( $self, $s ) = @_;
	my $r = unpack 'H*', $s;
	$s =~ s/[^ -~]/./g;
	return $r . ' (' . $s . ')';
}

# Escape a string before sending it to the controller
# See microchip AN1310 appendix A
# Send in the payload data as a string, you get the escaped string out
sub _escape {
	my ($self, $s) = @_;
	
	# byte stuffing for the control characters in the data stream
	$s =~ s/\x05/\x05\x05/g;
	$s =~ s/\x04/\x05\x04/g;
	$s =~ s/\x0F/\x05\x0F/g;
	
	return $s;
	
}

# Strip the escape codes from the received string
sub _unescape {
	my ($self, $s) = @_;
	
	# <DLE>
	$s =~ s/\x05\x05/\x05/g;

	# <ETX>
	$s =~ s/\x05\x04/\x04/g;

	# <STX>
	$s =~ s/\x05\x0F/\x0F/g;
	
	return $s;
}

# Convert an int to the string format required by the bootloader
#  int -> <byte_low><byte_high>
sub _int2str {
	my ($self, $num) = @_;
	
	my $lsb = $num % 256;
	my $msb = ($num - $lsb) / 256;
	
	my $resp = $self->_dec2hex($lsb) . $self->_dec2hex($msb);
	return $resp;
}

# Convert an int to the string format required for flash access
# int -> <byte_low><bye_high><bytes_upper>
# TODO integrate this with the funtion above and refactor
sub _int2flashstr {
	my ($self, $num) = @_;
	
	my $lsb = $num % 256;
	my $msb = (($num - $lsb) / 256) % 256;
	my $usb = ($num - 256 * $msb - $lsb ) / 256 / 256 ;
	
	my $resp = $self->_dec2hex($lsb) . $self->_dec2hex($msb) . $self->_dec2hex($usb);
	return $resp;	
}

# Convert string to int as communicated by the bootloader
# <byte_low><byte_high> -> int
sub _str2int {
	my ($self, $num) = @_;
	return 0;	
}

# Extract a byte from the response string
# Pass string and byte number (first byte is 0)
# and you get the integer value back
sub _get_byte {
	my ($self, $response, $offset) = @_;
	
	my $byte = substr($response, $offset*2, 2);
	
	return hex($byte);
	
}

# Speed up the Moose object construction
__PACKAGE__->meta->make_immutable;
no Moose;
1;

# ABSTRACT: Bootloader host software for Microchip PIC devices

=head1 SYNOPSIS

my $loader = Device::Microchip::Bootloader->new(firmware => 'my_firmware.hex', target => '/dev/ttyUSB0');

=head1 DESCRIPTION

Host software for bootloading a HEX file to a PIC microcontroller that is programmed with the bootloader as described in Microchip AN1310.

The tool allows bootloading over serial port and over ethernet when the device is connected over a serial to ethernet adapter such as a Lantronix XPort.

=head1 METHODS

=head2 C<new(%parameters)>

This constructor returns a new Device::Microchip::Bootloader object. Supported parameters are listed below

=over

=item firmware

The hex file that is to be programmed into the target device. Upon creation of the object, the HEX file will be examined and possible errors will be flagged.

=item device

The target device where to send the firmware to. This can be either a serial port object (e.g. /dev/ttyUSB0) or a TCP socket (e.g. 192.168.1.52:10001).

=back

=head2 C<connect_target>

Make a connection to the target device. This function will return a hash containing information on the response containing the following elements:

=over 

=item firmware version

=item type of pic we're connected to ('PIC16' of 'PIC18')

=back

The other elements of the response of the  

=head2 C<version>

Reports the version of the bootloader firmware running on the device as [major].[minor].

=head2 C<BUILD>

An internal function used by Moose to run code after the constructor. Need to document because otherwise Test::Pod::Coverage test fails


=cut
