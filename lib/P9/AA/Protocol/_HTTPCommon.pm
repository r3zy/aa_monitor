package P9::AA::Protocol::_HTTPCommon;

use strict;
use warnings;

use URI;
use URI::QueryParam;

use HTTP::Status;
use Scalar::Util qw(blessed);

use P9::AA::Util;
use P9::AA::CheckHarness;
use base 'P9::AA::Protocol';

our $VERSION = 0.10;

my $log = P9::AA::Log->new();
my $u = P9::AA::Util->new();

sub urldecode {
	shift if ($_[0] eq __PACKAGE__ || (blessed($_[0]) && $_[0]->isa(__PACKAGE__)));
	my ($str) = @_;
	return '' unless (defined $str && length $str);
	$str =~ s/\+/ /g;
	$str =~ s/%([0-9a-hA-H]{2})/pack('C',hex($1))/ge;
	return $str;
}

sub parseJSON {
	my ($self, $data_ref) = @_;
	my $d = $u->parseJson($data_ref);
	unless (defined $d && ref($d) eq 'HASH') {
		$self->error("Error parsing JSON: " . $u->error());
		return undef;
	}

	return $d;	
}

sub parseXML {
	my ($self, $data_ref) = @_;
	my $d = $u->parseXML($data_ref);
	unless (defined $d) {
		$self->error($u->error());
	}
	return $d;
}

sub code2CgiStatus {
	my ($self, $code) = @_;
	my $s = status_message($code);
	unless (defined $s && length($s)) {
		$code = 500;
		$s = 'Internal Server Error';
	}
	return $code . ' ' . $s;
}

sub code2str {
	my ($self, $code) = @_;
	my $s = status_message($code);
	unless (defined $s && length($s)) {
		$s = 'Internal Server Error';
	}
	return $s;
}

sub getCheckParams {
	my ($self, $req) = @_;
	$self->error('');

	# we support only few request methods...
	my $method = $req->getReqMethod();
	return undef unless ($self->isSupportedMethod($method));
	
	# always check parameters as if request method
	# would be GET
	my $data = $self->_getCheckParamsGet($req);
	return undef unless (defined $data);
	
	# POST request method is special case
	if ($method eq 'POST') {
		$data = $self->_getCheckParamsPost($req, $data);
	}

	# print "RETURNED STRUCT: ", Dumper($data), "\n";
	
	return $data;
}

sub getReqMethod {
	my ($self, $req) = @_;

	unless (defined $req && blessed($req) && $req->can('method')) {
		$self->error("Invalid request object.");
		return undef;
	}
	
	return uc($req->method());
}

sub isSupportedMethod {
	my ($self, $method) = @_;
	unless (defined $method && length($method)) {
		$self->error("Undefined HTTP request method.");
		return 0;
	}
	$method = lc($method);
	return 1 if ($method eq 'get' || $method eq 'post');

	$self->error("Unsupported request method: $method");
	return 0;
}

sub isBrowser {
	my ($self, $ua) = @_;
	return 0 unless (defined $ua && length($ua));
	return ($ua =~ m/(?:mozilla|opera|msie|konqueror|epiphany|gecko)/i) ? 1 : 0;
}

sub getRequestPath {
	my ($self, $req) = @_;
	return undef unless (defined $req && blessed($req));
	
	my $path = undef;
	if ($req->can('path_info')) {
		$path = $req->path_info();
	}
	elsif ($req->can('uri')) {
		$path = $req->uri()->path();
	}
	
	$path = urldecode($path) if (defined $path);
	return $path;
}

sub getCheckOutputType {
	my ($self, $req) = @_;
	my $type = undef;
	
	# request method
	my $method = $self->_getRequestMethod($req);
	$method = lc($method);
	unless (defined $method) {
		$self->error("Undefined request method");
		return undef;
	}
	
	# Accept: request header
	my $accept = $self->_getRequestHeader($req, 'Accept');
	$accept = undef if (defined $accept && $accept =~ m/\*/);

	# Content-Type: request header
	my $ct = ($req->can('content_type')) ? $req->content_type() : undef;
	$ct = (defined $ct) ? $ct : $self->_getRequestHeader($req, 'Content-Type');

	# output_type URI parameter
	my $ot = $self->_getQueryParam($req, 'output_type');

	my $ua = $self->_getRequestHeader($req, 'User-Agent');
	# $log->info("method: '$method', accept: '$accept', ct: '$ct', output_type: '$ot', ua: '$ua'");
	
	# query parameter has the highest priority
	$type = (defined $ot && length $ot) ? $ot : undef;

	# module suffix...
	my $path = $self->getRequestPath($req);
	if (defined $path && $path =~ m/\.(\w+)\/*$/) {
		$type = $1;
	}

	# do we have Accept?
	unless (defined $type) {
		if (defined $accept && length $accept) {
			if ($accept =~ m/\/+(.+)$/i) {
				$type = $1;
			}
		}
	}
	
	# POST and Content-Type?
	if (! defined $type && ($method eq 'post' || $method eq 'put') && defined $ct) {
		if ($ct =~ /\/(.+)$/) {
			$type = $1;
		}
	}

	# select default renderer just if
	# nothing appropriate was detected...
	unless (defined $type) {
		$type = "HTML" if ($self->isBrowser($ua));	
		$type = 'PLAIN' unless (defined $type);
	}

	$type = uc($type) if (defined $type);
	return $type;
}

# this method translates HTTP::Request object
# to check hashref
sub checkParamsFromReq {
	my ($self, $req) = @_;
	$self->error('');
	unless (defined $req && blessed($req)) {
		$self->error("Invalid request object.");
		return undef;
	}
	
	# we only support GET and POST
	# request methods...
	my $method = $self->getReqMethod($req);
	return undef unless ($self->isSupportedMethod($method));
	
	# always check parameters as if request method
	# would be GET
	my $data = $self->_getCheckParamsGet($req);
	
	# POST request method is special case
	if ($method eq 'POST') {
		$data = $self->_getCheckParamsPost($req, $data);
	}
	
	return $data;
}

sub _getCheckParamsGet {
	my ($self, $req) = @_;

	# get URI and query string...
	my ($uri, $qs) = (undef, undef);
	if ($req->can('uri')) {
		$uri = $req->uri()->path();
		$qs = $req->uri()->query();
	}
	elsif ($req->can('path_info')) {
		$uri = $req->path_info();
		if ($req->can('query_string')) {
			$qs = $req->query_string();
			$qs =~ s/;/&/g if (defined $qs);
		}
	}
	
	# urldecode URI
	$uri = '/' unless (defined $uri && length($uri));
	$uri = urldecode($uri);
	$uri = '/' . $uri unless ($uri =~ m/^\//);

	# split URI by slashes
	my @uri = split(/\/+/, $uri);
	
	# urldecode query string
	my %qs = ();
	if (defined $qs && length $qs) {
		%qs = ();
		# urldecode parameters
		map {
			my ($key, $val) = split(/\s*=\s*/, $_, 2);
			if (defined $key && defined $val) {
				$key = urldecode($key);
				$val = urldecode($val);
				$qs{$key} = $val;
			}
		} split(/&/, $qs);
	}

	my $module = undef;
	my $params = {};
	
	# select check module...
	if (@uri) {
		$module = pop(@uri);		
		# /<MODULE>.<output_type> ?
		if ($module =~ m/^(\w+)\./) {
			$module = $1
		}
	}
	if (exists($qs{module})) {
		$module = $qs{module};
		delete($qs{module});
	}

	# replace params from query string
	map { $params->{$_} = $qs{$_} } keys %qs;

	# result structure
	return {
		module => $module,
		params => $params,
	};
}

sub _getCheckParamsPost {
	my ($self, $req, $data) = @_;
	
	# get content-type
	my $ct = ($req->can('content_type')) ? $req->content_type() : undef;
	$ct = (! defined $ct && $req->can('header')) ? $req->header('Content-Type') : $ct;
	$ct = '' unless (defined $ct);
	
	unless (defined $ct && length($ct) > 0) {
		$self->error("Missing Content-Type request header.");
		return undef;
	}

	# get request body content
	my $content = undef;
	if ($req->can('decoded_content')) {
		$content = $req->decoded_content();
	}
	elsif ($req->can('param')) {
		# remove POSTDATA if req is CGI
		delete($data->{POSTDATA}) if ($req->isa('CGI'));
		$content = $req->param('POSTDATA');
		$content = $self->urldecode($content);
	}
	
	# post data...
	my $p = undef;
	
	# JSON?
	if ($ct =~ m/^(?:text|application)\/json/i) {
		$p = $self->parseJSON(\ $content);
		return undef unless (defined $p);
	}
	# XML?
	elsif ($ct =~ m/^(?:text|application)\/xml/i) {
		$p = $self->parseXML($content);
		return undef unless (defined $p);
	}
	# other content_type?
	else {
		$self->error("Invalid/unsupported POST content-type: $ct");
		return undef;
	}

	# merge post data with current data...
	$self->mergeReqParams($data, $p);

	return $data;
}

sub mergeReqParams {
	my ($self, $dst, $src) = @_;

	return undef unless (defined $dst && ref($dst) eq 'HASH');
	return undef unless (defined $src && ref($src) eq 'HASH');

	# module selection...
	#if (exists($src->{module}) && defined $src->{module} && ref($src->{params}) eq '') {
	#	$dst->{module} = $src->{module}
	#}

	# copy params
	if (ref($src) eq 'HASH') {
		map {
			$dst->{params}->{$_} = $src->{$_};
		} keys %{$src};
	}

	return $dst;
}

sub str_addr {
	my ($self, $sock) = @_;
	
	if (defined $sock && blessed($sock)) {
		# socket?
		if ($sock->isa('IO::Socket')) {
			# unix domain socket
			if ($sock->can('hostpath')) {
				return $sock->hostpath();
			} else {
				return '[' . $sock->peerhost() . ']:' . $sock->peerport();
			}
		}
		# CGI?
		elsif ($sock->isa('CGI')) {
			my $s = '[' . $sock->remote_addr() . ']';
			$s .= ':' . $ENV{REMOTE_PORT} if (exists($ENV{REMOTE_PORT}));
			return $s;
		}
	}
	
	return '';
}

sub renderDoc {
	my ($self, $pkg, $prefix) = @_;
	$prefix = '/' unless (defined $prefix && length $prefix);

	# load renderer class
	eval { require P9::AA::PodRenderer };
	return undef if ($@);

	# render package documentation
	no warnings;
	local $HtmlRend::PREFIX = $prefix;
	return P9::AA::PodRenderer->new()->render($pkg);
}

sub getBaseUrl {
	my $self = shift;
	my $u = P9::AA::Util->new();
	return $u->getBaseUrl(@_);
}

sub _getRequestMethod {
	my ($self, $req) = @_;
	return undef unless (defined $req && blessed $req);
	my $m = undef;
	if ($req->can('method')) {
		$m = $req->method();
	}
	elsif ($req->can('request_method')) {
		$m = $req->request_method();
	}

	return $m;
}

sub _getRequestHeader {
	my ($self, $req, $name) = @_;
	return undef unless (defined $req && blessed($req) && defined $name);
	my $v = undef;

	if ($req->isa('CGI') && $req->can('http')) {
		$v = $req->http($name);
	}
	elsif ($req->can('header')) {
		$v = $req->header($name);
	}
	return $v;
}

sub _getQueryParam {
	my ($self, $req, $name) = @_;
	return undef unless (defined $req && blessed($req) && defined $name);
	my $v = undef;
	if ($req->can('url_param')) {
		$v = $req->url_param($name);
	}
	elsif ($req->can('uri')) {
		$v = $req->uri()->query_param($name);
	}
	return $v;
}

1;