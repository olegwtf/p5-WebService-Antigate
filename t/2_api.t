#!/usr/bin/env perl

use strict;
use Test::More;
use WebService::Antigate;
use IO::Socket;

use constant API_KEY      => 'd41d8cd98f00b204e9800998ecf8427e';
use constant CAPTCHA_ID   => 15;
use constant CAPTCHA_TEXT => 'txet_ahctpac';
use constant BALANCE      => 10;

if( $^O eq 'MSWin32' ) {
	plan skip_all => 'Windows still does not support fork()';
}

my ($pid, $host, $port) = make_api_server();
my $recognizer = WebService::Antigate->new(key => API_KEY, domain => "$host:$port", delay => 1);
if (index($recognizer->ua->get("http://$host:$port")->content, 'squid') != -1) {
	plan skip_all => 'You are behind squid';
	kill 15, $pid;
}

is($recognizer->recognize(CAPTCHA_ID), CAPTCHA_TEXT, '->recognize(CAPTCHA_ID)');
is($recognizer->recognize(CAPTCHA_ID+1), undef, '->recognize(CAPTCHA_ID+1)');

is($recognizer->abuse(CAPTCHA_ID), 1, '->abuse(CAPTCHA_ID)');
is($recognizer->abuse(CAPTCHA_ID+1), undef, '->abuse(CAPTCHA_ID+1)');

is($recognizer->balance, BALANCE, '->balance()');
$recognizer->key('b026324c6904b2a9cb4b88d6d61c81d1');
is($recognizer->balance, undef, '->balance() & bad key');

kill 15, $pid;

done_testing();

sub make_api_server {
	my $serv = IO::Socket::INET->new(Listen => 3)
		or die $@;
	
	my $child = fork;
	die 'fork: ', $! unless defined $child;
	
	if ($child == 0) {
		while (1) {
			my $client = $serv->accept()
				or next;
			
			my $headers;
			while (1) {
				$client->sysread($headers, 1024, length $headers)
					or last;
				if (rindex($headers, "\015\012\015\012") != -1) {
					last;
				}
			}
			
			my ($path, $query) = $headers =~ /GET\s+([^?]+)\?(\S+)/
				or next;
			my %params;
			foreach my $kv (split '&', $query) {
				my ($k, $v) = split '=', $kv;
				$params{$k} = $v;
			}
			
			my $response;
			if ($params{key} ne API_KEY) {
				$response = 'ERROR_KEY_DOES_NOT_EXIST';
			}
			else {
				if ($params{action} eq 'get') {
					if ($params{id} == CAPTCHA_ID) {
						$response = 'OK|' . CAPTCHA_TEXT;
					}
					else {
						$response = 'ERROR_NO_SUCH_CAPCHA_ID';
					}
				}
				elsif ($params{action} eq 'reportbad') {
					if ($params{id} == CAPTCHA_ID) {
						$response = 'OK_REPORT_RECORDED';
					}
					else {
						$response = 'ERROR_NO_SUCH_CAPCHA_ID';
					}
				}
				elsif ($params{action} eq 'getbalance') {
					$response = BALANCE;
				}
			}
			
			$client->syswrite(
				join(
					"\015\012",
					"HTTP/1.1 200 OK",
					"Connection: close",
					"Content-Type: text/html",
					"\015\012"
				) . $response
			);
			$client->close();
		}
		
		exit;
	}
	
	return ($child, $serv->sockhost eq "0.0.0.0" ? "127.0.0.1" : $serv->sockhost, $serv->sockport);
}

