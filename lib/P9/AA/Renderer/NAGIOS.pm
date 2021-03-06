package P9::AA::Renderer::NAGIOS;

use strict;
use warnings;

use base 'P9::AA::Renderer';

our $VERSION = 0.10;

=head1 NAME

Nagios external check compatible output renderer.

=cut

sub render {
	my ($self, $data, $resp) = @_;
	my $buf = '';
	my $exit_code = 0;
	
	if ($data->{data}->{check}->{warning}) {
		my $warn = $data->{data}->{check}->{warning_message};
		$warn =~ s/[\r\n]+/ /gm;
		$buf = "WARNING: " . $warn . "\n",
		$exit_code = 1;
	}
	elsif ($data->{data}->{check}->{success}) {
		$buf = "OK\n";
	}
	else {
		my $err = $data->{data}->{check}->{error_message};
		$err =~ s/[\r\n]+/ /gm;
		$buf = "CRITICAL: " . $err . "\n",
		$exit_code = 2;
	}
	
	# set exit code :)
	$self->setHeader($resp, 'exit_code', $exit_code);

	return $buf
}

=head1 SEE ALSO

L<P9::AA::Renderer>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;
# EOF